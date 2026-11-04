// Calculator: a SwiftUI App with a WindowGroup, a grid of buttons, keyboard input and a
// fixed-size window under the standard application menu bar. Builds against this package
// on Windows and Linux and against Apple's SwiftUI on macOS unchanged.

import SwiftUI

/// The calculator's state machine: a display string, a pending operator and its operand.
final class CalculatorModel: ObservableObject {
    @Published var display = "0"
    @Published var history = ""
    private var accumulator: Double? = nil
    private var pendingOperator: String? = nil
    private var startsNewNumber = true

    func press(_ key: String) {
        switch key {
        case "0"..."9": appendDigit(key)
        case ".": appendPoint()
        case "+", "−", "×", "÷": applyOperator(key)
        case "=": equals()
        case "C": clear()
        case "±": negate()
        case "%": percent()
        case "⌫": backspace()
        default: break
        }
    }

    private var current: Double { Double(display) ?? 0 }

    private func appendDigit(_ d: String) {
        if startsNewNumber || display == "0" { display = d } else { display += d }
        startsNewNumber = false
    }

    private func appendPoint() {
        if startsNewNumber { display = "0." } else if !display.contains(".") { display += "." }
        startsNewNumber = false
    }

    private func applyOperator(_ op: String) {
        if !startsNewNumber { commitPending() }
        accumulator = current
        pendingOperator = op
        history = "\(format(current)) \(op)"
        startsNewNumber = true
    }

    private func commitPending() {
        guard let a = accumulator, let op = pendingOperator else { return }
        let b = current
        let r: Double
        switch op {
        case "+": r = a + b
        case "−": r = a - b
        case "×": r = a * b
        default: r = b == 0 ? .nan : a / b
        }
        display = format(r)
        accumulator = r
    }

    private func equals() {
        guard let op = pendingOperator, let a = accumulator else { return }
        history = "\(format(a)) \(op) \(format(current)) ="
        commitPending()
        accumulator = nil
        pendingOperator = nil
        startsNewNumber = true
    }

    func clear() {
        display = "0"; history = ""
        accumulator = nil; pendingOperator = nil; startsNewNumber = true
    }

    private func negate() { if current != 0 { display = format(-current) } }
    private func percent() { display = format(current / 100); startsNewNumber = true }
    private func backspace() {
        guard !startsNewNumber, display.count > 1 else { display = "0"; startsNewNumber = true; return }
        display.removeLast()
    }

    private func format(_ v: Double) -> String {
        if v.isNaN { return "Error" }
        if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
        var s = String(format: "%.10g", v)
        if s.contains(".") { while s.hasSuffix("0") { s.removeLast() } }
        return s
    }
}

/// One shared model: the window shows it and the Calculator menu's commands clear it.
@MainActor let calculator = CalculatorModel()

struct CalculatorView: View {
    @ObservedObject var model: CalculatorModel
    /// Rows of keys with the plain keyboard key that presses each (nil: no shortcut).
    let rows: [[(label: String, key: KeyEquivalent?)]] = [
        [("C", .escape), ("±", nil), ("%", "%"), ("÷", "/")],
        [("7", "7"), ("8", "8"), ("9", "9"), ("×", "*")],
        [("4", "4"), ("5", "5"), ("6", "6"), ("−", "-")],
        [("1", "1"), ("2", "2"), ("3", "3"), ("+", "+")],
        [("0", "0"), (".", "."), ("⌫", .delete), ("=", .return)],
    ]

    var body: some View {
        VStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(model.history.isEmpty ? " " : model.history)
                    .font(.caption).foregroundColor(.secondary)
                Text(model.display)
                    .font(.system(size: 34, weight: .light))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 8)
            .accessibilityLabel("Display")
            ForEach(0..<rows.count, id: \.self) { r in
                HStack(spacing: 8) {
                    ForEach(0..<rows[r].count, id: \.self) { c in
                        key(rows[r][c].label, shortcut: rows[r][c].key)
                    }
                }
            }
            Text("Type digits and + − × ÷, Return for =, Esc clears.")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(16)
        .frame(width: 280)
    }

    func key(_ label: String, shortcut: KeyEquivalent?) -> some View {
        let isOperator = ["÷", "×", "−", "+", "="].contains(label)
        let button = Button(action: { model.press(label) }) {
            Text(label)
                .font(.system(size: 18))
                .frame(width: 52, height: 40)
        }
        .foregroundColor(isOperator ? .accentColor : .primary)
        // A plain key (no modifiers) presses the button, as on macOS; `Group` keeps one type.
        return Group {
            if let shortcut { button.keyboardShortcut(shortcut, modifiers: []) } else { button }
        }
    }
}

@main
struct CalculatorApp: App {
    var body: some Scene {
        WindowGroup("Calculator") {
            CalculatorView(model: calculator)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("Calculator") {
                Button("Clear") { calculator.clear() }.keyboardShortcut("k")
                Button("Copy Result") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(calculator.display, forType: .string)
                }.keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
    }
}
