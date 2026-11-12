// NSBrowserDelegate (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every requirement is `@optional` in AppKit, which asks `respondsToSelector:` to choose
// how a browser gets its content: item-based (`numberOfChildrenOfItem`), passive
// matrix-based (`numberOfRowsInColumn` with `willDisplayCell`) or active matrix-based
// (`createRowsForColumn`), and whether to use the delegate's title matching, row heights
// and so on. Swift has no `respondsToSelector:` for protocol extensions, so the defaults
// whose absence changes what NSBrowser does report it through
// `NSBrowser._noteDelegateMethodMissing()` (ADR-0032); the others carry AppKit's
// behaviour when a delegate leaves them out.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(QuartzCore)
import QuartzCore
#endif
#if canImport(CoreText)
import CoreText
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate
public protocol NSBrowserDelegate: NSObjectProtocol {
    @MainActor func browser(_ browser: NSBrowser, acceptDrop info: any NSDraggingInfo, atRow row: Int, column: Int, dropOperation: NSBrowser.DropOperation) -> Bool
    @MainActor func browser(_ browser: NSBrowser, canDragRowsWith rowIndexes: IndexSet, inColumn column: Int, with event: NSEvent) -> Bool
    @MainActor func browser(_ browser: NSBrowser, child index: Int, ofItem item: Any?) -> Any
    @MainActor func browser(_ sender: NSBrowser, createRowsForColumn column: Int, in matrix: NSMatrix)
    @MainActor func browser(_ browser: NSBrowser, didChangeLastColumn oldLastColumn: Int, toColumn column: Int)
    @MainActor func browser(_ browser: NSBrowser, draggingImageForRowsWith rowIndexes: IndexSet, inColumn column: Int, with event: NSEvent, offset dragImageOffset: NSPointPointer) -> NSImage?
    @MainActor func browser(_ browser: NSBrowser, headerViewControllerForItem item: Any?) -> NSViewController?
    @MainActor func browser(_ browser: NSBrowser, heightOfRow row: Int, inColumn columnIndex: Int) -> CGFloat
    @MainActor func browser(_ sender: NSBrowser, isColumnValid column: Int) -> Bool
    @MainActor func browser(_ browser: NSBrowser, isLeafItem item: Any?) -> Bool
    func browser(_ browser: NSBrowser, namesOfPromisedFilesDroppedAtDestination dropDestination: URL, forDraggedRowsWith rowIndexes: IndexSet, inColumn column: Int) -> [String]
    @MainActor func browser(_ browser: NSBrowser, nextTypeSelectMatchFromRow startRow: Int, toRow endRow: Int, inColumn column: Int, for searchString: String?) -> Int
    @MainActor func browser(_ browser: NSBrowser, numberOfChildrenOfItem item: Any?) -> Int
    @MainActor func browser(_ sender: NSBrowser, numberOfRowsInColumn column: Int) -> Int
    @MainActor func browser(_ browser: NSBrowser, objectValueForItem item: Any?) -> Any?
    @MainActor func browser(_ browser: NSBrowser, previewViewControllerForLeafItem item: Any) -> NSViewController?
    @MainActor func browser(_ sender: NSBrowser, selectCellWith title: String, inColumn column: Int) -> Bool
    @MainActor func browser(_ sender: NSBrowser, selectRow row: Int, inColumn column: Int) -> Bool
    @MainActor func browser(_ browser: NSBrowser, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet, inColumn column: Int) -> IndexSet
    @MainActor func browser(_ browser: NSBrowser, setObjectValue object: Any?, forItem item: Any?)
    @MainActor func browser(_ browser: NSBrowser, shouldEditItem item: Any?) -> Bool
    @MainActor func browser(_ browser: NSBrowser, shouldShowCellExpansionForRow row: Int, column: Int) -> Bool
    @MainActor func browser(_ browser: NSBrowser, shouldSizeColumn columnIndex: Int, forUserResize: Bool, toWidth suggestedWidth: CGFloat) -> CGFloat
    @MainActor func browser(_ browser: NSBrowser, shouldTypeSelectFor event: NSEvent, withCurrentSearch searchString: String?) -> Bool
    @MainActor func browser(_ browser: NSBrowser, sizeToFitWidthOfColumn columnIndex: Int) -> CGFloat
    @MainActor func browser(_ sender: NSBrowser, titleOfColumn column: Int) -> String?
    @MainActor func browser(_ browser: NSBrowser, typeSelectStringForRow row: Int, inColumn column: Int) -> String?
    @MainActor func browser(_ browser: NSBrowser, validateDrop info: any NSDraggingInfo, proposedRow row: UnsafeMutablePointer<Int>, column: UnsafeMutablePointer<Int>, dropOperation: UnsafeMutablePointer<NSBrowser.DropOperation>) -> NSDragOperation
    @MainActor func browser(_ sender: NSBrowser, willDisplayCell cell: Any, atRow row: Int, column: Int)
    @MainActor func browser(_ browser: NSBrowser, writeRowsWith rowIndexes: IndexSet, inColumn column: Int, to pasteboard: NSPasteboard) -> Bool
    @available(macOS 10.10, *)
    @MainActor func browserColumnConfigurationDidChange(_ notification: Notification)
    @MainActor func browserDidScroll(_ sender: NSBrowser)
    @MainActor func browserWillScroll(_ sender: NSBrowser)
    @MainActor func rootItem(for browser: NSBrowser) -> Any?
}

// Optional requirements (ObjC `@optional`), modelled as defaulted requirements.
extension NSBrowserDelegate {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:acceptdrop:atrow:column:dropoperation:)
    @MainActor public func browser(_ browser: NSBrowser, acceptDrop info: any NSDraggingInfo, atRow row: Int, column: Int, dropOperation: NSBrowser.DropOperation) -> Bool { return false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:candragrowswith:incolumn:with:)
    @MainActor public func browser(_ browser: NSBrowser, canDragRowsWith rowIndexes: IndexSet, inColumn column: Int, with event: NSEvent) -> Bool { return false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:child:ofitem:)
    @MainActor public func browser(_ browser: NSBrowser, child index: Int, ofItem item: Any?) -> Any { unimplementedOptionalRequirement() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:createrowsforcolumn:in:)
    @MainActor public func browser(_ sender: NSBrowser, createRowsForColumn column: Int, in matrix: NSMatrix) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:didchangelastcolumn:tocolumn:)
    @MainActor public func browser(_ browser: NSBrowser, didChangeLastColumn oldLastColumn: Int, toColumn column: Int) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:draggingimageforrowswith:incolumn:with:offset:)
    @MainActor public func browser(_ browser: NSBrowser, draggingImageForRowsWith rowIndexes: IndexSet, inColumn column: Int, with event: NSEvent, offset dragImageOffset: NSPointPointer) -> NSImage? { return nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:headerviewcontrollerforitem:)
    @MainActor public func browser(_ browser: NSBrowser, headerViewControllerForItem item: Any?) -> NSViewController? { return nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:heightofrow:incolumn:)
    @MainActor public func browser(_ browser: NSBrowser, heightOfRow row: Int, inColumn columnIndex: Int) -> CGFloat { NSBrowser._noteDelegateMethodMissing(); return browser.rowHeight }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:iscolumnvalid:)
    @MainActor public func browser(_ sender: NSBrowser, isColumnValid column: Int) -> Bool { return true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:isleafitem:)
    @MainActor public func browser(_ browser: NSBrowser, isLeafItem item: Any?) -> Bool { return false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:namesofpromisedfilesdroppedatdestination:fordraggedrowswith:incolumn:)
    public func browser(_ browser: NSBrowser, namesOfPromisedFilesDroppedAtDestination dropDestination: URL, forDraggedRowsWith rowIndexes: IndexSet, inColumn column: Int) -> [String] { unimplementedOptionalRequirement() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:nexttypeselectmatchfromrow:torow:incolumn:for:)
    @MainActor public func browser(_ browser: NSBrowser, nextTypeSelectMatchFromRow startRow: Int, toRow endRow: Int, inColumn column: Int, for searchString: String?) -> Int { NSBrowser._noteDelegateMethodMissing(); return -1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:numberofchildrenofitem:)
    @MainActor public func browser(_ browser: NSBrowser, numberOfChildrenOfItem item: Any?) -> Int { NSBrowser._noteDelegateMethodMissing(); return 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:numberofrowsincolumn:)
    @MainActor public func browser(_ sender: NSBrowser, numberOfRowsInColumn column: Int) -> Int { NSBrowser._noteDelegateMethodMissing(); return 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:objectvalueforitem:)
    @MainActor public func browser(_ browser: NSBrowser, objectValueForItem item: Any?) -> Any? { return nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:previewviewcontrollerforleafitem:)
    @MainActor public func browser(_ browser: NSBrowser, previewViewControllerForLeafItem item: Any) -> NSViewController? { return nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:selectcellwith:incolumn:)
    @MainActor public func browser(_ sender: NSBrowser, selectCellWith title: String, inColumn column: Int) -> Bool { NSBrowser._noteDelegateMethodMissing(); return false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:selectrow:incolumn:)
    @MainActor public func browser(_ sender: NSBrowser, selectRow row: Int, inColumn column: Int) -> Bool { NSBrowser._noteDelegateMethodMissing(); return false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:selectionindexesforproposedselection:incolumn:)
    @MainActor public func browser(_ browser: NSBrowser, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet, inColumn column: Int) -> IndexSet { proposedSelectionIndexes }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:setobjectvalue:foritem:)
    @MainActor public func browser(_ browser: NSBrowser, setObjectValue object: Any?, forItem item: Any?) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:shouldedititem:)
    @MainActor public func browser(_ browser: NSBrowser, shouldEditItem item: Any?) -> Bool { return false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:shouldshowcellexpansionforrow:column:)
    @MainActor public func browser(_ browser: NSBrowser, shouldShowCellExpansionForRow row: Int, column: Int) -> Bool { return false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:shouldsizecolumn:foruserresize:towidth:)
    @MainActor public func browser(_ browser: NSBrowser, shouldSizeColumn columnIndex: Int, forUserResize: Bool, toWidth suggestedWidth: CGFloat) -> CGFloat { suggestedWidth }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:shouldtypeselectfor:withcurrentsearch:)
    @MainActor public func browser(_ browser: NSBrowser, shouldTypeSelectFor event: NSEvent, withCurrentSearch searchString: String?) -> Bool { return true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:sizetofitwidthofcolumn:)
    @MainActor public func browser(_ browser: NSBrowser, sizeToFitWidthOfColumn columnIndex: Int) -> CGFloat { browser._fittingWidth(ofColumn: columnIndex) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:titleofcolumn:)
    @MainActor public func browser(_ sender: NSBrowser, titleOfColumn column: Int) -> String? { return nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:typeselectstringforrow:incolumn:)
    @MainActor public func browser(_ browser: NSBrowser, typeSelectStringForRow row: Int, inColumn column: Int) -> String? { return nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:validatedrop:proposedrow:column:dropoperation:)
    @MainActor public func browser(_ browser: NSBrowser, validateDrop info: any NSDraggingInfo, proposedRow row: UnsafeMutablePointer<Int>, column: UnsafeMutablePointer<Int>, dropOperation: UnsafeMutablePointer<NSBrowser.DropOperation>) -> NSDragOperation { unimplementedOptionalRequirement() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:willdisplaycell:atrow:column:)
    @MainActor public func browser(_ sender: NSBrowser, willDisplayCell cell: Any, atRow row: Int, column: Int) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browser(_:writerowswith:incolumn:to:)
    @MainActor public func browser(_ browser: NSBrowser, writeRowsWith rowIndexes: IndexSet, inColumn column: Int, to pasteboard: NSPasteboard) -> Bool { return false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browsercolumnconfigurationdidchange(_:)
    @available(macOS 10.10, *)
    @MainActor public func browserColumnConfigurationDidChange(_ notification: Notification) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browserdidscroll(_:)
    @MainActor public func browserDidScroll(_ sender: NSBrowser) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/browserwillscroll(_:)
    @MainActor public func browserWillScroll(_ sender: NSBrowser) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowserdelegate/rootitem(for:)
    @MainActor public func rootItem(for browser: NSBrowser) -> Any? { return nil }
}

