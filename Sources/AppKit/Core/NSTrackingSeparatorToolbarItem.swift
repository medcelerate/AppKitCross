// NSTrackingSeparatorToolbarItem: a separator line that follows a split view's
// divider. The toolbar lays the items before it out in the split view's leading pane
// and the items after it in the rest of the width (NSToolbarView.swift).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstrackingseparatortoolbaritem
@available(macOS 11.0, *)
@MainActor open class NSTrackingSeparatorToolbarItem: NSToolbarItem {
    private var _splitView: NSSplitView?
    private var _dividerIndex = 0

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstrackingseparatortoolbaritem/init(identifier:splitview:dividerindex:)
    @MainActor public convenience init(identifier: NSToolbarItem.Identifier, splitView: NSSplitView, dividerIndex: Int) {
        self.init(itemIdentifier: identifier)
        _splitView = splitView
        _dividerIndex = dividerIndex
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstrackingseparatortoolbaritem/dividerindex
    @MainActor open var dividerIndex: Int {
        get { _dividerIndex }
        set { _dividerIndex = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstrackingseparatortoolbaritem/splitview
    /// Reading it before `init(identifier:splitView:dividerIndex:)` set one is a
    /// programming error, as in AppKit.
    @MainActor open var splitView: NSSplitView {
        get { _splitView! }
        set { _splitView = newValue; _changed() }
    }

    /// The divider's x in the window's content coordinates, when the split view is in a
    /// window and the divider exists; nil otherwise (the separator then takes its place
    /// in the row like a plain separator).
    internal var _trackedX: CGFloat? {
        guard let sv = _splitView, sv.window != nil, sv.isVertical else { return nil }
        let panes = sv.arrangedSubviews.isEmpty ? sv.subviews : sv.arrangedSubviews
        guard _dividerIndex >= 0, _dividerIndex < panes.count - 1 else { return nil }
        let pane = panes[_dividerIndex]
        let dividerLeft = NSPoint(x: pane.frame.maxX, y: pane.frame.midY)
        return sv.convert(dividerLeft, to: nil).x + sv.dividerThickness / 2
    }

    /// Separators are never validated against a target.
    open override func validate() { }
}
