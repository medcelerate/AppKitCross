// NSOpenPanel (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsopenpanel
@MainActor open class NSOpenPanel: NSSavePanel {
    private var _allowsMultipleSelection = false
    private var _canChooseDirectories = false
    private var _canChooseFiles = true
    private var _resolvesAliases = true
    private var _canDownloadUbiquitousContents = true
    private var _canResolveUbiquitousConflicts = true
    private var _isAccessoryViewDisclosed = false

    @MainActor public class func openPanel() -> NSOpenPanel { NSOpenPanel() }

    @MainActor internal override func _options() -> PlatformFileDialogOptions {
        var o = super._options()
        o.isSave = false
        o.canChooseFiles = _canChooseFiles
        o.canChooseDirectories = _canChooseDirectories
        o.allowsMultipleSelection = _allowsMultipleSelection
        return o
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsopenpanel/allowsmultipleselection
    @MainActor open var allowsMultipleSelection: Bool {
        get { _allowsMultipleSelection }
        set { _allowsMultipleSelection = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsopenpanel/canchoosedirectories
    @MainActor open var canChooseDirectories: Bool {
        get { _canChooseDirectories }
        set { _canChooseDirectories = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsopenpanel/canchoosefiles
    @MainActor open var canChooseFiles: Bool {
        get { _canChooseFiles }
        set { _canChooseFiles = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsopenpanel/candownloadubiquitouscontents
    @available(macOS 10.10, *)
    @MainActor open var canDownloadUbiquitousContents: Bool {
        get { _canDownloadUbiquitousContents }
        set { _canDownloadUbiquitousContents = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsopenpanel/canresolveubiquitousconflicts
    @available(macOS 10.10, *)
    @MainActor open var canResolveUbiquitousConflicts: Bool {
        get { _canResolveUbiquitousConflicts }
        set { _canResolveUbiquitousConflicts = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsopenpanel/isaccessoryviewdisclosed
    @available(macOS 10.11, *)
    @MainActor open var isAccessoryViewDisclosed: Bool {
        get { _isAccessoryViewDisclosed }
        set { _isAccessoryViewDisclosed = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsopenpanel/resolvesaliases
    @MainActor open var resolvesAliases: Bool {
        get { _resolvesAliases }
        set { _resolvesAliases = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsopenpanel/urls
    @MainActor open var urls: [URL] { _urls }
}
