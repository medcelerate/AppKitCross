// A Cassowary linear-constraint solver (a port of the kiwi algorithm) used by the
// Auto Layout engine. Variables are external symbols; constraints are linear
// expressions related by ==, <= or >= at a strength; the solver keeps a tableau that
// it re-optimises incrementally as constraints come and go.

import Foundation

/// A solver variable; `value` is updated by `Solver.updateVariables()`.
final class LayoutVariable: Hashable, CustomStringConvertible {
    private static var counter = 0
    let id: Int
    let name: String
    var value: Double = 0

    init(_ name: String = "") {
        LayoutVariable.counter += 1
        id = LayoutVariable.counter
        self.name = name
    }

    static func == (l: LayoutVariable, r: LayoutVariable) -> Bool { l === r }
    func hash(into h: inout Hasher) { h.combine(id) }
    var description: String { name.isEmpty ? "v\(id)" : name }
}

struct LayoutTerm {
    var variable: LayoutVariable
    var coefficient: Double
}

/// A linear expression: sum of terms plus a constant.
struct LayoutExpression {
    var terms: [LayoutTerm] = []
    var constant: Double = 0

    init(_ constant: Double = 0) { self.constant = constant }
    init(_ v: LayoutVariable, _ coefficient: Double = 1, constant: Double = 0) {
        terms = [LayoutTerm(variable: v, coefficient: coefficient)]
        self.constant = constant
    }

    static func + (l: LayoutExpression, r: LayoutExpression) -> LayoutExpression {
        var e = l
        e.terms += r.terms
        e.constant += r.constant
        return e
    }
    static func - (l: LayoutExpression, r: LayoutExpression) -> LayoutExpression { l + r * -1 }
    static func * (l: LayoutExpression, k: Double) -> LayoutExpression {
        var e = l
        e.terms = e.terms.map { LayoutTerm(variable: $0.variable, coefficient: $0.coefficient * k) }
        e.constant *= k
        return e
    }
    static func + (l: LayoutExpression, k: Double) -> LayoutExpression { var e = l; e.constant += k; return e }
    static func - (l: LayoutExpression, k: Double) -> LayoutExpression { l + (-k) }
}

enum LayoutRelation { case lessOrEqual, equal, greaterOrEqual }

enum LayoutStrength {
    static let required: Double = 1_001_001_000
    static let strong: Double = 1_000_000
    static let medium: Double = 1_000
    static let weak: Double = 1

    static func create(_ a: Double, _ b: Double, _ c: Double, _ w: Double = 1) -> Double {
        var r = 0.0
        r += max(0, min(1000, a * w)) * 1_000_000
        r += max(0, min(1000, b * w)) * 1_000
        r += max(0, min(1000, c * w))
        return r
    }

    static func clip(_ s: Double) -> Double { max(0, min(required, s)) }
}

/// A constraint handed to the solver; identity-based so it can be removed again.
final class LayoutSolverConstraint: Hashable {
    let expression: LayoutExpression
    let relation: LayoutRelation
    let strength: Double

    init(_ expression: LayoutExpression, _ relation: LayoutRelation, strength: Double = LayoutStrength.required) {
        self.expression = LayoutSolverConstraint.reduced(expression)
        self.relation = relation
        self.strength = LayoutStrength.clip(strength)
    }

    /// Merges duplicate variables so the tableau rows stay small.
    private static func reduced(_ e: LayoutExpression) -> LayoutExpression {
        var coeffs: [LayoutVariable: Double] = [:]
        var order: [LayoutVariable] = []
        for t in e.terms {
            if coeffs[t.variable] == nil { order.append(t.variable) }
            coeffs[t.variable, default: 0] += t.coefficient
        }
        var out = LayoutExpression(e.constant)
        out.terms = order.map { LayoutTerm(variable: $0, coefficient: coeffs[$0]!) }
        return out
    }

    static func == (l: LayoutSolverConstraint, r: LayoutSolverConstraint) -> Bool { l === r }
    func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }
}

enum LayoutSolverError: Error {
    case duplicateConstraint, unsatisfiableConstraint, unknownConstraint
    case duplicateEditVariable, badRequiredStrength, unknownEditVariable
}

final class LayoutSolver {
    private enum SymbolType { case invalid, external, slack, error, dummy }

    private struct Symbol: Hashable, Comparable {
        let id: Int
        let type: SymbolType
        static let invalid = Symbol(id: 0, type: .invalid)
        static func < (l: Symbol, r: Symbol) -> Bool { l.id < r.id }
    }

    private final class Row {
        var constant: Double
        var cells: [Symbol: Double] = [:]

        init(_ constant: Double = 0) { self.constant = constant }

        func copy() -> Row {
            let r = Row(constant)
            r.cells = cells
            return r
        }

        @discardableResult
        func add(_ value: Double) -> Double {
            constant += value
            return constant
        }

        func insert(_ symbol: Symbol, _ coefficient: Double = 1) {
            let c = (cells[symbol] ?? 0) + coefficient
            if LayoutSolver.nearZero(c) { cells[symbol] = nil } else { cells[symbol] = c }
        }

        func insert(_ other: Row, _ coefficient: Double = 1) {
            constant += other.constant * coefficient
            for (s, c) in other.cells { insert(s, c * coefficient) }
        }

        func remove(_ symbol: Symbol) { cells[symbol] = nil }

        func reverseSign() {
            constant = -constant
            for (s, c) in cells { cells[s] = -c }
        }

        func solveFor(_ symbol: Symbol) {
            let coeff = -1.0 / cells[symbol]!
            cells[symbol] = nil
            constant *= coeff
            for (s, c) in cells { cells[s] = c * coeff }
        }

        func solveFor(_ lhs: Symbol, _ rhs: Symbol) {
            insert(lhs, -1)
            solveFor(rhs)
        }

        func coefficient(for symbol: Symbol) -> Double { cells[symbol] ?? 0 }

        func substitute(_ symbol: Symbol, _ row: Row) {
            if let coeff = cells[symbol] {
                cells[symbol] = nil
                insert(row, coeff)
            }
        }

        /// The lowest-id symbol satisfying `where`, without sorting (the tableau is scanned
        /// on every pivot, and a sort there was most of a layout pass in a debug build).
        func firstSymbol(where ok: (Symbol, Double) -> Bool) -> Symbol {
            var found = Symbol.invalid
            for (sym, c) in cells where ok(sym, c) {
                if found.type == .invalid || sym < found { found = sym }
            }
            return found
        }
    }

    private struct Tag { var marker = Symbol.invalid; var other = Symbol.invalid }
    private struct EditInfo { var tag: Tag; var constraint: LayoutSolverConstraint; var constant: Double }

    private var constraints: [LayoutSolverConstraint: Tag] = [:]
    /// How many constraints the solver holds (for the frame trace).
    var constraintCount: Int { constraints.count }
    private var rows: [Symbol: Row] = [:]
    private var variables: [LayoutVariable: Symbol] = [:]
    private var edits: [LayoutVariable: EditInfo] = [:]
    private var infeasibleRows: [Symbol] = []
    private var objective = Row()
    private var artificial: Row?
    private var nextSymbolID = 1

    init() {}

    private func makeSymbol(_ type: SymbolType) -> Symbol {
        defer { nextSymbolID += 1 }
        return Symbol(id: nextSymbolID, type: type)
    }

    static func nearZero(_ v: Double) -> Bool { abs(v) < 1e-8 }

    // MARK: Constraints

    func addConstraint(_ constraint: LayoutSolverConstraint) throws {
        guard constraints[constraint] == nil else { throw LayoutSolverError.duplicateConstraint }
        var tag = Tag()
        let row = createRow(constraint, &tag)
        var subject = chooseSubject(row, tag)
        if subject.type == .invalid && allDummies(row) {
            if !LayoutSolver.nearZero(row.constant) { throw LayoutSolverError.unsatisfiableConstraint }
            subject = tag.marker
        }
        if subject.type == .invalid {
            if !addWithArtificialVariable(row) { throw LayoutSolverError.unsatisfiableConstraint }
        } else {
            row.solveFor(subject)
            substitute(subject, row)
            rows[subject] = row
        }
        constraints[constraint] = tag
        optimize(objective)
    }

    func removeConstraint(_ constraint: LayoutSolverConstraint) throws {
        guard let tag = constraints.removeValue(forKey: constraint) else { throw LayoutSolverError.unknownConstraint }
        removeConstraintEffects(constraint, tag)
        if rows.removeValue(forKey: tag.marker) == nil {
            let leaving = markerLeavingSymbol(tag.marker)
            guard leaving.type != .invalid, let row = rows.removeValue(forKey: leaving) else { return }
            row.solveFor(leaving, tag.marker)
            substitute(tag.marker, row)
        }
        optimize(objective)
    }

    func hasConstraint(_ constraint: LayoutSolverConstraint) -> Bool { constraints[constraint] != nil }

    private func removeConstraintEffects(_ c: LayoutSolverConstraint, _ tag: Tag) {
        if tag.marker.type == .error { removeMarkerEffects(tag.marker, c.strength) }
        if tag.other.type == .error { removeMarkerEffects(tag.other, c.strength) }
    }

    private func removeMarkerEffects(_ marker: Symbol, _ strength: Double) {
        if let row = rows[marker] { objective.insert(row, -strength) } else { objective.insert(marker, -strength) }
    }

    private func markerLeavingSymbol(_ marker: Symbol) -> Symbol {
        var r1 = Double.greatestFiniteMagnitude, r2 = Double.greatestFiniteMagnitude
        var first = Symbol.invalid, second = Symbol.invalid, third = Symbol.invalid
        for (sym, row) in rows {
            let c = row.coefficient(for: marker)
            if c == 0 { continue }
            if sym.type == .external {
                if third.type == .invalid || sym > third { third = sym }
            } else if c < 0 {
                let r = -row.constant / c
                if r < r1 || (r == r1 && sym < first) { r1 = r; first = sym }
            } else {
                let r = row.constant / c
                if r < r2 || (r == r2 && sym < second) { r2 = r; second = sym }
            }
        }
        if first.type != .invalid { return first }
        if second.type != .invalid { return second }
        return third
    }

    // MARK: Edit variables

    func addEditVariable(_ v: LayoutVariable, strength: Double) throws {
        guard edits[v] == nil else { throw LayoutSolverError.duplicateEditVariable }
        let s = LayoutStrength.clip(strength)
        guard s != LayoutStrength.required else { throw LayoutSolverError.badRequiredStrength }
        let cn = LayoutSolverConstraint(LayoutExpression(v), .equal, strength: s)
        try addConstraint(cn)
        edits[v] = EditInfo(tag: constraints[cn]!, constraint: cn, constant: 0)
    }

    func removeEditVariable(_ v: LayoutVariable) throws {
        guard let info = edits.removeValue(forKey: v) else { throw LayoutSolverError.unknownEditVariable }
        try removeConstraint(info.constraint)
    }

    func hasEditVariable(_ v: LayoutVariable) -> Bool { edits[v] != nil }

    func suggestValue(_ v: LayoutVariable, _ value: Double) throws {
        guard var info = edits[v] else { throw LayoutSolverError.unknownEditVariable }
        let delta = value - info.constant
        info.constant = value
        edits[v] = info
        if let row = rows[info.tag.marker] {
            if row.add(-delta) < 0 { infeasibleRows.append(info.tag.marker) }
            dualOptimize()
            return
        }
        if let row = rows[info.tag.other] {
            if row.add(delta) < 0 { infeasibleRows.append(info.tag.other) }
            dualOptimize()
            return
        }
        for (sym, row) in rows {
            let coeff = row.coefficient(for: info.tag.marker)
            if coeff != 0 && row.add(delta * coeff) < 0 && sym.type != .external { infeasibleRows.append(sym) }
        }
        dualOptimize()
    }

    func updateVariables() {
        for (v, sym) in variables {
            v.value = rows[sym]?.constant ?? 0
        }
    }

    // MARK: Internals

    private func symbol(for v: LayoutVariable) -> Symbol {
        if let s = variables[v] { return s }
        let s = makeSymbol(.external)
        variables[v] = s
        return s
    }

    private func createRow(_ c: LayoutSolverConstraint, _ tag: inout Tag) -> Row {
        let expr = c.expression
        let row = Row(expr.constant)
        for term in expr.terms where !LayoutSolver.nearZero(term.coefficient) {
            let sym = symbol(for: term.variable)
            if let other = rows[sym] { row.insert(other, term.coefficient) } else { row.insert(sym, term.coefficient) }
        }
        switch c.relation {
        case .lessOrEqual, .greaterOrEqual:
            let coeff: Double = c.relation == .lessOrEqual ? 1 : -1
            let slack = makeSymbol(.slack)
            tag.marker = slack
            row.insert(slack, coeff)
            if c.strength < LayoutStrength.required {
                let error = makeSymbol(.error)
                tag.other = error
                row.insert(error, -coeff)
                objective.insert(error, c.strength)
            }
        case .equal:
            if c.strength < LayoutStrength.required {
                let errplus = makeSymbol(.error), errminus = makeSymbol(.error)
                tag.marker = errplus
                tag.other = errminus
                row.insert(errplus, -1)
                row.insert(errminus, 1)
                objective.insert(errplus, c.strength)
                objective.insert(errminus, c.strength)
            } else {
                let dummy = makeSymbol(.dummy)
                tag.marker = dummy
                row.insert(dummy)
            }
        }
        if row.constant < 0 { row.reverseSign() }
        return row
    }

    private func chooseSubject(_ row: Row, _ tag: Tag) -> Symbol {
        let external = row.firstSymbol { sym, _ in sym.type == .external }
        if external.type != .invalid { return external }
        if tag.marker.type == .slack || tag.marker.type == .error {
            if row.coefficient(for: tag.marker) < 0 { return tag.marker }
        }
        if tag.other.type == .slack || tag.other.type == .error {
            if row.coefficient(for: tag.other) < 0 { return tag.other }
        }
        return .invalid
    }

    private func addWithArtificialVariable(_ row: Row) -> Bool {
        let art = makeSymbol(.slack)
        rows[art] = row.copy()
        artificial = row.copy()
        optimize(artificial!)
        let success = LayoutSolver.nearZero(artificial!.constant)
        artificial = nil
        if let r = rows.removeValue(forKey: art) {
            if r.cells.isEmpty { return success }
            let entering = anyPivotableSymbol(r)
            if entering.type == .invalid { return false }
            r.solveFor(art, entering)
            substitute(entering, r)
            rows[entering] = r
        }
        for r in rows.values { r.remove(art) }
        objective.remove(art)
        return success
    }

    private func substitute(_ symbol: Symbol, _ row: Row) {
        for (sym, r) in rows {
            r.substitute(symbol, row)
            if sym.type != .external && r.constant < 0 { infeasibleRows.append(sym) }
        }
        objective.substitute(symbol, row)
        artificial?.substitute(symbol, row)
    }

    private func optimize(_ objective: Row) {
        while true {
            let entering = enteringSymbol(objective)
            if entering.type == .invalid { return }
            let leaving = leavingSymbol(entering)
            guard leaving.type != .invalid, let row = rows.removeValue(forKey: leaving) else { return }   // unbounded: stop
            row.solveFor(leaving, entering)
            substitute(entering, row)
            rows[entering] = row
        }
    }

    private func dualOptimize() {
        while let leaving = infeasibleRows.popLast() {
            if let row = rows[leaving], row.constant < 0 {
                let entering = dualEnteringSymbol(row)
                guard entering.type != .invalid else { continue }
                rows[leaving] = nil
                row.solveFor(leaving, entering)
                substitute(entering, row)
                rows[entering] = row
            }
        }
    }

    private func enteringSymbol(_ objective: Row) -> Symbol {
        objective.firstSymbol { sym, c in sym.type != .dummy && c < 0 }
    }

    private func dualEnteringSymbol(_ row: Row) -> Symbol {
        var entering = Symbol.invalid
        var ratio = Double.greatestFiniteMagnitude
        for (sym, c) in row.cells where c > 0 && sym.type != .dummy {
            let r = objective.coefficient(for: sym) / c
            if r < ratio || (r == ratio && sym < entering) { ratio = r; entering = sym }
        }
        return entering
    }

    private func anyPivotableSymbol(_ row: Row) -> Symbol {
        row.firstSymbol { sym, _ in sym.type == .slack || sym.type == .error }
    }

    private func leavingSymbol(_ entering: Symbol) -> Symbol {
        var ratio = Double.greatestFiniteMagnitude
        var found = Symbol.invalid
        for (sym, row) in rows where sym.type != .external {
            let c = row.coefficient(for: entering)
            if c < 0 {
                let temp = -row.constant / c
                if temp < ratio || (temp == ratio && sym < found) { ratio = temp; found = sym }
            }
        }
        return found
    }

    private func allDummies(_ row: Row) -> Bool {
        row.cells.keys.allSatisfy { $0.type == .dummy }
    }
}
