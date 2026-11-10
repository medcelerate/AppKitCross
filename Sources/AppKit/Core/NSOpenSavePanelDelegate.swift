// NSOpenSavePanelDelegate (hand-written; seeded from the generated stub, see tools/apigen)
//
// Apple declares `NSSavePanel.delegate` as a redeclaration of `NSWindow.delegate` with a
// narrower type, which Objective-C allows and Swift does not. Here the protocol refines
// `NSWindowDelegate` instead, so `panel.delegate = self` stores the delegate in the
// window's slot and the panel reads it back as an `NSOpenSavePanelDelegate`; every
// `NSWindowDelegate` requirement is defaulted, so conformers implement nothing extra.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsopensavepaneldelegate
public protocol NSOpenSavePanelDelegate: NSWindowDelegate {
    @MainActor func panel(_ sender: Any, didChangeToDirectoryURL url: URL?)
    @MainActor func panel(_ sender: Any, didSelect type: UTType?)
    @MainActor func panel(_ sender: Any, displayNameFor type: UTType) -> String?
    @MainActor func panel(_ sender: Any, shouldEnable url: URL) -> Bool
    @MainActor func panel(_ sender: Any, userEnteredFilename filename: String, confirmed okFlag: Bool) -> String?
    @MainActor func panel(_ sender: Any, validate url: URL) throws
    @MainActor func panel(_ sender: Any, willExpand expanding: Bool)
    @MainActor func panelSelectionDidChange(_ sender: Any?)
}

// Optional requirements (ObjC `@optional`), modelled as defaulted requirements.
extension NSOpenSavePanelDelegate {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsopensavepaneldelegate/panel(_:didchangetodirectoryurl:)
    @MainActor public func panel(_ sender: Any, didChangeToDirectoryURL url: URL?) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsopensavepaneldelegate/panel(_:didselect:)
    @MainActor public func panel(_ sender: Any, didSelect type: UTType?) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsopensavepaneldelegate/panel(_:displaynamefor:)
    @MainActor public func panel(_ sender: Any, displayNameFor type: UTType) -> String? { return nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsopensavepaneldelegate/panel(_:shouldenable:)
    /// The default (as on macOS when the delegate does not implement it) enables every item.
    @MainActor public func panel(_ sender: Any, shouldEnable url: URL) -> Bool { return true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsopensavepaneldelegate/panel(_:userenteredfilename:confirmed:)
    /// The default keeps the name the user typed.
    @MainActor public func panel(_ sender: Any, userEnteredFilename filename: String, confirmed okFlag: Bool) -> String? { return filename }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsopensavepaneldelegate/panel(_:validate:)
    @MainActor public func panel(_ sender: Any, validate url: URL) throws { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsopensavepaneldelegate/panel(_:willexpand:)
    @MainActor public func panel(_ sender: Any, willExpand expanding: Bool) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsopensavepaneldelegate/panelselectiondidchange(_:)
    @MainActor public func panelSelectionDidChange(_ sender: Any?) { }
}
