// Containers and scene actions the Sibyl port needed: NavigationSplitView, HSplitView and
// VSplitView over NSSplitView, the inspector column, searchable, openWindow(id:),
// Transferable drag and drop, the accessibility environment values and the accepted no-op
// modifiers (symbol effects, content transitions, help overloads, subtitles).

import XCTest
import UniformTypeIdentifiers
@testable import AppKit
@testable import SwiftUI

extension UTType {
    static let containerGapToken = UTType(exportedAs: "org.appkitcross.tests.container-gap-token")
}

private struct GapToken: Codable, Transferable, Equatable {
    let id: String
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .containerGapToken)
    }
}

/// A Transferable through another type (a proxy over String).
private struct GapName: Transferable, Equatable {
    let name: String
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: { $0.name }, importing: { GapName(name: $0) })
    }
}

@MainActor
private func host<V: View>(_ view: V, width: CGFloat = 800, height: CGFloat = 500) -> (NSWindow, NSHostingView<V>) {
    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
    let h = NSHostingView(rootView: view)
    h.frame = NSRect(x: 0, y: 0, width: width, height: height)
    w.contentView!.addSubview(h)
    w.makeKeyAndOrderFront(nil)
    h.layoutSubtreeIfNeeded()
    return (w, h)
}

@MainActor
private func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }
@MainActor
private func texts(_ v: NSView) -> [String] { allViews(v).compactMap { ($0 as? _TextView)?.storage.string } }
@MainActor
private func splits(_ v: NSView) -> [NSSplitView] { allViews(v).compactMap { $0 as? NSSplitView } }

private final class InspectorModel: ObservableObject {
    @Published var shown = false
}

private final class SearchModel: ObservableObject {
    @Published var text = ""
}

final class SwiftUIContainerGapTests: XCTestCase, @unchecked Sendable {
    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated { _AppRunner._terminatesAfterLastWindowCloses = false }
    }
    override func tearDown() {
        MainActor.assumeIsolated { _AppRunner._terminatesAfterLastWindowCloses = true }
        super.tearDown()
    }

    // MARK: NavigationSplitView

    func testNavigationSplitViewSidebarAndDetail() {
        MainActor.assumeIsolated {
            let (w, h) = host(NavigationSplitView {
                Text("Sidebar").navigationSplitViewColumnWidth(min: 140, ideal: 250, max: 420)
            } detail: {
                Text("Detail")
            })
            defer { w.close() }
            guard let split = splits(h).first else { return XCTFail("a NavigationSplitView hosts an NSSplitView") }
            XCTAssertTrue(split.isVertical, "columns side by side, a vertical divider")
            XCTAssertEqual(split.arrangedSubviews.count, 2)
            XCTAssertEqual(split.frame.size, NSSize(width: 800, height: 500))
            let sidebar = split.arrangedSubviews[0], detail = split.arrangedSubviews[1]
            XCTAssertEqual(sidebar.frame.width, 250, "the sidebar opens at its ideal width")
            XCTAssertEqual(detail.frame.minX, 250 + split.dividerThickness)
            XCTAssertEqual(detail.frame.width, 800 - 250 - split.dividerThickness, "the detail takes the rest")
            XCTAssertEqual(texts(sidebar), ["Sidebar"])
            XCTAssertEqual(texts(detail), ["Detail"])

            // Dragging the divider resizes the columns, within the sidebar's range.
            split.setPosition(300, ofDividerAt: 0)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(sidebar.frame.width, 300)
            XCTAssertEqual(detail.frame.width, 800 - 300 - split.dividerThickness)
            split.setPosition(700, ofDividerAt: 0)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(sidebar.frame.width, 420, "clamped to the column's maximum")
            split.setPosition(20, ofDividerAt: 0)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(sidebar.frame.width, 140, "clamped to the column's minimum")

            // A wider window goes to the detail; the sidebar keeps its width.
            w.setContentSize(NSSize(width: 1000, height: 500))
            h.frame = NSRect(x: 0, y: 0, width: 1000, height: 500)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(sidebar.frame.width, 140)
            XCTAssertEqual(detail.frame.width, 1000 - 140 - split.dividerThickness)
        }
    }

    func testNavigationSplitViewDefaultsAndVisibility() {
        MainActor.assumeIsolated {
            let (w, h) = host(NavigationSplitView { Text("S") } content: { Text("C") } detail: { Text("D") }
                .navigationSplitViewStyle(.balanced))
            defer { w.close() }
            guard let split = splits(h).first else { return XCTFail("no split view") }
            XCTAssertEqual(split.arrangedSubviews.map(\.frame.width), [200, 250, 800 - 450 - 2 * split.dividerThickness],
                           "default sidebar and content widths; the detail takes the rest")

            let (w2, h2) = host(NavigationSplitView(columnVisibility: .constant(.detailOnly)) { Text("S") } detail: { Text("D") })
            defer { w2.close() }
            XCTAssertEqual(splits(h2).first?.arrangedSubviews.count, 1, ".detailOnly shows the detail alone")
            XCTAssertEqual(texts(h2), ["D"])
            let (w3, h3) = host(NavigationSplitView(columnVisibility: .constant(.doubleColumn)) { Text("S") } content: { Text("C") } detail: { Text("D") })
            defer { w3.close() }
            XCTAssertEqual(texts(h3).sorted(), ["C", "D"], ".doubleColumn hides a three-column view's sidebar")
        }
    }

    // MARK: HSplitView / VSplitView

    func testHSplitViewLaysChildrenSideBySideWithinTheirFrames() {
        MainActor.assumeIsolated {
            let (w, h) = host(HSplitView {
                Text("Left").frame(minWidth: 100, maxWidth: 300, maxHeight: .infinity)
                Text("Right").frame(minWidth: 150, maxWidth: .infinity, maxHeight: .infinity)
            }, width: 600, height: 300)
            defer { w.close() }
            guard let split = splits(h).first else { return XCTFail("an HSplitView hosts an NSSplitView") }
            XCTAssertTrue(split.isVertical)
            let panes = split.arrangedSubviews
            XCTAssertEqual(panes.count, 2)
            XCTAssertEqual(panes[0].frame.width, 100, "the first child at its ideal width (its minimum here)")
            XCTAssertEqual(panes[1].frame.minX, 100 + split.dividerThickness, "side by side")
            XCTAssertEqual(panes[1].frame.width, 600 - 100 - split.dividerThickness, "the last child takes up the slack")
            XCTAssertEqual(panes.map(\.frame.height), [300, 300])
            XCTAssertEqual(texts(panes[0]), ["Left"]); XCTAssertEqual(texts(panes[1]), ["Right"])
            split.setPosition(500, ofDividerAt: 0)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(panes[0].frame.width, 300, "the left child's maximum width holds")
            split.setPosition(10, ofDividerAt: 0)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(panes[0].frame.width, 100, "and its minimum")

            let (w2, h2) = host(VSplitView { Text("Top"); Text("Bottom") }, width: 300, height: 400)
            defer { w2.close() }
            guard let v = splits(h2).first else { return XCTFail("a VSplitView hosts an NSSplitView") }
            XCTAssertFalse(v.isVertical, "stacked, a horizontal divider")
            XCTAssertEqual(v.arrangedSubviews.count, 2)
            XCTAssertLessThan(v.arrangedSubviews[0].frame.maxY, v.arrangedSubviews[1].frame.minY + 0.5)
            XCTAssertEqual(v.arrangedSubviews.map(\.frame.width), [300, 300])
        }
    }

    // MARK: Inspector

    func testInspectorAppearsAndDisappearsWithItsBinding() {
        MainActor.assumeIsolated {
            struct Screen: View {
                @ObservedObject var model: InspectorModel
                var body: some View {
                    Text("Content")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .inspector(isPresented: $model.shown) {
                            Text("Inspector").inspectorColumnWidth(min: 210, ideal: 330, max: 520)
                        }
                }
            }
            let model = InspectorModel()
            let (w, h) = host(Screen(model: model))
            defer { w.close() }
            guard let split = splits(h).first else { return XCTFail("the inspector host is a split view") }
            XCTAssertEqual(split.arrangedSubviews.count, 1, "hidden: the content alone")
            XCTAssertFalse(texts(h).contains("Inspector"))
            let contentPane = split.arrangedSubviews[0]
            XCTAssertEqual(contentPane.frame.width, 800)

            model.shown = true
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(split.arrangedSubviews.count, 2, "shown: a trailing column")
            XCTAssertTrue(split.arrangedSubviews[0] === contentPane, "the content keeps its pane")
            // macOS 15 opens it at the modifier's minimum (589 + 1 + 210 in an 800-point window).
            XCTAssertEqual(split.arrangedSubviews[1].frame.width, 210, "at the inspector's minimum width")
            XCTAssertEqual(contentPane.frame.width, 800 - 210 - split.dividerThickness)
            XCTAssertEqual(texts(split.arrangedSubviews[1]), ["Inspector"])

            model.shown = false
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(split.arrangedSubviews.count, 1)
            XCTAssertFalse(texts(h).contains("Inspector"))
            XCTAssertEqual(contentPane.frame.width, 800)
        }
    }

    func testInspectorDefaultWidthInsideANavigationSplitView() {
        MainActor.assumeIsolated {
            let (w, h) = host(NavigationSplitView { Text("S") } detail: {
                Text("D").inspector(isPresented: .constant(true)) { Text("I") }
            }, width: 900)
            defer { w.close() }
            let all = splits(h)
            XCTAssertEqual(all.count, 2, "the navigation split view and the inspector's")
            guard let inner = all.last else { return }
            XCTAssertEqual(inner.arrangedSubviews.last?.frame.width, 270, "the default inspector width")
            XCTAssertEqual(all.first?.arrangedSubviews.first?.frame.width, 200, "the sidebar keeps its width")
        }
    }

    // MARK: searchable

    func testSearchableBindsAnNSSearchField() {
        MainActor.assumeIsolated {
            struct Screen: View {
                @ObservedObject var model: SearchModel
                let placement: SearchFieldPlacement
                var body: some View {
                    Text("Results").searchable(text: $model.text, placement: placement, prompt: "Search transcript")
                }
            }
            let model = SearchModel()
            let (w, h) = host(Screen(model: model, placement: .sidebar))
            defer { w.close() }
            guard let field = allViews(h).compactMap({ $0 as? NSSearchField }).first else { return XCTFail("searchable hosts an NSSearchField") }
            XCTAssertEqual(field.placeholderString, "Search transcript")
            XCTAssertLessThan(field.frame.minY, allViews(h).first { ($0 as? _TextView)?.storage.string == "Results" }!.frame.minY, "above the content")

            model.text = "cue"
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(field.stringValue, "cue", "the binding's text shows in the field")
            field.stringValue = "standby"
            NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
            XCTAssertEqual(model.text, "standby", "typing updates the binding")

            // In the toolbar: the window's toolbar gets an item hosting the field.
            let toolbarModel = SearchModel()
            let (w2, h2) = host(Screen(model: toolbarModel, placement: .toolbar))
            defer { w2.close() }
            XCTAssertTrue(allViews(h2).compactMap { $0 as? NSSearchField }.isEmpty, "not in the content")
            XCTAssertNotNil(w2.toolbar, "the window gets a toolbar")
            let hosted = w2.toolbar?.items.compactMap(\.view) ?? []
            let toolbarField = hosted.flatMap(allViews).compactMap { $0 as? NSSearchField }.first
            XCTAssertNotNil(toolbarField, "the toolbar item hosts the search field")
            toolbarField?.stringValue = "go"
            if let toolbarField { NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: toolbarField) }
            XCTAssertEqual(toolbarModel.text, "go")
        }
    }

    // MARK: openWindow

    func testOpenWindowOpensAndBringsForwardSceneWindows() {
        MainActor.assumeIsolated {
            let runner = _AppRunner(name: "Sibyl")
            runner.run(scene: SceneBuilder.buildBlock(
                Window("Sibyl", id: "main") { Text("Main") },
                Window("Post-Show", id: "post-show") { Text("Report") }.defaultSize(width: 640, height: 420),
                WindowGroup("Note", id: "note") { Text("Note") }
            ))
            defer { for w in runner.windows { w.close() } }
            XCTAssertEqual(runner.windows.map(\.title), ["Sibyl"], "only the first scene opens at launch")

            let open = EnvironmentValues().openWindow
            open(id: "post-show")
            XCTAssertEqual(runner.windows.map(\.title), ["Sibyl", "Post-Show"])
            XCTAssertEqual(runner.windows.last?.contentRect(forFrameRect: runner.windows.last!.frame).size, NSSize(width: 640, height: 420),
                           "the scene's default size applies when it opens later")
            open(id: "post-show")
            XCTAssertEqual(runner.windows.count, 2, "a Window opens once; opening it again brings it forward")
            XCTAssertEqual(runner._windows(ofScene: "post-show").count, 1)

            open(id: "note"); open(id: "note")
            XCTAssertEqual(runner._windows(ofScene: "note").count, 2, "a WindowGroup opens another window each time")

            EnvironmentValues().dismissWindow(id: "post-show")
            XCTAssertEqual(runner._windows(ofScene: "post-show").count, 0)
            open(id: "post-show")
            XCTAssertEqual(runner._windows(ofScene: "post-show").count, 1, "a closed Window opens again")
        }
    }

    func testOpenWindowFromAView() {
        MainActor.assumeIsolated {
            struct Opener: View {
                @Environment(\.openWindow) var openWindow
                var body: some View { Button("Open") { openWindow(id: "second") } }
            }
            let runner = _AppRunner(name: "Opener")
            runner.run(scene: SceneBuilder.buildBlock(Window("First", id: "first") { Opener() }, Window("Second", id: "second") { Text("2") }))
            defer { for w in runner.windows { w.close() } }
            XCTAssertEqual(runner.windows.count, 1)
            let button = allViews(runner.windows[0].contentView!).compactMap { $0 as? NSButton }.first
            XCTAssertNotNil(button)
            button?.performClick(nil)
            XCTAssertEqual(runner.windows.map(\.title), ["First", "Second"])
        }
    }

    // MARK: Transferable

    func testCodableTransferableRoundTripsThroughAnItemProvider() {
        XCTAssertEqual(GapToken.exportedContentTypes().map(\.identifier), [UTType.containerGapToken.identifier])
        XCTAssertEqual(GapToken.importedContentTypes().map(\.identifier), [UTType.containerGapToken.identifier])
        XCTAssertEqual(GapName.exportedContentTypes(), [.utf8PlainText], "a proxy exports its proxy's types")

        let token = GapToken(id: "channel-7")
        let provider = _itemProvider(for: token)
        XCTAssertEqual(provider.registeredTypeIdentifiers, [UTType.containerGapToken.identifier])

        // The provider's data, as a drag would put it on the pasteboard.
        let loaded = expectation(description: "data")
        nonisolated(unsafe) var data: Data?
        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.containerGapToken.identifier) { d, _ in data = d; loaded.fulfill() }
        wait(for: [loaded], timeout: 5)
        XCTAssertEqual(try data.map { try JSONDecoder().decode(GapToken.self, from: $0) }, token, "JSON under the content type")

        // loadTransferable decodes it back.
        let decoded = expectation(description: "transferable")
        nonisolated(unsafe) var back: GapToken?
        provider.loadTransferable(type: GapToken.self) { result in back = try? result.get(); decoded.fulfill() }
        wait(for: [decoded], timeout: 5)
        XCTAssertEqual(back, token)

        MainActor.assumeIsolated {
            // dropDestination's delegate decodes the pasteboard items and passes the location.
            let item = NSPasteboardItem()
            _ = item.setData(data!, forType: NSPasteboard.PasteboardType(UTType.containerGapToken.identifier))
            var received: ([GapToken], CGPoint)?
            var targeted: [Bool] = []
            let delegate = _TransferDropDelegate<GapToken>(entries: GapToken._entries, action: { items, location in received = (items, location); return true },
                                                           isTargeted: { targeted.append($0) })
            let info = DropInfo(location: CGPoint(x: 12, y: 34), items: [item])
            XCTAssertTrue(delegate.validateDrop(info: info))
            delegate.dropEntered(info: info)
            XCTAssertTrue(delegate.performDrop(info: info))
            XCTAssertEqual(received?.0, [token])
            XCTAssertEqual(received?.1, CGPoint(x: 12, y: 34))
            XCTAssertEqual(targeted, [true, false], "isTargeted follows the drag in and the drop")

            let other = NSPasteboardItem()
            _ = other.setString("not a token", forType: .string)
            XCTAssertFalse(delegate.validateDrop(info: DropInfo(location: .zero, items: [other])), "other types are refused")

            // A proxy representation goes through the proxy's data.
            let proxied = _TransferDropDelegate<GapName>(entries: GapName._entries, action: { items, _ in items == [GapName(name: "FOH")] }, isTargeted: { _ in })
            let text = NSPasteboardItem()
            _ = text.setData(Data("FOH".utf8), forType: NSPasteboard.PasteboardType(UTType.utf8PlainText.identifier))
            XCTAssertTrue(proxied.performDrop(info: DropInfo(location: .zero, items: [text])))
        }
    }

    func testDraggableAndDropDestinationInstallTheirViews() {
        MainActor.assumeIsolated {
            let (w, h) = host(VStack {
                Text("Drag me").draggable(GapToken(id: "a")) { Label("Channel", systemImage: "waveform") }
                Text("Drop here").dropDestination(for: GapToken.self) { tokens, _ in !tokens.isEmpty }
            }, width: 300, height: 200)
            defer { w.close() }
            let source = allViews(h).compactMap { $0 as? _DragSourceView }.first
            XCTAssertNotNil(source?.makeProvider, "draggable starts drags through onDrag")
            XCTAssertNotNil(source?.makePreview, "with the preview view as the drag image")
            XCTAssertEqual(source?.makeProvider?().registeredTypeIdentifiers, [UTType.containerGapToken.identifier])
            let target = allViews(h).compactMap { $0 as? _DropTargetView }.first
            XCTAssertEqual(target?.types.map(\.identifier), [UTType.containerGapToken.identifier], "the drop target takes the token's type")
        }
    }

    // MARK: Environment and accepted modifiers

    func testAccessibilityEnvironmentFollowsTheWorkspace() {
        MainActor.assumeIsolated {
            let env = EnvironmentValues()
            XCTAssertEqual(env.accessibilityReduceMotion, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            XCTAssertEqual(env.accessibilityReduceTransparency, NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
            XCTAssertEqual(env.accessibilityDifferentiateWithoutColor, NSWorkspace.shared.accessibilityDisplayShouldDifferentiateWithoutColor)
            #if !canImport(Darwin)
            XCTAssertFalse(env.accessibilityReduceMotion, "off unless the desktop asks for less motion")
            #endif
            final class Seen { var value: Bool? }
            let seen = Seen()
            struct Reader: View {
                @Environment(\.accessibilityReduceMotion) var reduceMotion
                let seen: Seen
                var body: some View { seen.value = reduceMotion; return Text("motion") }
            }
            let (w, _) = host(Reader(seen: seen), width: 200, height: 100)
            defer { w.close() }
            XCTAssertEqual(seen.value, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        }
    }

    func testAcceptedModifiersKeepTheirContent() {
        MainActor.assumeIsolated {
            let (w, h) = host(VStack {
                Image(systemName: "waveform").symbolEffect(.variableColor, isActive: true)
                Image(systemName: "waveform").symbolEffect(.pulse.byLayer, options: .repeating, isActive: false)
                Image(systemName: "waveform").symbolEffect(.bounce, value: 3)
                Text("42").contentTransition(.numericText())
                Label("Start", systemImage: "play.fill").contentTransition(.symbolEffect(.replace))
                Text("Key").help(Text("A tooltip"))
                Text("Localized").help(LocalizedStringKey("Localized tooltip"))
            }
            .navigationSubtitle("3 channels live")
            .presentedWindowStyle(.hiddenTitleBar), width: 300, height: 300)
            defer { w.close() }
            XCTAssertTrue(texts(h).contains("42"))
            XCTAssertTrue(texts(h).contains("Key"))
            XCTAssertEqual(w.subtitle, "3 channels live", "navigationSubtitle sets the window's subtitle")
            let tips = allViews(h).compactMap { $0.toolTip }
            XCTAssertTrue(tips.contains("A tooltip"), "help(Text) is the tooltip")
            XCTAssertTrue(tips.contains("Localized tooltip"))
            XCTAssertNotEqual(VariableColorSymbolEffect.variableColor.iterative, .variableColor)
        }
    }
}

/// A window scene whose content proposes an infinite height (a sidebar List did) must still
/// get a finite window: Sibyl's main window on Windows snapped to the maximum track height
/// after the first programmatic resize.
final class SwiftUIWindowGeometryFiniteTests: XCTestCase, @unchecked Sendable {
    private struct Boundless: Layout {
        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize { CGSize(width: 250, height: CGFloat.infinity) }
        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {}
    }
    func testInfiniteContentProposalsNeverReachTheWindow() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let runner = _AppRunner(name: "Boundless")
            runner.run(scene: SceneBuilder.buildBlock(
                Window("Main", id: "main") { Boundless { Text("x") } }.defaultSize(width: 1260, height: 780)
            ))
            defer { for w in runner.windows { w.close() } }
            guard let w = runner.windows.first else { return XCTFail("no window") }
            let content = w.contentView!.frame.size
            XCTAssertTrue(content.width.isFinite && content.height.isFinite, "\(content)")
            XCTAssertEqual(content.width, 1260)
            XCTAssertLessThanOrEqual(content.height, 780)
            XCTAssertTrue(w.minSize.width.isFinite && w.minSize.height.isFinite, "\(w.minSize)")
            // A later programmatic resize is honoured as asked.
            w.setContentSize(NSSize(width: 1100, height: 700))
            XCTAssertEqual(w.contentView!.frame.size, NSSize(width: 1100, height: 700))

            // The same content with no default size and `.contentSize` resizability.
            let runner2 = _AppRunner(name: "Boundless2")
            runner2.run(scene: SceneBuilder.buildBlock(
                Window("Main", id: "main") { Boundless { Text("x") } }.windowResizability(.contentSize)
            ))
            defer { for w in runner2.windows { w.close() } }
            guard let w2 = runner2.windows.first else { return XCTFail("no window") }
            XCTAssertTrue(w2.frame.height.isFinite && w2.minSize.height.isFinite, "\(w2.frame) min \(w2.minSize)")
        }
    }
}
