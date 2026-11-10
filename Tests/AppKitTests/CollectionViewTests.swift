// NSCollectionView, NSGridView and NSBox on the host backend: layout attributes, the
// flow and grid layouts, item reuse, batch updates, selection with the mouse and the
// keyboard, accessibility, grid cell placement and merges, and the box's drawing.

import XCTest
@testable import AppKit

// MARK: - Fixtures

/// An item that draws its selection and shows its represented object's text.
@MainActor
final class ColorItem: NSCollectionViewItem {
    final class ItemView: NSView {
        weak var item: ColorItem?
        override func draw(_ dirtyRect: NSRect) {
            (item?.isSelected == true ? NSColor.selectedContentBackgroundColor : NSColor.controlColor).setFill()
            NSBezierPath(rect: bounds).fill()
        }
    }
    static var made = 0
    override func loadView() {
        ColorItem.made += 1
        let v = ItemView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        v.item = self
        let label = NSTextField(labelWithString: "")
        label.frame = NSRect(x: 2, y: 2, width: 36, height: 16)
        label.autoresizingMask = [.width]
        v.addSubview(label)
        textField = label
        view = v
    }
}

final class HeaderView: NSView, NSCollectionViewElement {
    let label = NSTextField(labelWithString: "")
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        label.frame = NSRect(x: 4, y: 2, width: 200, height: 16)
        addSubview(label)
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        label.frame = NSRect(x: 4, y: 2, width: 200, height: 16)
        addSubview(label)
    }
}

@MainActor
private final class Source: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var sections: [[String]] = [["a", "b", "c", "d", "e"], ["f", "g", "h"]]
    var selected: [Set<IndexPath>] = []
    var deselected: [Set<IndexPath>] = []
    var highlights: [(Set<IndexPath>, NSCollectionViewItem.HighlightState)] = []
    var refuse: IndexPath? = nil
    var itemRequests = 0
    var displayed: [IndexPath] = []
    var ended: [IndexPath] = []

    func numberOfSections(in collectionView: NSCollectionView) -> Int { sections.count }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { sections[section].count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        itemRequests += 1
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("color"), for: indexPath)
        item.textField?.stringValue = sections[indexPath.section][indexPath.item]
        item.representedObject = sections[indexPath.section][indexPath.item]
        return item
    }
    func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath) -> NSView {
        let v = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: NSUserInterfaceItemIdentifier("header"), for: indexPath)
        (v as? HeaderView)?.label.stringValue = "Section \(indexPath.section)"
        return v
    }
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { selected.append(indexPaths) }
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { deselected.append(indexPaths) }
    func collectionView(_ collectionView: NSCollectionView, shouldSelectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> { indexPaths.filter { $0 != refuse } }
    func collectionView(_ collectionView: NSCollectionView, didChangeItemsAt indexPaths: Set<IndexPath>, to highlightState: NSCollectionViewItem.HighlightState) { highlights.append((indexPaths, highlightState)) }
    func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) { displayed.append(indexPath) }
    func collectionView(_ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) { ended.append(indexPath) }
}

/// Four 40×40 items fit a 200-point line with 10-point spacing and 5-point insets:
/// 5 + 40 + 10 + 40 + 10 + 40 + 10 + 40 = 195 ≤ 200 - 5. The scroll view is 215 wide so
/// the clip view is 200 once the vertical scroller takes its 15 points.
@MainActor
private func makeCollection(in window: NSWindow, height: CGFloat = 150, headers: Bool = false, layout: NSCollectionViewLayout? = nil) -> (NSCollectionView, NSScrollView, Source) {
    let source = Source()
    let cv = NSCollectionView(frame: .zero)
    let flow = NSCollectionViewFlowLayout()
    flow.itemSize = NSSize(width: 40, height: 40)
    flow.minimumInteritemSpacing = 10
    flow.minimumLineSpacing = 10
    flow.sectionInset = NSEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
    if headers { flow.headerReferenceSize = NSSize(width: 0, height: 20) }
    cv.collectionViewLayout = layout ?? flow
    cv.register(ColorItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("color"))
    cv.register(HeaderView.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader, withIdentifier: NSUserInterfaceItemIdentifier("header"))
    cv.dataSource = source
    cv.delegate = source
    cv.isSelectable = true
    cv.allowsMultipleSelection = true
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 215, height: height))
    scroll.hasVerticalScroller = true
    scroll.documentView = cv
    window.contentView!.addSubview(scroll)
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(cv)
    scroll.layoutSubtreeIfNeeded()
    return (cv, scroll, source)
}

@MainActor
private func click(_ cv: NSCollectionView, _ ip: IndexPath, flags: NSEvent.ModifierFlags = []) {
    let f = cv.layoutAttributesForItem(at: ip)!.frame
    let p = cv.convert(NSPoint(x: f.midX, y: f.midY), to: nil)
    let down = NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: flags, timestamp: 0, windowNumber: cv.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    let up = NSEvent.mouseEvent(with: .leftMouseUp, location: p, modifierFlags: flags, timestamp: 0, windowNumber: cv.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
    cv.window!.sendEvent(down)
    cv.window!.sendEvent(up)
}

@MainActor
private func key(_ view: NSView, _ chars: String, flags: NSEvent.ModifierFlags = []) {
    let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: view.window!.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: 0)!
    view.window!.sendEvent(e)
}

@MainActor
private func render(_ v: NSView) -> NSBitmapImageRep {
    let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
    v.cacheDisplay(in: v.bounds, to: rep)
    return rep
}

private func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
    let scale = max(1, rep.pixelsWide / max(1, Int(rep.size.width)))
    guard let c = rep.colorAt(x: x * scale, y: y * scale) else { return (0, 0, 0, 0) }
    return (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
}

private func ip(_ item: Int, _ section: Int = 0) -> IndexPath { IndexPath(item: item, section: section) }

@MainActor
private func element(_ tree: PlatformAccessibilityElement, role: NSAccessibility.Role) -> PlatformAccessibilityElement? {
    tree.flattened.first { $0.role == role.rawValue }
}

// MARK: - Tests

final class CollectionViewTests: XCTestCase, @unchecked Sendable {
    override func setUp() { MainActor.assumeIsolated { ColorItem.made = 0 } }

    func testLayoutAttributesCarryTheirElement() {
        MainActor.assumeIsolated {
            let a = NSCollectionViewLayoutAttributes(forItemWith: ip(2, 1))
            XCTAssertEqual(a.representedElementCategory, .item)
            XCTAssertNil(a.representedElementKind)
            XCTAssertEqual(a.indexPath, ip(2, 1))
            XCTAssertEqual(a.alpha, 1)
            XCTAssertEqual(a.zIndex, 0)
            a.frame = NSRect(x: 1, y: 2, width: 3, height: 4)
            a.size = NSSize(width: 30, height: 40)
            XCTAssertEqual(a.frame, NSRect(x: 1, y: 2, width: 30, height: 40))
            let copy = a.copy() as! NSCollectionViewLayoutAttributes
            XCTAssertEqual(copy, a)
            copy.zIndex = 5
            XCTAssertNotEqual(copy, a)
            let h = NSCollectionViewLayoutAttributes(forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader, with: ip(0, 3))
            XCTAssertEqual(h.representedElementCategory, .supplementaryView)
            XCTAssertEqual(h.representedElementKind, NSCollectionView.elementKindSectionHeader)
            let d = NSCollectionViewLayoutAttributes(forDecorationViewOfKind: "shade", with: ip(0))
            XCTAssertEqual(d.representedElementCategory, .decorationView)
            XCTAssertEqual(NSCollectionViewLayoutAttributes(forInterItemGapBefore: ip(1)).representedElementCategory, .interItemGap)
        }
    }

    func testFlowLayoutWrapsLinesInsideTheSectionInsets() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 150), styleMask: [.titled], backing: .buffered, defer: false)
            let (cv, _, source) = makeCollection(in: w, headers: true)
            defer { withExtendedLifetime(source) {} }
            XCTAssertEqual(cv.numberOfSections, 2)
            XCTAssertEqual(cv.numberOfItems(inSection: 0), 5)
            // Section 0: header 20 high, then the inset, four items on the first line.
            XCTAssertEqual(cv.layoutAttributesForSupplementaryElement(ofKind: NSCollectionView.elementKindSectionHeader, at: ip(0, 0))?.frame, NSRect(x: 0, y: 0, width: 200, height: 20))
            XCTAssertEqual(cv.layoutAttributesForItem(at: ip(0))?.frame, NSRect(x: 5, y: 25, width: 40, height: 40))
            XCTAssertEqual(cv.layoutAttributesForItem(at: ip(3))?.frame, NSRect(x: 155, y: 25, width: 40, height: 40))
            XCTAssertEqual(cv.layoutAttributesForItem(at: ip(4))?.frame, NSRect(x: 5, y: 75, width: 40, height: 40), "the fifth item wraps to the next line")
            // Section 1 starts after the first section's bottom inset.
            XCTAssertEqual(cv.layoutAttributesForSupplementaryElement(ofKind: NSCollectionView.elementKindSectionHeader, at: ip(0, 1))?.frame.minY, 120)
            XCTAssertEqual(cv.layoutAttributesForItem(at: ip(0, 1))?.frame, NSRect(x: 5, y: 145, width: 40, height: 40))
            XCTAssertEqual(cv.collectionViewLayout!.collectionViewContentSize, NSSize(width: 200, height: 190))
            XCTAssertEqual(cv.frame.size, NSSize(width: 200, height: 190), "the document view is as tall as the content")
            // Hit-testing goes through the layout.
            XCTAssertEqual(cv.indexPathForItem(at: NSPoint(x: 60, y: 30)), ip(1))
            XCTAssertNil(cv.indexPathForItem(at: NSPoint(x: 2, y: 30)), "the inset is not an item")
            // A narrower clip view re-wraps: three items per line.
            cv.enclosingScrollView!.frame = NSRect(x: 0, y: 0, width: 175, height: 150)
            cv.enclosingScrollView!.layoutSubtreeIfNeeded()
            XCTAssertEqual(cv.layoutAttributesForItem(at: ip(3))?.frame.origin, NSPoint(x: 5, y: 75), "the fourth item wraps when the width shrinks")
            // The delegate's per-section metrics win over the layout's.
            w.close()
        }
    }

    func testFlowLayoutHonoursTheDelegateMetricsAndCollapsing() {
        MainActor.assumeIsolated {
            final class Metrics: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
                func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { 3 }
                func numberOfSections(in collectionView: NSCollectionView) -> Int { 2 }
                func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
                    collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("color"), for: indexPath)
                }
                func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
                    NSSize(width: 20 + 10 * CGFloat(indexPath.item), height: 20)
                }
                func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, insetForSectionAt section: Int) -> NSEdgeInsets {
                    NSEdgeInsets(top: 0, left: CGFloat(section) * 10, bottom: 0, right: 0)
                }
            }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 150), styleMask: [.titled], backing: .buffered, defer: false)
            let metrics = Metrics()
            let (cv, _, source) = makeCollection(in: w)
            defer { withExtendedLifetime(source) {} }
            cv.dataSource = metrics
            cv.delegate = metrics
            XCTAssertEqual(cv.layoutAttributesForItem(at: ip(0))?.frame, NSRect(x: 0, y: 0, width: 20, height: 20))
            XCTAssertEqual(cv.layoutAttributesForItem(at: ip(2))?.frame, NSRect(x: 70, y: 0, width: 40, height: 20), "sizes come from the delegate, spacing from the layout")
            XCTAssertEqual(cv.layoutAttributesForItem(at: ip(0, 1))?.frame.minX, 10, "the second section's inset comes from the delegate")
            let flow = cv.collectionViewLayout as! NSCollectionViewFlowLayout
            let before = cv.layoutAttributesForItem(at: ip(0, 1))!.frame.minY
            flow.collapseSection(at: 0)
            XCTAssertTrue(flow.section(atIndexIsCollapsed: 0))
            XCTAssertNil(cv.layoutAttributesForItem(at: ip(0)), "a collapsed section has no item frames")
            XCTAssertLessThan(cv.layoutAttributesForItem(at: ip(0, 1))!.frame.minY, before)
            flow.expandSection(at: 0)
            XCTAssertEqual(cv.layoutAttributesForItem(at: ip(0, 1))!.frame.minY, before)
            // Horizontal scrolling lays the lines out across the height.
            flow.scrollDirection = .horizontal
            XCTAssertEqual(cv.layoutAttributesForItem(at: ip(0))?.frame.origin, NSPoint(x: 0, y: 0))
            XCTAssertEqual(cv.layoutAttributesForItem(at: ip(1))?.frame.origin, NSPoint(x: 0, y: 30), "items run down the column")
            XCTAssertGreaterThan(cv.collectionViewLayout!.collectionViewContentSize.width, 0)
            w.close()
        }
    }

    func testItemsExistForTheVisibleRectAndAreReused() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            let (cv, _, source) = makeCollection(in: w, height: 100)
            w.display()
            // 100 points of clip view: the first line (y 5...45) and the second (55...95) show, section 1 (y 105+) does not.
            let visible = cv.indexPathsForVisibleItems()
            XCTAssertEqual(visible, Set([ip(0), ip(1), ip(2), ip(3), ip(4)]), "\(visible.sorted())")
            XCTAssertEqual(cv.item(at: ip(1))?.textField?.stringValue, "b")
            XCTAssertEqual(cv.item(at: ip(1))?.view.frame, NSRect(x: 55, y: 5, width: 40, height: 40))
            XCTAssertEqual(ColorItem.made, 5)
            XCTAssertEqual(source.displayed.sorted(), [ip(0), ip(1), ip(2), ip(3), ip(4)])
            // Scrolling to the end recycles the first line and reuses its items.
            cv.scrollToItems(at: [ip(2, 1)], scrollPosition: .bottom)
            w.display()
            XCTAssertTrue(cv.indexPathsForVisibleItems().contains(ip(2, 1)))
            XCTAssertFalse(cv.indexPathsForVisibleItems().contains(ip(0)))
            XCTAssertTrue(source.ended.contains(ip(0)))
            XCTAssertLessThanOrEqual(ColorItem.made, 8, "spare items are reused: \(ColorItem.made) made")
            XCTAssertEqual(cv.item(at: ip(2, 1))?.textField?.stringValue, "h")
            XCTAssertEqual(cv.visibleItems().count, cv.indexPathsForVisibleItems().count)
            XCTAssertEqual(cv.indexPath(for: cv.item(at: ip(2, 1))!), ip(2, 1))
            // reloadData drops every item and makes them again.
            let before = source.itemRequests
            cv.reloadData()
            w.display()
            XCTAssertGreaterThan(source.itemRequests, before)
            w.close()
        }
    }

    func testBatchUpdatesMoveTheVisibleItemsAndTheSelection() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
            let (cv, _, source) = makeCollection(in: w, height: 300)
            w.display()
            cv.selectionIndexPaths = [ip(2), ip(1, 1)]
            let itemC = cv.item(at: ip(2))!
            let itemF = cv.item(at: ip(0, 1))!
            var completed = false
            cv.performBatchUpdates({
                source.sections[0].remove(at: 0)                  // a
                source.sections[0].insert("x", at: 1)             // b x c d e
                source.sections[0].insert("y", at: 5)             // b x c d e y
                source.sections[1].remove(at: 2)                  // f g
                cv.deleteItems(at: [ip(0)])
                cv.insertItems(at: [ip(1), ip(5)])
                cv.deleteItems(at: [ip(2, 1)])
            }, completionHandler: { completed = $0 })
            XCTAssertTrue(completed)
            XCTAssertEqual(cv.numberOfItems(inSection: 0), 6)
            XCTAssertEqual(cv.numberOfItems(inSection: 1), 2)
            XCTAssertEqual(cv.selectionIndexPaths, [ip(2), ip(1, 1)], "c moved from 2 to 2 (one deleted before, one inserted before), g stays")
            XCTAssertTrue(cv.item(at: ip(2)) === itemC, "the item view follows its element")
            XCTAssertTrue(cv.item(at: ip(0, 1)) === itemF)
            XCTAssertEqual(cv.item(at: ip(1))?.textField?.stringValue, "x")
            XCTAssertEqual(cv.item(at: ip(5))?.textField?.stringValue, "y")
            XCTAssertTrue(itemC.isSelected)
            // Moving an item within a batch keeps its view.
            cv.performBatchUpdates({
                let c = source.sections[0].remove(at: 2)
                source.sections[0].insert(c, at: 0)
                cv.moveItem(at: ip(2), to: ip(0))
            })
            XCTAssertTrue(cv.item(at: ip(0)) === itemC)
            XCTAssertEqual(cv.selectionIndexPaths, [ip(0), ip(1, 1)])
            // Sections: insert one at the front, delete the last.
            cv.performBatchUpdates({
                source.sections.insert(["p", "q"], at: 0)
                source.sections.removeLast()
                cv.insertSections([0])
                cv.deleteSections([1])
            })
            XCTAssertEqual(cv.numberOfSections, 2)
            XCTAssertEqual(cv.selectionIndexPaths, [ip(0, 1)], "the selection in the deleted section is gone, the other follows its section")
            XCTAssertTrue(cv.item(at: ip(0, 1)) === itemC)
            XCTAssertEqual(cv.item(at: ip(1, 0))?.textField?.stringValue, "q")
            // reloadItems makes the item again.
            source.sections[0][1] = "Q"
            cv.reloadItems(at: [ip(1, 0)])
            XCTAssertEqual(cv.item(at: ip(1, 0))?.textField?.stringValue, "Q")
            w.close()
        }
    }

    func testMouseAndKeyboardSelectionGoThroughTheDelegate() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
            let (cv, _, source) = makeCollection(in: w, height: 300)
            w.display()
            click(cv, ip(1))
            XCTAssertEqual(cv.selectionIndexPaths, [ip(1)])
            XCTAssertEqual(source.selected, [[ip(1)]])
            XCTAssertTrue(cv.item(at: ip(1))!.isSelected)
            XCTAssertEqual(source.highlights.map { $0.1 }, [.forSelection, .none], "highlighted while the mouse is down")
            XCTAssertEqual(cv.item(at: ip(1))!.highlightState, .none)
            click(cv, ip(3), flags: .shift)
            XCTAssertEqual(cv.selectionIndexPaths, [ip(1), ip(2), ip(3)], "shift extends from the anchor")
            click(cv, ip(2), flags: .command)
            XCTAssertEqual(cv.selectionIndexPaths, [ip(1), ip(3)], "command toggles one item")
            XCTAssertEqual(source.deselected.last, [ip(2)])
            key(cv, "\u{F701}")                       // down from the last selected item (3): the item below it on the next line is 4 (x 5) ... nearest is 4
            XCTAssertEqual(cv.selectionIndexPaths, [ip(4)])
            key(cv, "\u{F703}")                       // right: the next item in order
            XCTAssertEqual(cv.selectionIndexPaths, [ip(0, 1)])
            key(cv, "\u{F700}")                       // up: back to the line above
            XCTAssertEqual(cv.selectionIndexPaths, [ip(4)])
            key(cv, "\u{F702}", flags: .shift)        // shift-left extends
            XCTAssertEqual(cv.selectionIndexPaths, [ip(3), ip(4)])
            key(cv, "\u{F72B}")                       // end
            XCTAssertEqual(cv.selectionIndexPaths, [ip(2, 1)])
            XCTAssertTrue(NSApplication.shared.sendAction(Selector(("selectAll:")), to: nil, from: nil))
            XCTAssertEqual(cv.selectionIndexPaths.count, 8)
            // A refused item never enters the selection.
            cv.deselectAll(nil)
            source.refuse = ip(0)
            click(cv, ip(0))
            XCTAssertEqual(cv.selectionIndexPaths, [], "the delegate refused item 0, leaving nothing selected")
            cv.allowsEmptySelection = false
            cv.selectionIndexPaths = [ip(1)]
            cv.deselectAll(nil)
            XCTAssertEqual(cv.selectionIndexPaths, [ip(1)], "no empty selection allowed")
            cv.allowsEmptySelection = true
            // Not selectable: clicks do nothing.
            let count = source.selected.count
            cv.isSelectable = false
            click(cv, ip(2))
            XCTAssertEqual(cv.selectionIndexPaths, [ip(1)])
            XCTAssertEqual(source.selected.count, count)
            // Single selection: the last of a set wins.
            cv.isSelectable = true
            cv.allowsMultipleSelection = false
            cv.selectionIndexPaths = [ip(0), ip(3)]
            XCTAssertEqual(cv.selectionIndexPaths, [ip(3)])
            XCTAssertEqual(cv.selectionIndexes, IndexSet(integer: 3))
            w.close()
        }
    }

    func testHeadersAreSupplementaryViewsAndPin() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            let (cv, scroll, source) = makeCollection(in: w, height: 100, headers: true)
            defer { withExtendedLifetime(source) {} }
            w.display()
            let header = cv._supplementaryView(ofKind: NSCollectionView.elementKindSectionHeader, at: ip(0, 0)) as? HeaderView
            XCTAssertEqual(header?.label.stringValue, "Section 0")
            XCTAssertEqual(header?.frame, NSRect(x: 0, y: 0, width: 200, height: 20))
            XCTAssertEqual(cv.indexPathsForVisibleSupplementaryElements(ofKind: NSCollectionView.elementKindSectionHeader), [ip(0, 0)])
            // Pinned headers stay at the top of the visible rect while their section shows.
            (cv.collectionViewLayout as! NSCollectionViewFlowLayout).sectionHeadersPinToVisibleBounds = true
            scroll.contentView.scroll(to: NSPoint(x: 0, y: 30))
            w.display()
            XCTAssertEqual(cv._supplementaryView(ofKind: NSCollectionView.elementKindSectionHeader, at: ip(0, 0))?.frame.minY, 30)
            let pinned = cv._supplementaryView(ofKind: NSCollectionView.elementKindSectionHeader, at: ip(0, 0))!
            let headerIndex = cv.subviews.firstIndex { $0 === pinned }!
            let lastItemIndex = cv.subviews.lastIndex { $0 is ColorItem.ItemView }!
            XCTAssertGreaterThan(headerIndex, lastItemIndex, "the pinned header is stacked above the items")
            w.close()
        }
    }

    func testGridLayoutMakesEqualCellsAndStripesTheBackground() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 150), styleMask: [.titled], backing: .buffered, defer: false)
            let grid = NSCollectionViewGridLayout()
            grid.minimumItemSize = NSSize(width: 50, height: 30)
            grid.maximumItemSize = NSSize(width: 80, height: 40)
            grid.minimumInteritemSpacing = 10
            grid.minimumLineSpacing = 10
            grid.margins = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
            let (cv, _, source) = makeCollection(in: w, layout: grid)
            defer { withExtendedLifetime(source) {} }
            w.display()
            // The usable width (the clip view less the margins) fits three 50-wide columns
            // with two gaps; the cells grow to share the width.
            let usable = cv.enclosingScrollView!.contentView.bounds.width - 20
            XCTAssertEqual(grid._numberOfColumns, 3)
            let w0 = cv.layoutAttributesForItem(at: ip(0))!.frame
            XCTAssertEqual(w0.minX, 10)
            XCTAssertEqual(w0.width, (usable - 20) / 3, accuracy: 0.01)
            XCTAssertEqual(w0.height, w0.width * 0.6, accuracy: 0.01, "the height keeps the minimum size's proportions")
            XCTAssertEqual(cv.layoutAttributesForItem(at: ip(3))!.frame.minY, 10 + w0.height + 10, accuracy: 0.01)
            XCTAssertEqual(cv.layoutAttributesForItem(at: ip(0, 1))!.frame.minX, cv.layoutAttributesForItem(at: ip(2))!.frame.minX, "sections run on through the grid")
            grid.maximumNumberOfColumns = 2
            XCTAssertEqual(cv.layoutAttributesForItem(at: ip(2))!.frame.minY, cv.layoutAttributesForItem(at: ip(3))!.frame.minY)
            // Two background colours stripe the rows.
            cv.backgroundColors = [.white, .black]
            let rep = render(cv)
            let row0 = pixel(rep, 100, 20), row1 = pixel(rep, 100, 20 + Int(w0.height) + 10)
            XCTAssertNotEqual(row0.r, row1.r, "rows alternate: \(row0) \(row1)")
            w.close()
        }
    }

    func testInvalidationCycleRunsPrepareAgain() {
        MainActor.assumeIsolated {
            final class Counting: NSCollectionViewFlowLayout {
                var prepares = 0
                override func prepare() { prepares += 1; super.prepare() }
            }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 150), styleMask: [.titled], backing: .buffered, defer: false)
            let layout = Counting()
            layout.itemSize = NSSize(width: 40, height: 40)
            let (cv, _, source) = makeCollection(in: w, layout: layout)
            defer { withExtendedLifetime(source) {} }
            w.display()
            let n = layout.prepares
            XCTAssertGreaterThan(n, 0)
            w.display()
            XCTAssertEqual(layout.prepares, n, "drawing again does not prepare again")
            layout.invalidateLayout()
            w.display()
            XCTAssertEqual(layout.prepares, n + 1)
            layout.itemSize = NSSize(width: 30, height: 30)
            _ = cv.layoutAttributesForItem(at: ip(0))
            XCTAssertEqual(layout.prepares, n + 2, "a metric change invalidates; the next query prepares")
            // A context naming items only still re-prepares the flow (its frames depend on them).
            let context = NSCollectionViewFlowLayoutInvalidationContext()
            context.invalidateItems(at: [ip(1)])
            XCTAssertEqual(context.invalidatedItemIndexPaths, [ip(1)])
            XCTAssertFalse(context.invalidateEverything)
            layout.invalidateLayout(with: context)
            _ = cv.layoutAttributesForItem(at: ip(0))
            XCTAssertEqual(layout.prepares, n + 3)
            w.close()
        }
    }

    func testBackgroundViewAndColors() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 150), styleMask: [.titled], backing: .buffered, defer: false)
            let (cv, _, source) = makeCollection(in: w)
            defer { withExtendedLifetime(source) {} }
            cv.backgroundColors = [.red]
            w.display()
            var p = pixel(render(cv), 2, 2)
            XCTAssertEqual(p.r, 1, accuracy: 0.05)
            XCTAssertEqual(p.g, 0, accuracy: 0.05)
            let bg = NSView(frame: .zero)
            bg.wantsLayer = true
            cv.backgroundView = bg
            w.display()
            XCTAssertEqual(bg.frame, cv.bounds, "the background view covers the content")
            XCTAssertTrue(cv.subviews.first === bg, "and sits behind the items")
            p = pixel(render(cv), 2, 2)
            XCTAssertNotEqual(p.r, 1, "the background view replaces the colours")
            w.close()
        }
    }

    func testAccessibilityExposesTheItemsAsSelectableChildren() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
            let (cv, _, source) = makeCollection(in: w, height: 300, headers: true)
            w.display()
            let tree = w.accessibilityTree()
            let grid = element(tree, role: .grid)!
            XCTAssertEqual(grid.role, "AXGrid")
            XCTAssertTrue(grid.allowsMultipleSelection)
            let items = grid.children.filter { $0.role == "AXGroup" && $0.isSelectable }
            XCTAssertEqual(items.count, 8, "\(grid.children.map(\.role))")
            XCTAssertEqual(items.map(\.index), Array(0..<8))
            XCTAssertEqual(items[1].label, "b", "an item reads as its text field")
            XCTAssertEqual(grid.children.first?.role, "AXStaticText", "the header view is not an element: its label stands in for it")
            XCTAssertEqual(grid.children.first?.value, .string("Section 0"))
            // Selecting and pressing through assistive technology runs the delegate path.
            XCTAssertTrue(w.accessibilitySetSelected(true, on: items[2].id, extending: false))
            XCTAssertEqual(cv.selectionIndexPaths, [ip(2)])
            XCTAssertEqual(source.selected.last, [ip(2)])
            XCTAssertTrue(w.accessibilitySetSelected(true, on: items[3].id, extending: true))
            XCTAssertEqual(cv.selectionIndexPaths, [ip(2), ip(3)])
            XCTAssertTrue(w.accessibilityPerform(.press, on: items[6].id))
            XCTAssertEqual(cv.selectionIndexPaths, [ip(1, 1)])
            let after = element(w.accessibilityTree(), role: .grid)!
            XCTAssertEqual(after.children.filter { $0.isSelected }.map(\.index), [6])
            XCTAssertEqual((cv.accessibilitySelectedChildren() ?? []).count, 1)
            w.close()
        }
    }

    // MARK: NSGridView

    /// A view with an intrinsic size (a grid's tracks size to their content).
    @MainActor final class Sized: NSView {
        let size: NSSize
        init(_ w: CGFloat, _ h: CGFloat) { size = NSSize(width: w, height: h); super.init(frame: NSRect(origin: .zero, size: size)) }
        required init?(coder: NSCoder) { nil }
        override var intrinsicContentSize: NSSize { size }
    }
    /// A view's frame in top-down coordinates of its grid (grids are not flipped).
    @MainActor private func top(_ v: NSView) -> NSRect {
        let g = v.superview!
        return NSRect(x: v.frame.minX, y: g.bounds.height - v.frame.maxY, width: v.frame.width, height: v.frame.height)
    }

    func testGridViewPlacesCellsInRowsAndColumns() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            let a = Sized(40, 20), b = Sized(60, 20), c = Sized(30, 30), d = Sized(20, 10)
            let grid = NSGridView(views: [[a, b], [c, d]])
            grid.columnSpacing = 10
            grid.rowSpacing = 4
            grid.translatesAutoresizingMaskIntoConstraints = false
            w.contentView!.addSubview(grid)
            NSLayoutConstraint.activate([grid.leadingAnchor.constraint(equalTo: w.contentView!.leadingAnchor, constant: 10), grid.topAnchor.constraint(equalTo: w.contentView!.topAnchor, constant: 10)])
            w.contentView!.layoutSubtreeIfNeeded()
            XCTAssertEqual(grid.numberOfRows, 2)
            XCTAssertEqual(grid.numberOfColumns, 2)
            XCTAssertTrue(grid.cell(atColumnIndex: 1, rowIndex: 0).contentView === b)
            XCTAssertTrue(grid.cell(for: d)?.row === grid.row(at: 1))
            XCTAssertEqual(grid.index(of: grid.column(at: 1)), 1)
            // Columns are as wide as their widest content, rows as tall as their tallest.
            XCTAssertEqual(grid.fittingSize, NSSize(width: 40 + 10 + 60, height: 20 + 4 + 30))
            XCTAssertEqual(top(a).origin, NSPoint(x: 0, y: 0))
            XCTAssertEqual(top(b).minX, 50)
            XCTAssertEqual(top(c).minY, 24)
            XCTAssertEqual(top(d).origin, NSPoint(x: 50, y: 24), "leading / top placement by default")
            XCTAssertEqual(d.frame.size, NSSize(width: 20, height: 10))
            // Trailing and centre placements move the smaller views in their tracks.
            grid.column(at: 1).xPlacement = .trailing
            grid.row(at: 1).yPlacement = .center
            w.contentView!.layoutSubtreeIfNeeded()
            XCTAssertEqual(top(d).maxX, 110)
            XCTAssertEqual(top(d).midY, 24 + 15, accuracy: 0.5)
            // Fill stretches, a fixed column width wins over the content.
            grid.cell(for: d)!.xPlacement = .fill
            grid.column(at: 0).width = 100
            w.contentView!.layoutSubtreeIfNeeded()
            XCTAssertEqual(d.frame.width, 60)
            XCTAssertEqual(top(b).minX, 110)
            XCTAssertEqual(grid.fittingSize.width, 100 + 10 + 60)
            // Hiding a column collapses it and its content; the row keeps its place.
            grid.column(at: 0).isHidden = true
            w.contentView!.layoutSubtreeIfNeeded()
            XCTAssertTrue(a.isHidden && c.isHidden)
            XCTAssertEqual(top(b).minX, 0)
            XCTAssertEqual(grid.fittingSize.width, 60)
            grid.column(at: 0).isHidden = false
            w.contentView!.layoutSubtreeIfNeeded()
            XCTAssertFalse(a.isHidden)
            XCTAssertEqual(top(b).minX, 110)
            grid.row(at: 0).isHidden = true
            w.contentView!.layoutSubtreeIfNeeded()
            XCTAssertEqual(top(c).minY, 0)
            XCTAssertEqual(grid.fittingSize.height, 30)
            // Rows and columns can be added, inserted, moved and removed.
            let e = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
            let row = grid.insertRow(at: 0, with: [e])
            XCTAssertEqual(grid.numberOfRows, 3)
            XCTAssertTrue(grid.row(at: 0) === row)
            XCTAssertTrue(row.cell(at: 0).contentView === e)
            XCTAssertNil(row.cell(at: 1).contentView)
            grid.moveRow(at: 0, to: 2)
            XCTAssertTrue(grid.row(at: 2) === row)
            grid.removeRow(at: 2)
            XCTAssertEqual(grid.numberOfRows, 2)
            XCTAssertNil(e.superview)
            _ = grid.addColumn(with: [NSView(frame: .zero)])
            XCTAssertEqual(grid.numberOfColumns, 3)
            grid.removeColumn(at: 2)
            XCTAssertEqual(grid.numberOfColumns, 2)
            w.close()
        }
    }

    func testGridViewMergesCellsAndAlignsBaselines() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            let title = Sized(30, 20), a = Sized(40, 20), b = Sized(60, 20), c = Sized(40, 20), d = Sized(60, 20)
            let grid = NSGridView(views: [[title, NSGridCell.emptyContentView], [a, b], [c, d]])
            grid.columnSpacing = 10
            grid.rowSpacing = 0
            grid.translatesAutoresizingMaskIntoConstraints = false
            w.contentView!.addSubview(grid)
            NSLayoutConstraint.activate([grid.leadingAnchor.constraint(equalTo: w.contentView!.leadingAnchor), grid.topAnchor.constraint(equalTo: w.contentView!.topAnchor)])
            XCTAssertNil(grid.cell(atColumnIndex: 1, rowIndex: 0).contentView, "the empty content view leaves the cell empty")
            grid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: 0, length: 1))
            grid.cell(for: title)!.xPlacement = .fill
            w.contentView!.layoutSubtreeIfNeeded()
            XCTAssertEqual(top(title), NSRect(x: 0, y: 0, width: 110, height: 20), "the merged title spans both columns")
            XCTAssertEqual(top(a).minY, 20)
            XCTAssertEqual(grid.fittingSize, NSSize(width: 110, height: 60))
            // A vertical merge through a row's API.
            grid.column(at: 0).mergeCells(in: NSRange(location: 1, length: 2))
            grid.cell(for: a)!.yPlacement = .fill
            w.contentView!.layoutSubtreeIfNeeded()
            XCTAssertEqual(a.frame.height, 40)
            XCTAssertNil(c.superview, "the other cell of the merged region loses its content")
            // Baseline rows: labels of different sizes share a baseline.
            let small = NSTextField(labelWithString: "small"), big = NSTextField(labelWithString: "big")
            big.font = NSFont.systemFont(ofSize: 24)
            let baseline = NSGridView(views: [[small, big]])
            baseline.rowAlignment = .lastBaseline
            baseline.translatesAutoresizingMaskIntoConstraints = false
            w.contentView!.addSubview(baseline)
            NSLayoutConstraint.activate([baseline.leadingAnchor.constraint(equalTo: w.contentView!.leadingAnchor), baseline.topAnchor.constraint(equalTo: w.contentView!.topAnchor, constant: 100)])
            w.contentView!.layoutSubtreeIfNeeded()
            // Baselines in the grid's (y-up) coordinates: the bottom plus the baseline offset.
            let smallBase = small.frame.minY + small.lastBaselineOffsetFromBottom
            let bigBase = big.frame.minY + big.lastBaselineOffsetFromBottom
            XCTAssertEqual(smallBase, bigBase, accuracy: 0.5, "the baselines meet")
            XCTAssertGreaterThan(top(small).minY, top(big).minY, "the small label sits lower than the big one's top")
            w.close()
        }
    }

    // MARK: NSBox

    func testBoxTitlePositionsBorderAndContent() {
        MainActor.assumeIsolated {
            let box = NSBox(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
            box.title = "Settings"
            XCTAssertEqual(box.boxType, .primary)
            XCTAssertEqual(box.titlePosition, .atTop)
            XCTAssertNotNil(box.contentView)
            XCTAssertTrue(box.contentView?.superview === box)
            let th = box.titleRect.height
            XCTAssertGreaterThan(th, 0)
            XCTAssertEqual(box.borderRect.minY, th / 2, "an 'at top' title straddles the border")
            XCTAssertEqual(box.titleRect.minX, 10)
            XCTAssertEqual(box.contentView!.frame.minY, th + 1 + 5, "the content starts below the title, the border and the margin")
            XCTAssertEqual(box.contentView!.frame.minX, 1 + 5)
            box.titlePosition = .aboveTop
            XCTAssertEqual(box.borderRect.minY, th)
            XCTAssertEqual(box.titleRect.minY, 0)
            box.titlePosition = .belowBottom
            XCTAssertEqual(box.borderRect.maxY, 120 - th)
            XCTAssertEqual(box.titleRect.maxY, 120)
            box.titlePosition = .noTitle
            XCTAssertEqual(box.borderRect, box.bounds)
            XCTAssertEqual(box.titleRect, .zero)
            XCTAssertEqual(box.contentView!.frame, NSRect(x: 6, y: 6, width: 188, height: 108))
            box.contentViewMargins = NSSize(width: 0, height: 0)
            XCTAssertEqual(box.contentView!.frame, NSRect(x: 1, y: 1, width: 198, height: 118))
            box.setFrameSize(NSSize(width: 100, height: 60))
            XCTAssertEqual(box.contentView!.frame, NSRect(x: 1, y: 1, width: 98, height: 58), "the content follows the box")
            box.setFrameFromContentFrame(NSRect(x: 20, y: 20, width: 50, height: 40))
            XCTAssertEqual(box.frame.size, NSSize(width: 52, height: 42), "the frame wraps the content frame in the border")
            box.setFrameSize(NSSize(width: 100, height: 60))
            box.boxType = .separator
            XCTAssertEqual(box.borderRect, NSRect(x: 0, y: 30, width: 100, height: 1), "a separator is a line across the middle")
            let custom = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
            box.contentView = custom
            XCTAssertTrue(box.contentView === custom)
            XCTAssertTrue(custom.superview === box)
        }
    }

    func testBoxDrawsFillBorderAndTransparency() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
            let box = NSBox(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
            box.boxType = .custom
            box.titlePosition = .noTitle
            box.fillColor = .blue
            box.borderColor = .red
            box.borderWidth = 4
            box.cornerRadius = 0
            w.contentView!.addSubview(box)
            w.makeKeyAndOrderFront(nil)
            var rep = render(box)
            let inside = pixel(rep, 100, 60), edge = pixel(rep, 1, 60)
            XCTAssertEqual(inside.b, 1, accuracy: 0.05, "the fill colour: \(inside)")
            XCTAssertEqual(inside.r, 0, accuracy: 0.05)
            XCTAssertEqual(edge.r, 1, accuracy: 0.05, "the border colour: \(edge)")
            XCTAssertEqual(edge.b, 0, accuracy: 0.05)
            box.isTransparent = true
            rep = render(box)
            XCTAssertEqual(pixel(rep, 100, 60).a, 0, accuracy: 0.05, "a transparent box draws nothing")
            box.isTransparent = false
            box.boxType = .separator
            rep = render(box)
            XCTAssertEqual(pixel(rep, 100, 30).a, 0, "nothing above the line")
            XCTAssertGreaterThan(pixel(rep, 100, 60).a, 0, "the separator line")
            // A titled primary box: the title is drawn where titleRect says.
            box.boxType = .primary
            box.titlePosition = .atTop
            box.title = "Settings"
            rep = render(box)
            let t = box.titleRect
            var ink = 0
            for x in Int(t.minX)..<Int(t.maxX) { for y in Int(t.minY)..<Int(t.maxY) { let p = pixel(rep, x, y); if p.a > 0.3 && p.r < 0.5 { ink += 1 } } }
            XCTAssertGreaterThan(ink, 10, "the title's ink")
            let tree = w.accessibilityTree()
            let group = tree.flattened.first { $0.role == "AXGroup" && $0.title == "Settings" }
            XCTAssertNotNil(group, "the box is an AXGroup titled by its title: \(tree.flattened.map { ($0.role, $0.title ?? "") })")
            w.close()
        }
    }
}
