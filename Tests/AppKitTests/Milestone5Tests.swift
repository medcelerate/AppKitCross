// Milestone 5: Auto Layout (Cassowary), anchors, the visual format language,
// NSStackView, and the view / window controllers.

import XCTest
@testable import AppKit

final class CassowaryTests: XCTestCase, @unchecked Sendable {
    func testSolvesEqualitiesAndInequalitiesByStrength() throws {
        try MainActor.assumeIsolated {
            let s = LayoutSolver()
            let x = LayoutVariable("x"), y = LayoutVariable("y")
            try s.addConstraint(LayoutSolverConstraint(LayoutExpression(x) - 10, .equal))                      // x == 10
            try s.addConstraint(LayoutSolverConstraint(LayoutExpression(y) - LayoutExpression(x) - 5, .greaterOrEqual)) // y >= x + 5
            try s.addConstraint(LayoutSolverConstraint(LayoutExpression(y) - 12, .equal, strength: LayoutStrength.medium)) // y == 12 (medium)
            s.updateVariables()
            XCTAssertEqual(x.value, 10, accuracy: 1e-9)
            XCTAssertEqual(y.value, 15, accuracy: 1e-9)   // the required inequality wins over the medium equality
            let w = LayoutVariable("w")
            let c1 = LayoutSolverConstraint(LayoutExpression(w) - 100, .equal, strength: LayoutStrength.strong)
            let c2 = LayoutSolverConstraint(LayoutExpression(w) - 50, .equal, strength: LayoutStrength.weak)
            try s.addConstraint(c1); try s.addConstraint(c2)
            s.updateVariables()
            XCTAssertEqual(w.value, 100, accuracy: 1e-9)
            try s.removeConstraint(c1)
            s.updateVariables()
            XCTAssertEqual(w.value, 50, accuracy: 1e-9)
            // Edit variables.
            let e = LayoutVariable("e")
            try s.addEditVariable(e, strength: LayoutStrength.strong)
            try s.suggestValue(e, 42)
            s.updateVariables()
            XCTAssertEqual(e.value, 42, accuracy: 1e-9)
            try s.suggestValue(e, 7)
            s.updateVariables()
            XCTAssertEqual(e.value, 7, accuracy: 1e-9)
            // Unsatisfiable required constraint is reported.
            XCTAssertThrowsError(try s.addConstraint(LayoutSolverConstraint(LayoutExpression(x) - 11, .equal)))
        }
    }
}

final class AutoLayoutTests: XCTestCase, @unchecked Sendable {
    func testAnchorsPinAndCenterViews() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            let root = w.contentView!
            let a = NSView(), b = NSView()
            a.translatesAutoresizingMaskIntoConstraints = false
            b.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(a); root.addSubview(b)
            NSLayoutConstraint.activate([
                a.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
                a.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
                a.widthAnchor.constraint(equalToConstant: 100),
                a.heightAnchor.constraint(equalToConstant: 40),
                b.centerXAnchor.constraint(equalTo: root.centerXAnchor),
                b.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
                b.widthAnchor.constraint(equalTo: a.widthAnchor, multiplier: 0.5),
                b.heightAnchor.constraint(equalTo: a.heightAnchor),
            ])
            w.layoutIfNeeded()
            // Unflipped root: "top + 10" is 10 points below the top edge.
            XCTAssertEqual(a.frame, NSRect(x: 20, y: 150, width: 100, height: 40))
            XCTAssertEqual(b.frame, NSRect(x: 125, y: 10, width: 50, height: 40))
            XCTAssertEqual(root.constraints.count, 6)   // the two size constraints on `a` live on `a`
            XCTAssertEqual(a.constraints.count, 2)
            // Changing a constant re-solves on the next layout.
            a.constraints.first { $0.firstAttribute == .width }!.constant = 60
            w.layoutIfNeeded()
            XCTAssertEqual(a.frame.width, 60)
            XCTAssertEqual(b.frame.width, 30)
            // Resizing the window keeps the pins.
            w.setContentSize(NSSize(width: 400, height: 300))
            w.layoutIfNeeded()
            XCTAssertEqual(a.frame.minY, 250)
            XCTAssertEqual(b.frame.midX, 200)
            XCTAssertEqual(b.frame.minY, 10)
            // Deactivation removes the constraint from its holder.
            let pin = root.constraints.first { $0.firstItem === a && $0.firstAttribute == .leading }!
            pin.isActive = false
            XCTAssertEqual(root.constraints.count, 5)
            XCTAssertNil(pin._holder)
            w.close()
        }
    }

    func testFlippedSuperviewsAndIntrinsicSizes() {
        MainActor.assumeIsolated {
            final class Flipped: NSView { override var isFlipped: Bool { true } }
            final class Label: NSView {
                override var intrinsicContentSize: NSSize { NSSize(width: 80, height: 20) }
            }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            let container = Flipped(frame: NSRect(x: 10, y: 10, width: 280, height: 180))
            container.autoresizingMask = [.width, .height]
            w.contentView!.addSubview(container)
            let label = Label()
            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: container.topAnchor, constant: 5),
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 5),
            ])
            w.layoutIfNeeded()
            // Flipped container: top + 5 is y = 5; size from the intrinsic content size.
            XCTAssertEqual(label.frame, NSRect(x: 5, y: 5, width: 80, height: 20))
            // A required width wins over the intrinsic size; compression resistance holds a low-priority squeeze.
            let wide = label.widthAnchor.constraint(equalToConstant: 120)
            wide.isActive = true
            w.layoutIfNeeded()
            XCTAssertEqual(label.frame.width, 120)
            wide.isActive = false
            let narrow = label.widthAnchor.constraint(equalToConstant: 10)
            narrow.priority = .defaultLow
            narrow.isActive = true
            w.layoutIfNeeded()
            XCTAssertEqual(label.frame.width, 80, "compression resistance (750) beats a 250 width")
            label.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(100), for: .horizontal)
            w.layoutIfNeeded()
            XCTAssertEqual(label.frame.width, 10)
            w.close()
        }
    }

    func testVisualFormatAndLayoutGuides() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            let root = w.contentView!
            let a = NSView(), b = NSView()
            for v in [a, b] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
            var cs = NSLayoutConstraint.constraints(withVisualFormat: "H:|-[a(50)]-gap-[b(>=20)]-|", options: [.alignAllTop], metrics: ["gap": 30], views: ["a": a, "b": b])
            cs += NSLayoutConstraint.constraints(withVisualFormat: "V:|-10-[a(30)]", metrics: nil, views: ["a": a, "b": b])
            cs += [b.heightAnchor.constraint(equalTo: a.heightAnchor)]
            NSLayoutConstraint.activate(cs)
            w.layoutIfNeeded()
            XCTAssertEqual(a.frame, NSRect(x: 20, y: 60, width: 50, height: 30))
            XCTAssertEqual(b.frame.minX, 100)
            XCTAssertEqual(b.frame.maxX, 280)
            XCTAssertEqual(b.frame.minY, 60)   // alignAllTop
            // A layout guide centred in the root.
            let g = NSLayoutGuide()
            root.addLayoutGuide(g)
            NSLayoutConstraint.activate([
                g.widthAnchor.constraint(equalToConstant: 40), g.heightAnchor.constraint(equalToConstant: 10),
                g.centerXAnchor.constraint(equalTo: root.centerXAnchor), g.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            ])
            w.layoutIfNeeded()
            XCTAssertEqual(g.frame, NSRect(x: 130, y: 45, width: 40, height: 10))
            XCTAssertEqual(root.safeAreaLayoutGuide.owningView, root)
            w.layoutIfNeeded()
            XCTAssertEqual(root.safeAreaLayoutGuide.frame, root.bounds)
            w.close()
        }
    }

    func testFittingSizeFromConstraints() {
        MainActor.assumeIsolated {
            final class Box: NSView {
                let size: NSSize
                init(_ s: NSSize) { size = s; super.init(frame: .zero) }
                required init?(coder: NSCoder) { nil }
                override var intrinsicContentSize: NSSize { size }
            }
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
            let a = Box(NSSize(width: 50, height: 20)), b = Box(NSSize(width: 30, height: 40))
            for v in [a, b] { v.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(v) }
            NSLayoutConstraint.activate([
                a.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 5),
                a.topAnchor.constraint(equalTo: container.topAnchor, constant: 5),
                b.leadingAnchor.constraint(equalTo: a.trailingAnchor, constant: 10),
                b.topAnchor.constraint(equalTo: container.topAnchor, constant: 5),
                container.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: 5),
                container.bottomAnchor.constraint(greaterThanOrEqualTo: b.bottomAnchor, constant: 5),
            ])
            XCTAssertEqual(container.fittingSize, NSSize(width: 100, height: 50))
        }
    }
}

final class StackViewTests: XCTestCase, @unchecked Sendable {
    final class Box: NSView {
        let size: NSSize
        init(_ w: CGFloat, _ h: CGFloat) { size = NSSize(width: w, height: h); super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override var intrinsicContentSize: NSSize { size }
    }

    func testHorizontalStackPacksAndFills() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            let a = Box(40, 20), b = Box(60, 30), c = Box(50, 10)
            let stack = NSStackView(views: [a, b, c])
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.spacing = 10
            stack.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
            w.contentView!.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: w.contentView!.leadingAnchor),
                stack.topAnchor.constraint(equalTo: w.contentView!.topAnchor),
            ])
            XCTAssertEqual(stack.intrinsicContentSize, NSSize(width: 40 + 60 + 50 + 20 + 12, height: 30 + 8))
            w.layoutIfNeeded()
            XCTAssertEqual(stack.frame.size, NSSize(width: 182, height: 38))
            XCTAssertEqual(a.frame, NSRect(x: 6, y: 9, width: 40, height: 20))      // centred vertically (flipped stack)
            XCTAssertEqual(b.frame, NSRect(x: 56, y: 4, width: 60, height: 30))
            XCTAssertEqual(c.frame.minX, 126)
            // Width-constrained stack with fill: the chain still has to span the width.
            let width = stack.widthAnchor.constraint(equalToConstant: 300)
            width.isActive = true
            stack.distribution = .fillEqually
            w.layoutIfNeeded()
            XCTAssertEqual(a.frame.width, b.frame.width)
            XCTAssertEqual(b.frame.width, c.frame.width)
            XCTAssertEqual(c.frame.maxX, 294)
            stack.distribution = .equalSpacing
            w.layoutIfNeeded()
            XCTAssertEqual(a.frame.width, 40); XCTAssertEqual(c.frame.maxX, 294)
            let gap1 = b.frame.minX - a.frame.maxX, gap2 = c.frame.minX - b.frame.maxX
            XCTAssertEqual(gap1, gap2, accuracy: 1)
            XCTAssertGreaterThan(gap1, 10)
            // Hidden views are detached.
            b.isHidden = true
            w.layoutIfNeeded()
            XCTAssertEqual(stack.detachedViews.count, 1)
            XCTAssertEqual(stack.intrinsicContentSize.width, 40 + 50 + 10 + 12)
            w.close()
        }
    }

    func testVerticalStackAlignment() {
        MainActor.assumeIsolated {
            let a = Box(40, 20), b = Box(80, 10)
            let stack = NSStackView(views: [a, b])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 5
            stack.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
            stack.layoutSubtreeIfNeeded()
            XCTAssertEqual(a.frame, NSRect(x: 0, y: 0, width: 40, height: 20))
            XCTAssertEqual(b.frame, NSRect(x: 0, y: 25, width: 80, height: 10))
            stack.alignment = .width
            stack.layoutSubtreeIfNeeded()
            XCTAssertEqual(a.frame.width, 100); XCTAssertEqual(b.frame.width, 100)
        }
    }
}

final class ControllerTests: XCTestCase, @unchecked Sendable {
    final class Counting: NSViewController {
        var log: [String] = []
        override func loadView() { view = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 80)); log.append("load") }
        override func viewDidLoad() { log.append("didLoad") }
        override func viewWillAppear() { log.append("willAppear") }
        override func viewDidAppear() { log.append("didAppear") }
        override func viewWillDisappear() { log.append("willDisappear") }
        override func viewDidDisappear() { log.append("didDisappear") }
        override func viewWillLayout() { log.append("willLayout") }
        override func viewDidLayout() { log.append("didLayout") }
    }

    func testViewControllerLifecycleAndWindowSizing() {
        MainActor.assumeIsolated {
            let vc = Counting()
            vc.title = "Demo"
            XCTAssertFalse(vc.isViewLoaded)
            let w = NSWindow(contentViewController: vc)
            XCTAssertEqual(vc.log.prefix(2), ["load", "didLoad"])
            XCTAssertEqual(w.contentView, vc.view)
            XCTAssertEqual(w.contentView!.frame.size, NSSize(width: 120, height: 80))
            XCTAssertEqual(w.title, "Demo")
            XCTAssertFalse(vc.log.contains("willAppear"), "not on screen yet")
            w.makeKeyAndOrderFront(nil)
            XCTAssertTrue(vc.log.contains("willAppear") && vc.log.contains("didAppear"))
            XCTAssertTrue(vc.view.nextResponder === vc)
            w.layoutIfNeeded()
            XCTAssertTrue(vc.log.contains("didLayout"))
            // Children.
            let child = Counting()
            vc.addChild(child)
            XCTAssertTrue(child.parent === vc)
            XCTAssertEqual(vc.children.count, 1)
            child.removeFromParent()
            XCTAssertNil(child.parent)
            // Window controller.
            let wc = NSWindowController(window: w)
            XCTAssertTrue(w.windowController === wc)
            XCTAssertTrue(wc.contentViewController === vc)
            wc.showWindow(nil)
            XCTAssertTrue(w.isVisible)
            wc.close()
            XCTAssertTrue(vc.log.contains("didDisappear"))
            let lazyWC = NSWindowController()
            lazyWC.contentViewController = Counting()
            XCTAssertFalse(lazyWC.isWindowLoaded)
            XCTAssertNotNil(lazyWC.window)
            XCTAssertTrue(lazyWC.isWindowLoaded)
            XCTAssertEqual(lazyWC.window?.contentView?.frame.size, NSSize(width: 120, height: 80))
            lazyWC.close()
        }
    }

    func testTabViewControllerSwitchesChildren() {
        MainActor.assumeIsolated {
            let tabs = NSTabViewController()
            let a = Counting(), b = Counting()
            a.title = "A"; b.title = "B"
            tabs.addChild(a)
            tabs.addChild(b)
            XCTAssertEqual(tabs.tabViewItems.count, 2)
            XCTAssertEqual(tabs.tabView.tabViewItems.map(\.label), ["A", "B"])
            let w = NSWindow(contentViewController: tabs)
            w.makeKeyAndOrderFront(nil)
            w.layoutIfNeeded()
            XCTAssertEqual(tabs.selectedTabViewItemIndex, 0)
            XCTAssertTrue(a.view.superview === tabs.tabView)
            XCTAssertNil(b.view.superview)
            XCTAssertEqual(a.view.frame, tabs.tabView.contentRect)
            tabs.selectedTabViewItemIndex = 1
            XCTAssertNil(a.view.superview)
            XCTAssertTrue(b.view.superview === tabs.tabView)
            XCTAssertTrue(a.log.contains("didDisappear"))
            XCTAssertTrue(b.log.contains("didAppear"))
            // Clicking a tab selects it.
            let rect = tabs.tabView.bounds
            let p = tabs.tabView.convert(NSPoint(x: rect.midX - 20, y: 12), to: nil)
            tabs.tabView.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!)
            XCTAssertEqual(tabs.selectedTabViewItemIndex, 0)
            w.close()
        }
    }

    func testSplitViewControllerDividesAndCollapses() {
        MainActor.assumeIsolated {
            let split = NSSplitViewController()
            let side = Counting(), main = Counting()
            let sideItem = NSSplitViewItem(sidebarWithViewController: side)
            sideItem.minimumThickness = 100
            split.addSplitViewItem(sideItem)
            split.addSplitViewItem(NSSplitViewItem(viewController: main))
            split.view.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
            let w = NSWindow(contentViewController: split)
            w.makeKeyAndOrderFront(nil)
            w.layoutIfNeeded()
            XCTAssertEqual(split.splitView.arrangedSubviews.count, 2)
            XCTAssertEqual(side.view.frame.minX, 0)
            XCTAssertGreaterThanOrEqual(side.view.frame.width, 100)
            XCTAssertEqual(main.view.frame.maxX, 400)
            XCTAssertEqual(main.view.frame.minX, side.view.frame.maxX + split.splitView.dividerThickness)
            split.splitView.setPosition(150, ofDividerAt: 0)
            XCTAssertEqual(side.view.frame.width, 150)
            XCTAssertEqual(main.view.frame.minX, 150 + split.splitView.dividerThickness)
            split.toggleSidebar(nil)
            XCTAssertTrue(sideItem.isCollapsed)
            XCTAssertTrue(split.splitView.isSubviewCollapsed(side.view))
            XCTAssertEqual(main.view.frame.minX, split.splitView.dividerThickness)
            split.toggleSidebar(nil)
            XCTAssertFalse(side.view.isHidden)
            // Window resize goes to the lowest holding priority (the main pane).
            w.setContentSize(NSSize(width: 500, height: 200))
            w.layoutIfNeeded()
            XCTAssertEqual(main.view.frame.maxX, 500)
            w.close()
        }
    }
}

final class WindowReopenTests: XCTestCase, @unchecked Sendable {
    func testClosedWindowCanBeShownAgain() {
        MainActor.assumeIsolated {
            let vc = NSViewController()
            vc.view = NSView(frame: NSRect(x: 0, y: 0, width: 150, height: 100))
            let wc = NSWindowController(window: NSWindow(contentViewController: vc))
            wc.showWindow(nil)
            let w = wc.window!
            XCTAssertTrue(w.isVisible)
            let frame = w.frame
            w.close()
            XCTAssertFalse(w.isVisible)
            XCTAssertFalse(NSApplication.shared.windows.contains { $0 === w })
            wc.showWindow(nil)
            XCTAssertTrue(w.isVisible)
            XCTAssertEqual(w.frame, frame)
            XCTAssertTrue(NSApplication.shared.windows.contains { $0 === w })
            XCTAssertTrue(w.contentView === vc.view)
            w.close()
        }
    }
}

final class CollapsedGeometryTests: XCTestCase, @unchecked Sendable {
    func testCollapsingAWindowKeepsGeometryFinite() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            let scroll = NSScrollView(frame: NSRect(x: 10, y: 10, width: 280, height: 180))
            scroll.autoresizingMask = [.width, .height]
            scroll.borderType = .bezelBorder
            scroll.hasVerticalScroller = true
            scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 1000))
            w.contentView!.addSubview(scroll)
            w.makeKeyAndOrderFront(nil)
            w.display()
            // What a minimised Win32 window reports: a 0x0 client area.
            w.setContentSize(NSSize(width: 0, height: 0))
            w.display()
            XCTAssertTrue(scroll.frame.width.isFinite && scroll.frame.height.isFinite)
            XCTAssertTrue(scroll.contentView.frame.width.isFinite && scroll.contentView.frame.minY.isFinite)
            w.setContentSize(NSSize(width: 300, height: 200))
            w.display()
            // Autoresizing through a 0x0 pass is lossy (as in AppKit); what matters is sane geometry.
            XCTAssertTrue(scroll.frame.width.isFinite && scroll.frame.width >= 0 && scroll.frame.height >= 0)
            XCTAssertTrue(scroll.contentView.frame.width.isFinite && scroll.contentView.frame.width >= 0)
            w.close()
        }
    }
}
