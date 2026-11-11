// NSCollectionViewUpdateItem (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// One change of a batch update, as the collection view describes it to the layout in
// `prepare(forCollectionViewUpdates:)`. A section change carries an index path whose
// `item` is NSNotFound, as AppKit does.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewupdateitem
@available(macOS 10.11, *)
@MainActor open class NSCollectionViewUpdateItem: NSObject {
    private let _before: IndexPath?
    private let _after: IndexPath?
    private let _action: NSCollectionView.UpdateAction

    internal init(before: IndexPath?, after: IndexPath?, action: NSCollectionView.UpdateAction) {
        _before = before
        _after = after
        _action = action
        super.init()
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewupdateitem/indexpathafterupdate
    @MainActor open var indexPathAfterUpdate: IndexPath? { _after }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewupdateitem/indexpathbeforeupdate
    @MainActor open var indexPathBeforeUpdate: IndexPath? { _before }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewupdateitem/updateaction
    @MainActor open var updateAction: NSCollectionView.UpdateAction { _action }

    open override var description: String {
        MainActor.assumeIsolated { "<NSCollectionViewUpdateItem \(_action) \(String(describing: _before)) -> \(String(describing: _after))>" }
    }
}
