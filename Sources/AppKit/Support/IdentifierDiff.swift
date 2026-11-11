// The difference between two orderings of unique identifiers, shared by the diffable data
// sources (ADR-0029).
//
// A Heckel-style diff: because every identifier occurs at most once on each side, a hash table
// pairs each surviving element with its old and new position in one pass (Heckel's "unique
// lines" step, which here covers every line). The elements that keep their place are then the
// longest increasing subsequence of the old positions taken in new order — the longest common
// subsequence of the two orderings, found in O(n log n) — and every other surviving element is a
// move. This gives the fewest moves possible, which is what a table or collection view should
// animate.

import Foundation

/// The edit script that turns `old` into `new` (both free of duplicates).
///
/// Deletes are old indices, inserts new indices; a move pairs an element's old index with its new
/// one. Elements in neither `moves` nor the inserts/deletes keep their place: `stays` pairs their
/// old and new indices, ascending on both sides.
internal struct _IdentifierDiff: Equatable {
    var deletes: [Int] = []                       // old indices, ascending
    var inserts: [Int] = []                       // new indices, ascending
    var moves: [(from: Int, to: Int)] = []        // ascending by `to`
    var stays: [(from: Int, to: Int)] = []        // ascending on both

    var isEmpty: Bool { deletes.isEmpty && inserts.isEmpty && moves.isEmpty }

    static func == (a: _IdentifierDiff, b: _IdentifierDiff) -> Bool {
        a.deletes == b.deletes && a.inserts == b.inserts
            && a.moves.map { [$0.from, $0.to] } == b.moves.map { [$0.from, $0.to] }
            && a.stays.map { [$0.from, $0.to] } == b.stays.map { [$0.from, $0.to] }
    }

    init() { }

    init<T: Hashable>(from old: [T], to new: [T]) {
        var oldIndex: [T: Int] = [:]
        oldIndex.reserveCapacity(old.count)
        for (i, e) in old.enumerated() {
            precondition(oldIndex.updateValue(i, forKey: e) == nil, "IdentifierDiff: duplicate identifier \(e) in the old ordering")
        }
        // Surviving elements in new order, with their old position.
        var matched: [(from: Int, to: Int)] = []
        var survivors = Set<Int>()
        var seenNew = Set<T>()
        for (j, e) in new.enumerated() {
            precondition(seenNew.insert(e).inserted, "IdentifierDiff: duplicate identifier \(e) in the new ordering")
            if let i = oldIndex[e] { matched.append((i, j)); survivors.insert(i) } else { inserts.append(j) }
        }
        deletes = old.indices.filter { !survivors.contains($0) }
        let keep = Self.longestIncreasingRun(matched.map { $0.from })
        for (k, m) in matched.enumerated() {
            if keep.contains(k) { stays.append(m) } else { moves.append(m) }
        }
    }

    /// The positions (in `values`) of one longest strictly increasing subsequence (patience sort).
    static func longestIncreasingRun(_ values: [Int]) -> Set<Int> {
        guard !values.isEmpty else { return [] }
        var tails: [Int] = []             // index into values of the smallest tail of each length
        var previous = [Int](repeating: -1, count: values.count)
        for (k, v) in values.enumerated() {
            var lo = 0, hi = tails.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if values[tails[mid]] < v { lo = mid + 1 } else { hi = mid }
            }
            if lo > 0 { previous[k] = tails[lo - 1] }
            if lo == tails.count { tails.append(k) } else { tails[lo] = k }
        }
        var out = Set<Int>()
        var k = tails[tails.count - 1]
        while k >= 0 { out.insert(k); k = previous[k] }
        return out
    }
}

/// One step of a sequential edit script, in the coordinates of the list as it is when the step
/// runs (the convention of `NSTableView`'s `insertRows`/`removeRows`/`moveRow` inside
/// `beginUpdates`/`endUpdates`).
internal enum _SequentialEdit: Equatable {
    case remove(IndexSet)
    case insert(IndexSet)
    case move(from: Int, to: Int)
}

extension _IdentifierDiff {
    /// The diff as sequential steps: one removal of every deleted element, then, in new order,
    /// each insert (runs merged) and each move placed right after its new predecessor. Applying
    /// the steps to `old` yields `new` exactly.
    static func sequentialEdits<T: Hashable>(from old: [T], to new: [T]) -> [_SequentialEdit] {
        let diff = _IdentifierDiff(from: old, to: new)
        guard !diff.isEmpty else { return [] }
        var edits: [_SequentialEdit] = []
        var current = old
        if !diff.deletes.isEmpty {
            edits.append(.remove(IndexSet(diff.deletes)))
            for i in diff.deletes.reversed() { current.remove(at: i) }
        }
        let inserted = Set(diff.inserts)
        let moved = Set(diff.moves.map { $0.to })
        var run: (start: Int, count: Int)?
        func flush() {
            if let r = run { edits.append(.insert(IndexSet(integersIn: r.start..<(r.start + r.count)))) }
            run = nil
        }
        // The position right after the element that precedes `j` in the new ordering.
        func slot(_ j: Int) -> Int { j == 0 ? 0 : current.firstIndex(of: new[j - 1])! + 1 }
        for j in new.indices {
            if inserted.contains(j) {
                let p = slot(j)
                if let r = run, r.start + r.count == p { run = (r.start, r.count + 1) } else { flush(); run = (p, 1) }
                current.insert(new[j], at: p)
            } else if moved.contains(j) {
                flush()
                let from = current.firstIndex(of: new[j])!
                var to = slot(j)
                if from < to { to -= 1 }
                if from != to {
                    edits.append(.move(from: from, to: to))
                    current.insert(current.remove(at: from), at: to)
                }
            }
        }
        flush()
        assert(current == new, "IdentifierDiff: sequential edits did not reproduce the new ordering")
        return edits
    }
}
