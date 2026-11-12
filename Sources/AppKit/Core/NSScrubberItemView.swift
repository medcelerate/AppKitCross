// NSScrubberItemView (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// The base class of a scrubber's item views (ADR-0034). A class registered with
// `NSScrubber.register(_:forItemIdentifier:)` is made through `init?(coder:)`, as for
// collection views: the port cannot call `init(frame:)` through a metatype.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberitemview
@available(macOS 10.12, *)
@MainActor open class NSScrubberItemView: NSScrubberArrangedView {
}
