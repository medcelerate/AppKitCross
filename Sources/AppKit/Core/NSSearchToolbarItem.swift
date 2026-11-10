// NSSearchToolbarItem: a search field in the toolbar. The field is an NSSearchField
// (the port's NSTextField with a rounded bezel and a "Search" placeholder); the item's
// view is the field, sized to `preferredWidthForSearchField`.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchtoolbaritem
@available(macOS 11.0, *)
@MainActor open class NSSearchToolbarItem: NSToolbarItem {
    private var _searchField: NSSearchField
    private var _preferredWidth: CGFloat = 180
    private var _resignsFirstResponderWithCancel = true

    @MainActor public override init(itemIdentifier: NSToolbarItem.Identifier) {
        let field = NSSearchField(frame: NSRect(x: 0, y: 0, width: 180, height: 22))
        field.placeholderString = "Search"
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        _searchField = field
        super.init(itemIdentifier: itemIdentifier)
        label = "Search"
        view = field
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchtoolbaritem/beginsearchinteraction()
    @MainActor open func beginSearchInteraction() {
        guard let w = _searchField.window else { return }
        _ = w.makeFirstResponder(_searchField)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchtoolbaritem/endsearchinteraction()
    @MainActor open func endSearchInteraction() {
        guard let w = _searchField.window, w.firstResponder === _searchField || (w.firstResponder as? NSView)?.isDescendant(of: _searchField) == true else { return }
        _ = w.makeFirstResponder(nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchtoolbaritem/preferredwidthforsearchfield
    @MainActor open var preferredWidthForSearchField: CGFloat {
        get { _preferredWidth }
        set { _preferredWidth = newValue; _searchField.setFrameSize(NSSize(width: newValue, height: _searchField.frame.height)); _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchtoolbaritem/resignsfirstresponderwithcancel
    @MainActor open var resignsFirstResponderWithCancel: Bool {
        get { _resignsFirstResponderWithCancel }
        set { _resignsFirstResponderWithCancel = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchtoolbaritem/searchfield
    @MainActor open var searchField: NSSearchField {
        get { _searchField }
        set { _searchField = newValue; view = newValue }
    }

    /// Search fields are never disabled by validation (they have no action of their own).
    open override func validate() { }
}
