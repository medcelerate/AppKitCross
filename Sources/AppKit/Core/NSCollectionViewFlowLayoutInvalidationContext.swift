// NSCollectionViewFlowLayoutInvalidationContext (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewflowlayoutinvalidationcontext
@available(macOS 10.11, *)
@MainActor open class NSCollectionViewFlowLayoutInvalidationContext: NSCollectionViewLayoutInvalidationContext {
    private var _invalidateAttributes = true
    private var _invalidateDelegateMetrics = true

    public required override init() { super.init() }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewflowlayoutinvalidationcontext/invalidateflowlayoutattributes
    @MainActor open var invalidateFlowLayoutAttributes: Bool {
        get { _invalidateAttributes }
        set { _invalidateAttributes = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewflowlayoutinvalidationcontext/invalidateflowlayoutdelegatemetrics
    @MainActor open var invalidateFlowLayoutDelegateMetrics: Bool {
        get { _invalidateDelegateMetrics }
        set { _invalidateDelegateMetrics = newValue }
    }
}
