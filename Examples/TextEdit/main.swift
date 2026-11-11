// TextEdit: a document-based application on NSDocument and NSDocumentController, same
// source on macOS, Windows and Linux. Plain text, Markdown and RTF documents, declared in
// Info.plist (CFBundleDocumentTypes); the File menu's New, Open, Open Recent, Close, Save,
// Save As, Revert and Quit go through the responder chain to the document and the
// document controller; closing an edited window or quitting asks about unsaved changes;
// the window title carries the file name and the edited mark.
//
// Headless modes for CI: `--roundtrip out.rtf` makes a document through the document
// controller, writes it as RTF, reads it back and checks the attributes;
// `--show-save-panel` opens an untitled document with the save panel up (screenshots).

import AppKit
import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if os(Windows)
import WinSDK
#endif

/// Sets an environment variable for this process (`setenv` is POSIX; Windows has
/// `SetEnvironmentVariableW`, which `ProcessInfo.environment` reads back).
func setEnvironmentVariable(_ name: String, _ value: String) {
#if os(Windows)
    let n = Array(name.utf16) + [0], v = Array(value.utf16) + [0]
    _ = n.withUnsafeBufferPointer { n in v.withUnsafeBufferPointer { v in SetEnvironmentVariableW(n.baseAddress, v.baseAddress) } }
#else
    setenv(name, value, 1)
#endif
}

// Without a bundle, the document controller reads Info.plist from APPKITWIN_INFO_PLIST
// or from next to the executable; SwiftPM puts resources elsewhere (and refuses a resource
// named Info.plist), so point it at the copy in the resource bundle.
if ProcessInfo.processInfo.environment["APPKITWIN_INFO_PLIST"] == nil, let plist = Bundle.module.url(forResource: "TextEdit-Info", withExtension: "plist", subdirectory: "Resources") {
    setEnvironmentVariable("APPKITWIN_INFO_PLIST", plist.path)
}

/// One text document: plain text (UTF-8) or RTF, edited in an NSTextView.
final class TextDocument: NSDocument {
    /// The model: the text with its attributes. The text view's storage is the live copy
    /// while a window is open.
    var contents = NSAttributedString(string: "")
    private var textView: NSTextView?
    private var changeObserver: NSObjectProtocol?

    nonisolated static let rtfType = "public.rtf"

    var isRichText: Bool { fileType == TextDocument.rtfType }

    // MARK: Reading and writing

    override func read(from data: Data, ofType typeName: String) throws {
        let text: NSAttributedString
        if typeName == TextDocument.rtfType {
            guard let rtf = NSAttributedString(rtf: data, documentAttributes: nil) else {
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileReadCorruptFile.rawValue,
                              userInfo: [NSLocalizedDescriptionKey: "The file is not valid RTF."])
            }
            text = rtf
        } else {
            guard let string = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileReadInapplicableStringEncoding.rawValue,
                              userInfo: [NSLocalizedDescriptionKey: "The file's text encoding is not supported."])
            }
            text = NSAttributedString(string: string, attributes: [.font: NSFont.userFont(ofSize: 13) ?? NSFont.systemFont(ofSize: 13)])
        }
        MainActor.assumeIsolated {
            contents = text
            if let tv = textView { tv.textStorage?.setAttributedString(text) }
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        let text = textView?.textStorage.map { NSAttributedString(attributedString: $0) } ?? contents
        if typeName == TextDocument.rtfType {
            guard let data = text.rtf(from: NSRange(location: 0, length: text.length)) else {
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileWriteUnknown.rawValue, userInfo: [NSLocalizedDescriptionKey: "The text could not be written as RTF."])
            }
            return data
        }
        guard let data = text.string.data(using: .utf8) else {
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileWriteInapplicableStringEncoding.rawValue, userInfo: [NSLocalizedDescriptionKey: "The text cannot be encoded as UTF-8."])
        }
        return data
    }

    // MARK: Windows

    override func makeWindowControllers() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 460),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 320, height: 200)
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        let tv = NSTextView(frame: scroll.bounds)
        tv.autoresizingMask = [.width, .height]
        tv.isRichText = isRichText
        tv.font = NSFont.userFont(ofSize: 13)
        tv.textStorage?.setAttributedString(contents)
        tv.setAccessibilityLabel("Document text")
        scroll.documentView = tv
        window.contentView?.addSubview(scroll)
        window.initialFirstResponder = tv
        textView = tv
        // Each edit is a change (the text view does not register undo actions yet, so the
        // undo manager cannot drive the change count).
        changeObserver = NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: tv, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateChangeCount(.changeDone) }
        }
        let controller = NSWindowController(window: window)
        controller.shouldCascadeWindows = true
        addWindowController(controller)
        // Cascade new windows a little so untitled documents do not stack exactly.
        let n = NSDocumentController.shared.documents.count
        window.center()
        window.setFrameOrigin(NSPoint(x: window.frame.minX + CGFloat(n % 6) * 24, y: window.frame.minY - CGFloat(n % 6) * 24))
    }

    override func close() {
        if let o = changeObserver { NotificationCenter.default.removeObserver(o); changeObserver = nil }
        super.close()
    }

    /// Format > Make Rich Text / Make Plain Text: switches the document's type; the next
    /// save goes through the save panel with the matching extension.
    func toggleRichText() {
        fileType = isRichText ? "public.plain-text" : TextDocument.rtfType
        textView?.isRichText = isRichText
        fileURL = nil
        updateChangeCount(.changeDone)
    }

    override func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        if NSStringFromSelector(action) == "toggleRichText:" { toggleRichText(); return true }
        return super.performSelectorAction(action, with: sender)
    }
    override func respondsToSelectorAction(_ action: Selector) -> Bool {
        NSStringFromSelector(action) == "toggleRichText:" || super.respondsToSelectorAction(action)
    }
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action.map(NSStringFromSelector) == "toggleRichText:" {
            menuItem.title = isRichText ? "Make Plain Text" : "Make Rich Text"
            return true
        }
        return super.validateMenuItem(menuItem)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // The menu bar before documents open, so Open Recent is found and filled.
        let main = NSMenu(title: "Main")

        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "New", action: Selector(("newDocument:")), keyEquivalent: "n")
        file.addItem(withTitle: "Open\u{2026}", action: Selector(("openDocument:")), keyEquivalent: "o")
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = NSMenu(title: "Open Recent")
        file.addItem(recentItem)
        file.addItem(NSMenuItem.separator())
        file.addItem(withTitle: "Close", action: Selector(("performClose:")), keyEquivalent: "w")
        file.addItem(withTitle: "Save", action: Selector(("saveDocument:")), keyEquivalent: "s")
        let saveAs = file.addItem(withTitle: "Save As\u{2026}", action: Selector(("saveDocumentAs:")), keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(withTitle: "Revert to Saved", action: Selector(("revertDocumentToSaved:")), keyEquivalent: "")
        file.addItem(NSMenuItem.separator())
        file.addItem(withTitle: "Quit TextEdit", action: Selector(("terminate:")), keyEquivalent: "q")
        fileItem.submenu = file
        main.addItem(fileItem)

        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
        edit.addItem(NSMenuItem.separator())
        edit.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let formatItem = NSMenuItem(title: "Format", action: nil, keyEquivalent: "")
        let format = NSMenu(title: "Format")
        let rich = format.addItem(withTitle: "Make Rich Text", action: Selector(("toggleRichText:")), keyEquivalent: "t")
        rich.keyEquivalentModifierMask = [.command, .shift]
        formatItem.submenu = format
        main.addItem(formatItem)

        NSApp.mainMenu = main
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - Headless modes

/// `--roundtrip out.rtf`: no windows; the document controller's types from Info.plist, a
/// document made through it, RTF written and read back with its attributes intact.
@MainActor func roundTrip(to path: String) -> Int32 {
    let dc = NSDocumentController.shared
    let url = URL(fileURLWithPath: path)
    do {
        guard dc.documentClass(forType: "public.rtf") == TextDocument.self else {
            print("FAIL: Info.plist did not map public.rtf to TextDocument (classes: \(dc.documentClassNames), types: \(dc.defaultType ?? "none"))")
            return 1
        }
        let doc = try dc.makeUntitledDocument(ofType: "public.rtf") as! TextDocument
        let text = NSMutableAttributedString(string: "Hello, documents!\nSecond paragraph, centred.\n", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        text.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 14), range: NSRange(location: 0, length: 5))
        text.addAttribute(.foregroundColor, value: NSColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1), range: NSRange(location: 7, length: 9))
        let centred = NSMutableParagraphStyle()
        centred.alignment = .center
        text.addAttribute(.paragraphStyle, value: centred, range: NSRange(location: 18, length: 27))
        doc.contents = text
        try doc.write(to: url, ofType: "public.rtf")
        print("wrote \(url.path) (\(try Data(contentsOf: url).count) bytes)")
        let type = try dc.typeForContents(of: url)
        guard type == "public.rtf" else { print("FAIL: typeForContents gave \(type)"); return 1 }
        let back = try dc.makeDocument(withContentsOf: url, ofType: type) as! TextDocument
        let s = back.contents
        guard s.string == text.string else { print("FAIL: text differs: \(s.string.debugDescription)"); return 1 }
        let bold = s.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        guard let bold, NSFontManager.shared.traits(of: bold).contains(.boldFontMask) else { print("FAIL: bold lost"); return 1 }
        guard let color = s.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor, color.redComponent > 0.7 else { print("FAIL: colour lost"); return 1 }
        guard (s.attribute(.paragraphStyle, at: 20, effectiveRange: nil) as? NSParagraphStyle)?.alignment == .center else { print("FAIL: alignment lost"); return 1 }
        guard back.fileURL == url, back.displayName == url.lastPathComponent, !back.isDocumentEdited else { print("FAIL: document state"); return 1 }
        print("round trip OK: \(s.length) characters, bold, colour and alignment kept; types \(dc.documentClassNames)")
        return 0
    } catch {
        print("FAIL: \(error)")
        return 1
    }
}

let arguments = CommandLine.arguments.dropFirst()
if let i = arguments.firstIndex(of: "--roundtrip"), i + 1 <= arguments.endIndex - 1 {
    exit(roundTrip(to: arguments[i + 1]))
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
if arguments.contains("--show-save-panel") {
    // For screenshots: an untitled document with its save panel up (the package-drawn
    // panel under Xvfb without a portal, or with APPKITWIN_FILE_DIALOG=package).
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        NSDocumentController.shared.currentDocument?.saveAs(nil)
    }
}
app.run()
