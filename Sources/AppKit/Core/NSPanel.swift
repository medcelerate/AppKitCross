// NSPanel (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() are stubs awaiting implementation.
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nspanel
@MainActor open class NSPanel: NSWindow {
    /// A panel never becomes the main window, as in AppKit: a sheet or an inspector that
    /// takes the keyboard leaves its document window main, so nil-target actions (File >
    /// Print… while Page Setup is up) still reach the document through the main window's
    /// responder chain instead of validating as disabled against the panel's.
    @MainActor open override var canBecomeMain: Bool { false }
    private var _becomesKeyOnlyIfNeeded = false
    private var _isFloatingPanel = false
    private var _worksWhenModal = false
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded
    @MainActor open var becomesKeyOnlyIfNeeded: Bool {
        get { _becomesKeyOnlyIfNeeded }
        set { _becomesKeyOnlyIfNeeded = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspanel/isfloatingpanel
    @MainActor open override var isFloatingPanel: Bool {
        get { _isFloatingPanel }
        set { _isFloatingPanel = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspanel/workswhenmodal
    @MainActor open override var worksWhenModal: Bool {
        get { _worksWhenModal }
        set { _worksWhenModal = newValue }
    }
}
