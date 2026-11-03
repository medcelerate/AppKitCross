// NSDraggingSession (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingsession
open class NSDraggingSession: NSObject {
    nonisolated(unsafe) private static var _nextSequenceNumber = 1

    internal let _items: [NSDraggingItem]
    internal let _pasteboard: NSPasteboard
    internal let _sequenceNumber: Int
    internal var _location: NSPoint = .zero          // screen coordinates
    internal weak var _source: AnyObject?
    private var _animatesToStartingPositions = true
    private var _formation: NSDraggingFormation = .default
    private var _leaderIndex = 0

    internal init(items: [NSDraggingItem], source: AnyObject?) {
        _items = items
        _source = source
        _sequenceNumber = NSDraggingSession._nextSequenceNumber
        NSDraggingSession._nextSequenceNumber += 1
        let pb = NSPasteboard(name: NSPasteboard.Name("drag-\(_sequenceNumber)"))
        _pasteboard = pb
        super.init()
        _ = pb.clearContents()
        pb.writeObjects(items.map { $0._makePasteboardItem(for: pb) })
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingsession/animatestostartingpositionsoncancelorfail
    open var animatesToStartingPositionsOnCancelOrFail: Bool {
        get { _animatesToStartingPositions }
        set { _animatesToStartingPositions = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingsession/draggingformation
    open var draggingFormation: NSDraggingFormation {
        get { _formation }
        set { _formation = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingsession/draggingleaderindex
    open var draggingLeaderIndex: Int {
        get { _leaderIndex }
        set { _leaderIndex = newValue }
    }
    /// The current pointer location in screen coordinates.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingsession/dragginglocation
    open var draggingLocation: NSPoint { _location }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingsession/draggingpasteboard
    open var draggingPasteboard: NSPasteboard { _pasteboard }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingsession/draggingsequencenumber
    open var draggingSequenceNumber: Int { _sequenceNumber }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingsession/enumeratedraggingitems(options:for:classes:searchoptions:using:)
    open func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey : Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {
        var stop = ObjCBool(false)
        for (i, item) in _items.enumerated() {
            block(item, i, &stop)
            if stop.boolValue { break }
        }
    }
}
