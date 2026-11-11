// IndexPath (hand-written AppKit additions, see tools/apigen `skipMembers`)
//
// The two-element index paths `NSCollectionView` uses: section and item.

import Foundation

extension IndexPath {
    /// Initialize for use with `NSCollectionView`.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/indexpath/init(item:section:)
    public init(item: Int, section: Int) { self.init(indexes: [section, item]) }
    /// The item of this index path, when used with `NSCollectionView`.
    ///
    /// - precondition: The index path must have exactly two elements.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/indexpath/item
    public var item: Int {
        get { precondition(count == 2, "IndexPath.item: the index path must have two elements"); return self[1] }
        set { precondition(count == 2, "IndexPath.item: the index path must have two elements"); self[1] = newValue }
    }
    /// The section of this index path, when used with `NSCollectionView`.
    ///
    /// - precondition: The index path must have exactly two elements.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/indexpath/section
    public var section: Int {
        get { precondition(count == 2, "IndexPath.section: the index path must have two elements"); return self[0] }
        set { precondition(count == 2, "IndexPath.section: the index path must have two elements"); self[0] = newValue }
    }
}
