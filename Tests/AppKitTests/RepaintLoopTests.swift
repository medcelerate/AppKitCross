// A window whose paint invalidates itself paints forever (the Windows pump then never
// leaves its message loop). The Controls tab's rows, with the indeterminate bar and
// spinner animating, must settle: after a frame's tick and paint, nothing is dirty.

import XCTest
@testable import AppKit
#if canImport(QuartzCore)
import QuartzCore
#endif

final class RepaintLoopTests: XCTestCase {
    func testControlsRowsSettleAfterEachFrame() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            var clock: CFTimeInterval = 100
            let savedNow = CARuntime.now
            CARuntime.now = { clock }
            defer { CARuntime.now = savedNow }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
            w.backgroundColor = .white
            w.makeKeyAndOrderFront(nil)
            let root = w.contentView!
            let stack = NSStackView()
            stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(stack)
            @MainActor func row(_ label: String, _ views: [NSView]) -> NSStackView {
                let r = NSStackView(); r.orientation = .horizontal; r.spacing = 8
                let l = NSTextField(labelWithString: label)
                l.setContentHuggingPriority(.required, for: .horizontal)
                r.addArrangedSubview(l)
                for v in views { r.addArrangedSubview(v) }
                return r
            }
            let search = NSSearchField(frame: .zero); search.widthAnchor.constraint(equalToConstant: 200).isActive = true
            stack.addArrangedSubview(row("Search:", [search]))
            let tokens = NSTokenField(frame: .zero); tokens.objectValue = ["Mercury", "Venus"]; tokens.widthAnchor.constraint(equalToConstant: 280).isActive = true
            stack.addArrangedSubview(row("Tokens:", [tokens]))
            let path = NSPathControl(frame: .zero); path.url = URL(fileURLWithPath: "/Users/jane/Documents/Planets/Mars.txt"); path.widthAnchor.constraint(equalToConstant: 300).isActive = true
            stack.addArrangedSubview(row("Path:", [path]))
            let stepper = NSStepper(frame: .zero); stepper.maxValue = 10; stepper.integerValue = 3
            let value = NSTextField(frame: .zero); value.integerValue = 3; value.widthAnchor.constraint(equalToConstant: 40).isActive = true
            let capacity = NSLevelIndicator(frame: .zero); capacity.levelIndicatorStyle = .discreteCapacity; capacity.maxValue = 10; capacity.integerValue = 3
            capacity.widthAnchor.constraint(equalToConstant: 120).isActive = true; capacity.numberOfTickMarks = 11
            stack.addArrangedSubview(row("Stepper:", [stepper, value, capacity]))
            let rating = NSLevelIndicator(frame: .zero); rating.levelIndicatorStyle = .rating; rating.maxValue = 5; rating.integerValue = 4
            let relevancy = NSLevelIndicator(frame: .zero); relevancy.levelIndicatorStyle = .relevancy; relevancy.maxValue = 100; relevancy.doubleValue = 65
            relevancy.widthAnchor.constraint(equalToConstant: 100).isActive = true
            stack.addArrangedSubview(row("Levels:", [rating, relevancy]))
            let bar = NSProgressIndicator(frame: .zero); bar.isIndeterminate = false; bar.maxValue = 100; bar.doubleValue = 30
            bar.widthAnchor.constraint(equalToConstant: 160).isActive = true
            let busy = NSProgressIndicator(frame: .zero); busy.isIndeterminate = true; busy.widthAnchor.constraint(equalToConstant: 100).isActive = true
            busy.startAnimation(nil)
            let spinner = NSProgressIndicator(frame: .zero); spinner.style = .spinning; spinner.controlSize = .small; spinner.startAnimation(nil)
            stack.addArrangedSubview(row("Progress:", [bar, busy, spinner]))
            let status = NSTextField(labelWithString: "Type in the search field; tokens split on commas.")
            status.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(status)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
                stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -12),
                status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
                status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
            ])
            let platform = Mirror(reflecting: w).descendant("_platform") as! HostWindow
            w.displayIfNeeded()
            // Two paints at most settle a fresh layout (the first applies frames).
            w.displayIfNeeded()
            XCTAssertFalse(platform._needsPaint, "the window settles after its first frames")
            for frame in 0..<12 {
                clock += 1.0 / 60; CARuntime.tick()
                w.displayIfNeeded()
                if frame == 6 {
                    // The frame after a text change re-lays the window; the frames the
                    // engine applied are shown by one more paint, and that one settles.
                    XCTAssertTrue(platform._needsPaint, "a layout change paints once more")
                    w.displayIfNeeded()
                }
                XCTAssertFalse(platform._needsPaint, "frame \(frame): a paint must not invalidate the window again")
                if frame == 5 { status.stringValue = "Stepper: 4"; value.integerValue = 4 }
            }
            // Leave the frame clock idle for the tests that follow.
            busy.stopAnimation(nil); spinner.stopAnimation(nil)
            w.close()
            XCTAssertFalse(CARuntime.hasPendingWork)
        }
    }
}

