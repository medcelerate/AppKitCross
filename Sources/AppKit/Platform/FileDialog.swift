// The file-dialog seam (ADR-0017). `NSSavePanel` and `NSOpenPanel` ask the backend for a
// `PlatformFileDialog`; when it has one the panel's `runModal`, `begin` and
// `beginSheetModal` show the operating system's dialog (IFileOpenDialog/IFileSaveDialog
// on Windows, the xdg-desktop-portal FileChooser on Linux) and answer with what it chose.
// When the backend has none (the host backend, Linux without a portal) the panel draws
// itself with the package's own views: a path field, a directory listing in an
// `NSTableView`, type filtering, New Folder, Cancel and OK.
//
// `APPKITWIN_FILE_DIALOG=package` forces the package-drawn panel on every platform (and
// `=native` the native one where there is one), for screenshots and tests.

import Foundation

/// What a panel asks of a dialog: everything the native dialogs understand.
public struct PlatformFileDialogOptions: Sendable {
    public var isSave = false
    public var title: String? = nil
    /// The confirm button's label.
    public var prompt: String? = nil
    public var message: String? = nil
    public var directory: URL? = nil
    public var defaultName: String? = nil
    /// Filename extensions without dots; empty means any file.
    public var allowedExtensions: [String] = []
    /// Human-readable names for the extensions, parallel to `allowedExtensions` where
    /// known (the dialog's type filter labels).
    public var allowedTypeDescriptions: [String] = []
    public var allowsOtherTypes = true
    /// The extension of the type selected to begin with (a save panel's current content
    /// type): a native dialog preselects that type's filter and appends it to a name typed
    /// without one. nil means the first allowed extension.
    public var defaultExtension: String? = nil
    public var canChooseFiles = true
    public var canChooseDirectories = false
    public var allowsMultipleSelection = false
    public var canCreateDirectories = true
    public var showsHiddenFiles = false
    public var treatsFilePackagesAsDirectories = false
    public init() {}
}

/// The operating system's open/save dialog. The call blocks until the dialog closes
/// (the backend keeps its own event loop running meanwhile) and answers nil when
/// cancelled.
@MainActor
public protocol PlatformFileDialog: AnyObject {
    func run(_ options: PlatformFileDialogOptions, parent: PlatformWindow?) -> [URL]?
}

extension PlatformBackend {
    /// The native dialog, or nil when the panel should draw itself. The default is nil.
    public var fileDialog: (any PlatformFileDialog)? { nil }
}

enum PlatformFileDialogPolicy {
    /// Whether a native dialog may be used, after `APPKITWIN_FILE_DIALOG`.
    static var allowsNative: Bool {
        ProcessInfo.processInfo.environment["APPKITWIN_FILE_DIALOG"]?.lowercased() != "package"
    }
}
