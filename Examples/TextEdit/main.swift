// TextEdit: a document-based application on NSDocument and NSDocumentController, same
// source on macOS, Windows and Linux. Plain text, Markdown and RTF documents, declared in
// Info.plist (CFBundleDocumentTypes); the File menu's New, Open, Open Recent, Close, Save,
// Save As, Revert and Quit go through the responder chain to the document and the
// document controller; closing an edited window or quitting asks about unsaved changes;
// the window title carries the file name and the edited mark.
//
// The text view is an editor (ADR-0030): Edit > Find (the find bar), Spelling and Grammar
// (continuous checking, the Spelling panel, guesses in the context menu), Substitutions
// and Complete; Format > Lists and Table; images dropped or pasted into rich text become
// attachments, and a rich document with attachments is saved as RTFD.
//
// Headless modes for CI: `--roundtrip out.rtf` makes a document through the document
// controller, writes it as RTF, reads it back and checks the attributes;
// `--roundtrip-rtfd out.rtfd` does the same for a list, a table and an attachment in RTFD;
// `--show-save-panel` opens an untitled document with the save panel up (screenshots);
// `--sample-screenshot dir` renders a document with a list, a table and an attachment to
// dir/textedit-sample-<platform>.png (the comparison page).

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
    nonisolated static let rtfdType = "com.apple.rtfd"

    var isRichText: Bool { fileType == TextDocument.rtfType || fileType == TextDocument.rtfdType }

    // MARK: RTFD (a directory: TXT.rtf and the attachments' files)

    override func read(from fileWrapper: FileWrapper, ofType typeName: String) throws {
        guard typeName == TextDocument.rtfdType else { return try super.read(from: fileWrapper, ofType: typeName) }
        guard let parsed = NSAttributedString(RTFDFileWrapper: fileWrapper, documentAttributes: nil) else {
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileReadCorruptFile.rawValue,
                          userInfo: [NSLocalizedDescriptionKey: "The file is not a valid RTFD document."])
        }
        // Parsed here, handed to the main actor: nothing else holds it.
        nonisolated(unsafe) let text = parsed
        MainActor.assumeIsolated {
            contents = text
            if let tv = textView { tv.textStorage?.setAttributedString(text) }
        }
    }

    override func fileWrapper(ofType typeName: String) throws -> FileWrapper {
        guard typeName == TextDocument.rtfdType else { return try super.fileWrapper(ofType: typeName) }
        let text = textView?.textStorage.map { $0.copy() as! NSAttributedString } ?? contents
        guard let wrapper = text.rtfdFileWrapper(from: NSRange(location: 0, length: text.length), documentAttributes: [:]) else {
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileWriteUnknown.rawValue, userInfo: [NSLocalizedDescriptionKey: "The text could not be written as RTFD."])
        }
        return wrapper
    }

    /// A rich text document that gains an attachment becomes RTFD (RTF cannot hold one),
    /// as TextEdit converts it; the next save writes the .rtfd next to the .rtf.
    private func convertToRTFDIfNeeded() {
        guard fileType == TextDocument.rtfType, let st = textView?.textStorage, st.containsAttachments else { return }
        fileType = TextDocument.rtfdType
        if let url = fileURL { fileURL = url.deletingPathExtension().appendingPathExtension("rtfd") }
    }

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
        let text = textView?.textStorage.map { $0.copy() as! NSAttributedString } ?? contents
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
        TextDocument.configure(tv, rich: isRichText)
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
            MainActor.assumeIsolated {
                self?.convertToRTFDIfNeeded()
                self?.updateChangeCount(.changeDone)
            }
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
    /// The editor settings TextEdit uses: the find bar, spell checking while typing, and
    /// for rich text graphics (attachments by drag and drop or paste).
    static func configure(_ tv: NSTextView, rich: Bool) {
        tv.isRichText = rich
        tv.importsGraphics = rich
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isContinuousSpellCheckingEnabled = true
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = rich
        tv.isAutomaticDashSubstitutionEnabled = rich
    }

    func toggleRichText() {
        fileType = isRichText ? "public.plain-text" : TextDocument.rtfType
        if let tv = textView { TextDocument.configure(tv, rich: isRichText) }
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
        let matchStyle = edit.addItem(withTitle: "Paste and Match Style", action: Selector(("pasteAsPlainText:")), keyEquivalent: "v")
        matchStyle.keyEquivalentModifierMask = [.command, .option, .shift]
        edit.addItem(NSMenuItem.separator())
        edit.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")
        let complete = edit.addItem(withTitle: "Complete", action: Selector(("complete:")), keyEquivalent: "\u{1B}")
        complete.keyEquivalentModifierMask = [.option]
        edit.addItem(NSMenuItem.separator())
        edit.addItem(submenu("Find", AppDelegate.findItems()))
        edit.addItem(submenu("Spelling and Grammar", [
            item("Show Spelling and Grammar", "showGuessPanel:", ":"),
            item("Check Document Now", "checkSpelling:", ";"),
            .separator(),
            item("Check Spelling While Typing", "toggleContinuousSpellChecking:"),
            item("Check Grammar With Spelling", "toggleGrammarChecking:"),
            item("Correct Spelling Automatically", "toggleAutomaticSpellingCorrection:"),
        ]))
        edit.addItem(submenu("Substitutions", [
            item("Show Substitutions", "orderFrontSubstitutionsPanel:"),
            .separator(),
            item("Smart Copy/Paste", "toggleSmartInsertDelete:"),
            item("Smart Quotes", "toggleAutomaticQuoteSubstitution:"),
            item("Smart Dashes", "toggleAutomaticDashSubstitution:"),
            item("Text Replacement", "toggleAutomaticTextReplacement:"),
        ]))
        editItem.submenu = edit
        main.addItem(editItem)

        let formatItem = NSMenuItem(title: "Format", action: nil, keyEquivalent: "")
        let format = NSMenu(title: "Format")
        let rich = format.addItem(withTitle: "Make Rich Text", action: Selector(("toggleRichText:")), keyEquivalent: "t")
        rich.keyEquivalentModifierMask = [.command, .shift]
        format.addItem(NSMenuItem.separator())
        // Items naming a marker format (or a table size) act at once; the plain ones open
        // the text view's Lists and Table panels.
        func list(_ title: String, _ format: String) -> NSMenuItem {
            let i = item(title, "orderFrontListPanel:")
            i.representedObject = format
            return i
        }
        format.addItem(submenu("Lists", [
            list("Bulleted List", "{disc}"), list("Dashed List", "{hyphen}"), list("Numbered List", "{decimal}."),
            list("Lettered List", "{lower-alpha}."), list("Roman Numeral List", "{upper-roman}."),
            list("Remove List", ""), .separator(), item("Lists\u{2026}", "orderFrontListPanel:"),
        ]))
        let table3 = item("Insert 3 \u{00D7} 3 Table", "orderFrontTablePanel:")
        table3.representedObject = [3, 3]
        format.addItem(submenu("Table", [item("Table\u{2026}", "orderFrontTablePanel:"), table3]))
        formatItem.submenu = format
        main.addItem(formatItem)

        NSApp.mainMenu = main
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Edit > Find, by NSTextFinder action tag as AppKit's menu has them.
    static func findItems() -> [NSMenuItem] {
        let entries: [(String, String, NSEvent.ModifierFlags, NSTextFinder.Action)] = [
            ("Find\u{2026}", "f", [.command], .showFindInterface),
            ("Find and Replace\u{2026}", "f", [.command, .option], .showReplaceInterface),
            ("Find Next", "g", [.command], .nextMatch),
            ("Find Previous", "g", [.command, .shift], .previousMatch),
            ("Use Selection for Find", "e", [.command], .setSearchString),
        ]
        return entries.map { title, key, mods, action in
            let i = NSMenuItem(title: title, action: Selector(("performTextFinderAction:")), keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.tag = action.rawValue
            return i
        }
    }
}

@MainActor func item(_ title: String, _ action: String, _ key: String = "") -> NSMenuItem {
    NSMenuItem(title: title, action: Selector((action)), keyEquivalent: key)
}

@MainActor func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
    let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    let menu = NSMenu(title: title)
    for i in items { menu.addItem(i) }
    parent.submenu = menu
    return parent
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

/// The sample for `--roundtrip-rtfd` and `--sample-screenshot`: a heading, a numbered
/// list with a nested item, a 2×3 table and an image attachment.
@MainActor func sampleDocument() -> NSAttributedString {
    let font = NSFont.systemFont(ofSize: 13)
    let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 560, height: 400))
    TextDocument.configure(tv, rich: true)
    tv.font = font
    tv.typingAttributes = [.font: font, .foregroundColor: NSColor.textColor]
    tv.insertText("Text extras\n")
    tv.textStorage?.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 17), range: NSRange(location: 0, length: 11))
    tv.typingAttributes = [.font: font, .foregroundColor: NSColor.textColor]
    tv.insertText("Groceries")
    tv.orderFrontListPanel(listItem("{decimal}."))
    for (text, nest) in [("Apples", false), ("Pears", false), ("Conference pears", true)] {
        tv.insertNewline(nil)
        if nest { tv.insertTab(nil) }
        tv.insertText(text)
    }
    tv.insertNewline(nil)
    tv.insertBacktab(nil)
    tv.insertNewline(nil)
    tv.insertNewline(nil)
    tv.insertSampleTable()
    let image = NSImage(size: NSSize(width: 48, height: 32), flipped: false) { r in
        NSColor.systemBlue.setFill(); NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()
        NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: 16, y: 8, width: 16, height: 16)).fill()
        return true
    }
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let wrapper = FileWrapper(regularFileWithContents: rep.representation(using: .png, properties: [:])!)
    wrapper.preferredFilename = "badge.png"
    let attachment = NSTextAttachment(fileWrapper: wrapper)
    tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
    tv.insertText("An attachment: ")
    tv.insertText(NSAttributedString(attachment: attachment), replacementRange: NSRange(location: NSNotFound, length: 0))
    tv.insertText(" sits on the baseline, and a mispeled word is underlined.")
    // copy(): corelibs' init(attributedString:) does not read an NSTextStorage's backing.
    return tv.textStorage!.copy() as! NSAttributedString
}

@MainActor func listItem(_ format: String) -> NSMenuItem {
    let i = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    i.representedObject = format
    return i
}

extension NSTextView {
    /// A 2×3 table through the Format menu's path, its cells filled by Tab.
    @MainActor func insertSampleTable() {
        let insert = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        insert.representedObject = [2, 3]
        orderFrontTablePanel(insert)
        for (i, text) in ["Fruit", "Kind", "Price", "Apple", "Gala", "0.40"].enumerated() {
            if i > 0 { insertTab(nil) }
            insertText(text)
        }
        setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
    }
}

/// `--roundtrip-rtfd out.rtfd`: the sample written as RTFD through the document and read back.
@MainActor func roundTripRTFD(to path: String) -> Int32 {
    let dc = NSDocumentController.shared
    let url = URL(fileURLWithPath: path)
    do {
        let doc = try dc.makeUntitledDocument(ofType: TextDocument.rtfdType) as! TextDocument
        let text = sampleDocument()
        doc.contents = text
        try doc.write(to: url, ofType: TextDocument.rtfdType)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        print("wrote \(url.path): \(files.sorted())")
        let back = try dc.makeDocument(withContentsOf: url, ofType: TextDocument.rtfdType) as! TextDocument
        let s = back.contents
        guard s.string == text.string else { print("FAIL: text differs:\n\(s.string.debugDescription)\n\(text.string.debugDescription)"); return 1 }
        guard s.containsAttachments else { print("FAIL: attachment lost (written \(text.length) characters, attachment \(text.containsAttachments))"); return 1 }
        var lists = 0, cells = 0
        s.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: s.length), options: []) { v, _, _ in
            guard let p = v as? NSParagraphStyle else { return }
            if !p.textLists.isEmpty { lists += 1 }
            if p.textBlocks.first is NSTextTableBlock { cells += 1 }
        }
        guard lists > 0 else { print("FAIL: lists lost"); return 1 }
        guard cells >= 6 else { print("FAIL: table lost (\(cells) cell runs)"); return 1 }
        print("RTFD round trip OK: \(s.length) characters, list paragraphs, \(cells) table cells and the attachment kept")
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
if let i = arguments.firstIndex(of: "--roundtrip-rtfd"), i + 1 <= arguments.endIndex - 1 {
    exit(roundTripRTFD(to: arguments[i + 1]))
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
if let i = arguments.firstIndex(of: "--sample-screenshot"), i + 1 <= arguments.endIndex - 1 {
    // For the comparison page: the sample in a document window, rendered once laid out.
    let dir = arguments[i + 1]
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        MainActor.assumeIsolated {
            guard let doc = NSDocumentController.shared.currentDocument as? TextDocument,
                  let w = doc.windowControllers.first?.window,
                  let tv = w.initialFirstResponder as? NSTextView else { exit(1) }
            if doc.fileType != TextDocument.rtfdType { doc.fileType = TextDocument.rtfdType; TextDocument.configure(tv, rich: true) }
            tv.textStorage?.setAttributedString(sampleDocument())
            tv.setSelectedRange(NSRange(location: 0, length: 0))
            tv.checkTextInDocument(nil)
            w.display()
            writeScreenshot(of: w, named: "textedit-sample", to: dir)
            exit(0)
        }
    }
}
if arguments.contains("--show-save-panel") {
    // For screenshots: an untitled document with its save panel up (the package-drawn
    // panel under Xvfb without a portal, or with APPKITWIN_FILE_DIALOG=package).
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        NSDocumentController.shared.currentDocument?.saveAs(nil)
    }
}
app.run()

/// Renders a window's content over its background to <dir>/<name>-<platform>.png.
@MainActor func writeScreenshot(of w: NSWindow, named name: String, to dir: String) {
    #if os(Windows)
    let platform = "windows"
    #elseif os(Linux)
    let platform = "linux"
    #else
    let platform = "macos"
    #endif
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    guard let cv = w.contentView, let rep = cv.bitmapImageRepForCachingDisplay(in: cv.bounds) else { return }
    cv.cacheDisplay(in: cv.bounds, to: rep)
    let composed = NSImage(size: cv.bounds.size)
    composed.lockFocus()
    w.effectiveAppearance.performAsCurrentDrawingAppearance {
        w.backgroundColor.setFill()
        NSBezierPath.fill(NSRect(origin: .zero, size: cv.bounds.size))
    }
    if let cg = rep.cgImage { NSGraphicsContext.current?.cgContext.draw(cg, in: NSRect(origin: .zero, size: cv.bounds.size)) }
    composed.unlockFocus()
    guard let final = composed.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let png = NSBitmapImageRep(cgImage: final).representation(using: .png, properties: [:]) else { return }
    let path = (dir as NSString).appendingPathComponent("\(name)-\(platform).png")
    try? png.write(to: URL(fileURLWithPath: path))
    print("screenshot: \(path)")
    fflush(nil)
}
