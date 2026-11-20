// Alert sheets styled as on macOS 11 and later: SwiftUI's confirmationDialog as a 260pt
// alert sheet centred on its window, the app icon, stacked buttons with a red destructive
// one that is never the default, Cancel on Escape, and the parent dimmed while it is up.

import XCTest
@testable import AppKit
@testable import SwiftUI

@MainActor
private func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }
@MainActor
private func buttons(_ v: NSView) -> [NSButton] { allViews(v).compactMap { $0 as? NSButton } }

/// RGBA bytes of an image, top row first.
private func rgba(_ image: CGImage) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let space = CGColorSpaceCreateDeviceRGB()
    data.withUnsafeMutableBytes { buf in
        let ctx = CGContext(data: buf.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return data
}

@MainActor
private func snapshot(_ w: NSWindow) -> CGImage? {
    w.display()
    return (w._platformWindow as? HostWindow)?.lastImage
}

/// Mean brightness (0...255) of an image's pixels.
private func brightness(_ image: CGImage) -> Double {
    let d = rgba(image)
    var sum = 0
    for i in stride(from: 0, to: d.count, by: 4) { sum += Int(d[i]) + Int(d[i + 1]) + Int(d[i + 2]) }
    return Double(sum) / Double(d.count / 4 * 3)
}

private final class Log { var pressed: [String] = [] }

private struct DeleteDialog: View {
    @State var pending: String? = nil
    let log: Log
    var body: some View {
        Button("Ask") { pending = "Production" }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .confirmationDialog("Delete “\(pending ?? "")”?",
                                isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                                presenting: pending) { name in
                Button("Delete Channel", role: .destructive) { log.pressed.append("delete \(name)") }
                Button("Cancel", role: .cancel) { log.pressed.append("cancel") }
            } message: { _ in
                Text("The channel and its on-screen transcript are removed.")
            }
    }
}

final class AlertSheetStyleTests: XCTestCase, @unchecked Sendable {
    private var savedDuration: TimeInterval = 0

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            savedDuration = NSWindow._sheetAnimationDuration
            NSWindow._sheetAnimationDuration = 0
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated { NSWindow._sheetAnimationDuration = savedDuration }
        super.tearDown()
    }

    @MainActor private func host<V: View>(_ view: V) -> (NSWindow, NSHostingView<V>) {
        let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 700, height: 500), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        let h = NSHostingView(rootView: view)
        h.frame = w.contentView!.bounds
        h.autoresizingMask = [.width, .height]
        w.contentView!.addSubview(h)
        w.makeKeyAndOrderFront(nil)
        h.layoutSubtreeIfNeeded()
        return (w, h)
    }

    func testConfirmationDialogIsACentredAlertSheetWithStackedButtons() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let log = Log()
            let (w, h) = host(DeleteDialog(log: log))
            let before = snapshot(w).map(brightness)
            buttons(h).first { $0.title == "Ask" }?.performClick(nil)
            h.layoutSubtreeIfNeeded()
            guard let panel = w.attachedSheet else { return XCTFail("the dialog is a sheet on the window") }
            XCTAssertEqual(panel.frame.width, NSAlert._width, "a narrow alert, as on macOS 11 and later")
            XCTAssertEqual(panel.frame.midX, w.frame.midX, accuracy: 1, "centred across the window")
            XCTAssertEqual(panel.frame.midY, w.frame.midY, accuracy: 1, "centred down the window, as macOS 26 shows alert sheets")
            XCTAssertTrue(panel.frame.maxY <= w.frame.minY + w.contentLayoutRect.maxY, "never over the title band")

            let bs = buttons(panel.contentView!)
            guard let delete = bs.first(where: { $0.title == "Delete Channel" }), let cancel = bs.first(where: { $0.title == "Cancel" }) else {
                return XCTFail("both actions are buttons: \(bs.map(\.title))")
            }
            XCTAssertEqual(delete.frame.minX, cancel.frame.minX, "stacked")
            XCTAssertEqual(delete.frame.width, cancel.frame.width)
            XCTAssertEqual(delete.frame.width, NSAlert._width - 32, "across the alert")
            XCTAssertGreaterThan(delete.frame.minY, cancel.frame.maxY, "the first action on top")
            XCTAssertTrue(delete.hasDestructiveAction)
            XCTAssertEqual(delete.keyEquivalent, "", "a destructive action is not the default button")
            XCTAssertEqual(cancel.keyEquivalent, "\u{1B}")
            XCTAssertTrue(allViews(panel.contentView!).contains { $0 is NSTextField && ($0 as! NSTextField).stringValue == "Delete “Production”?" })

            // The parent is drawn dimmed behind the sheet.
            if let before, let during = snapshot(w).map(brightness) {
                XCTAssertLessThan(during, before - 10, "the window dims behind its sheet (\(before) -> \(during))")
            } else { XCTFail("no parent image") }

            // The destructive title is drawn in red.
            if let image = snapshot(panel) {
                let d = rgba(image)
                var red = 0
                for i in stride(from: 0, to: d.count, by: 4) where d[i] > 170 && d[i + 1] < 110 && d[i + 2] < 110 { red += 1 }
                XCTAssertGreaterThan(red, 10, "red text on the destructive button")
            } else { XCTFail("no panel image") }

            // Escape is Cancel; the dim goes with the sheet.
            (panel._platformWindow as! HostWindow).inject(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                                                                           characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53)!)
            XCTAssertEqual(log.pressed, ["cancel"])
            XCTAssertNil(w.attachedSheet)
            if let before, let after = snapshot(w).map(brightness) { XCTAssertEqual(after, before, accuracy: 0.5) }

            // The destructive action runs with the presented data.
            buttons(h).first { $0.title == "Ask" }?.performClick(nil)
            h.layoutSubtreeIfNeeded()
            buttons(w.attachedSheet!.contentView!).first { $0.title == "Delete Channel" }?.performClick(nil)
            XCTAssertEqual(log.pressed, ["cancel", "delete Production"])
            XCTAssertNil(w.attachedSheet)
            w.close()
        }
    }

    func testConfirmationDialogAddsCancelWhenNoActionHasTheRole() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Root: View {
                @State var ask = false
                var body: some View {
                    Button("Ask") { ask = true }
                        .confirmationDialog("Clear?", isPresented: $ask) {
                            Button("Clear", role: .destructive) {}
                        }
                }
            }
            let (w, h) = host(Root())
            buttons(h).first { $0.title == "Ask" }?.performClick(nil)
            h.layoutSubtreeIfNeeded()
            guard let panel = w.attachedSheet else { return XCTFail("no sheet") }
            let titles = buttons(panel.contentView!).sorted { $0.frame.minY > $1.frame.minY }.map(\.title)
            XCTAssertEqual(titles, ["Clear", "Cancel"])
            w.close()
        }
    }

    func testTwoPlainButtonsSitSideBySideWithTheDefaultOnTheRight() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let alert = NSAlert()
            alert.messageText = "Save changes?"
            _ = alert.addButton(withTitle: "Save")
            _ = alert.addButton(withTitle: "Cancel")
            alert.layout()
            let (save, cancel) = (alert.buttons[0], alert.buttons[1])
            XCTAssertEqual(save.keyEquivalent, "\r")
            XCTAssertEqual(cancel.keyEquivalent, "\u{1B}", "a button titled Cancel takes Escape, as in AppKit")
            XCTAssertEqual(save.frame.minY, cancel.frame.minY)
            XCTAssertGreaterThan(save.frame.minX, cancel.frame.maxX, "the default button on the right")
            XCTAssertEqual(alert.window.frame.width, NSAlert._width)
            // Three buttons stack.
            let three = NSAlert()
            for t in ["Save", "Cancel", "Don't Save"] { _ = three.addButton(withTitle: t) }
            three.layout()
            XCTAssertEqual(Set(three.buttons.map(\.frame.minX)).count, 1)
            XCTAssertEqual(three.buttons[2].keyEquivalent, "d")
            XCTAssertEqual(three.buttons[2].keyEquivalentModifierMask, [.command])
        }
    }
}
