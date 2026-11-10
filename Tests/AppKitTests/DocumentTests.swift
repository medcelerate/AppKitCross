// The document architecture on the host backend (ADR-0017): document types from an
// Info.plist dictionary, the untitled/open/save/revert/close lifecycle, the change count
// with the undo manager, window titles and the edited mark, the Open Recent menu, the
// responder chain to documents and the controller, the package-drawn open and save
// panels driven programmatically, the unsaved-changes alert, FileWrapper and UndoManager
// (Apple's on macOS, the port's on Linux and Windows) and the RTF round trip.

import XCTest
@testable import AppKit
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// A plain-text document with a window: the smallest NSDocument subclass an app writes.
@MainActor
final class TestDocument: NSDocument {
    var text = ""
    var readCount = 0
    var windowTitleSuffix = ""

    /// An undoable edit: the inverse is registered with the document's undo manager,
    /// and undoing it registers the redo, as model code does on macOS.
    func setText(_ new: String) {
        let old = text
        undoManager?.registerUndo(withTarget: self) { $0.setText(old) }
        text = new
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let s = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        MainActor.assumeIsolated { text = s; readCount += 1 }
    }
    override func data(ofType typeName: String) throws -> Data {
        guard let d = text.data(using: .utf8) else { throw CocoaError(.fileWriteInapplicableStringEncoding) }
        return d
    }
    override func makeWindowControllers() {
        let w = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 320, height: 200), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        let wc = SuffixWindowController(window: w)
        wc.suffix = windowTitleSuffix
        addWindowController(wc)
    }
}

/// A document edited through an NSTextView, as Examples/TextEdit does.
final class TextViewDocument: NSDocument {
    var textView: NSTextView?
    private var observer: NSObjectProtocol?
    override func makeWindowControllers() {
        let w = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 320, height: 200), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        let tv = NSTextView(frame: w.contentView!.bounds)
        w.contentView?.addSubview(tv)
        w.initialFirstResponder = tv
        textView = tv
        observer = NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: tv, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateChangeCount(.changeDone) }
        }
        addWindowController(NSWindowController(window: w))
    }
    override func close() {
        if let o = observer { NotificationCenter.default.removeObserver(o); observer = nil }
        super.close()
    }
}

@MainActor
final class SuffixWindowController: NSWindowController {
    var suffix = ""
    override func windowTitle(forDocumentDisplayName displayName: String) -> String { displayName + suffix }
}

@MainActor
private let testInfoPlist: [String: Any] = [
    "CFBundleName": "DocTest",
    "CFBundleExecutable": "AppKitTests",
    // Specific types before general ones, as Apple's guidance for CFBundleDocumentTypes says.
    "CFBundleDocumentTypes": [
        ["CFBundleTypeName": "Log", "CFBundleTypeRole": "Viewer", "LSItemContentTypes": ["public.log"],
         "CFBundleTypeExtensions": ["log"], "NSDocumentClass": "AppKitTests.TestDocument"],
        ["CFBundleTypeName": "Plain Text", "CFBundleTypeRole": "Editor", "LSItemContentTypes": ["public.plain-text"],
         "CFBundleTypeExtensions": ["txt", "text"], "NSDocumentClass": "AppKitTests.TestDocument"],
        ["CFBundleTypeName": "Notes", "CFBundleTypeRole": "Editor", "LSItemContentTypes": ["org.appkitcross.test.notes"],
         "CFBundleTypeExtensions": ["notes"], "NSDocumentClass": "AppKitTests.TestDocument"],
    ],
    "UTExportedTypeDeclarations": [
        ["UTTypeIdentifier": "org.appkitcross.test.notes", "UTTypeConformsTo": ["public.plain-text"], "UTTypeDescription": "Notes",
         "UTTypeTagSpecification": ["public.filename-extension": ["notes"]]],
    ],
]

/// A fresh shared controller reading `testInfoPlist`, with every window closed.
@MainActor
private func freshController() -> NSDocumentController {
    for w in NSApplication.shared.windows { w.close() }
    NSDocumentController._shared = nil
    NSDocumentController._infoDictionaryOverride = testInfoPlist
    let dc = NSDocumentController()
    dc.clearRecentDocuments(nil)
    return dc
}

@MainActor
private func tempDirectory(_ name: String) -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppKitDocumentTests-\(name)-\(getpid())")
    try? FileManager.default.removeItem(at: url)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
private func pump(_ seconds: TimeInterval = 0.05) {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
}

/// The buttons of every visible alert panel (not a file panel), by title.
@MainActor
private func visibleAlertButton(_ title: String) -> NSButton? {
    func find(_ v: NSView) -> NSButton? {
        if let b = v as? NSButton, b.title == title { return b }
        for s in v.subviews { if let b = find(s) { return b } }
        return nil
    }
    for w in NSApplication.shared.windows where w is NSPanel && !(w is NSSavePanel) && w.isVisible {
        if let cv = w.contentView, let b = find(cv) { return b }
    }
    return nil
}

@MainActor
private func sendKey(_ chars: String, code: UInt16, to window: NSWindow) {
    let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                             characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    NSApplication.shared.sendEvent(e)
}

final class DocumentTests: XCTestCase, @unchecked Sendable {
    override func tearDown() {
        MainActor.assumeIsolated {
            for w in NSApplication.shared.windows { w.close() }
            NSDocumentController._shared?.clearRecentDocuments(nil)
            NSDocumentController._shared = nil
            NSDocumentController._infoDictionaryOverride = nil
            (Platform.backend as? HostBackend)?.fileDialogOverride = nil
            NSApplication.shared.mainMenu = nil
        }
        super.tearDown()
    }

    // MARK: Types from Info.plist

    func testDocumentTypesComeFromTheInfoPlist() throws {
        try MainActor.assumeIsolated {
            let dc = freshController()
            XCTAssertTrue(NSDocumentController.shared === dc)
            XCTAssertEqual(dc.defaultType, "public.plain-text")
            XCTAssertEqual(dc.documentClassNames, ["AppKitTests.TestDocument"])
            XCTAssertTrue(dc.documentClass(forType: "public.plain-text") == TestDocument.self)
            XCTAssertNil(dc.documentClass(forType: "public.png"))
            XCTAssertEqual(dc.displayName(forType: "public.plain-text"), "Plain Text")
            let dir = tempDirectory("types")
            for name in ["a.txt", "b.notes", "c.log", "d.TEXT", "e.png"] { try! Data().write(to: dir.appendingPathComponent(name)) }
            XCTAssertEqual(try dc.typeForContents(of: dir.appendingPathComponent("a.txt")), "public.plain-text")
            XCTAssertEqual(try dc.typeForContents(of: dir.appendingPathComponent("d.TEXT")), "public.plain-text")
            XCTAssertEqual(try dc.typeForContents(of: dir.appendingPathComponent("b.notes")), "org.appkitcross.test.notes")
            XCTAssertEqual(try dc.typeForContents(of: dir.appendingPathComponent("c.log")), "public.log")
            XCTAssertThrowsError(try dc.typeForContents(of: dir.appendingPathComponent("e.png"))) { error in
                XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
            }
            // Editor types are writable, the Viewer type only readable.
            XCTAssertEqual(TestDocument.readableTypes, ["public.log", "public.plain-text", "org.appkitcross.test.notes"])
            XCTAssertEqual(TestDocument.writableTypes, ["public.plain-text", "org.appkitcross.test.notes"])
            XCTAssertTrue(TestDocument.isNativeType("public.plain-text"))
            XCTAssertFalse(TestDocument.isNativeType("public.log"))
            let viewer = try! dc.makeDocument(withContentsOf: dir.appendingPathComponent("c.log"), ofType: "public.log")
            // A save of a non-native type keeps that type among the writable ones.
            XCTAssertEqual(viewer.writableTypes(for: .saveOperation).last, "public.log")
            XCTAssertEqual(viewer.writableTypes(for: .saveAsOperation), TestDocument.writableTypes)
            XCTAssertEqual(viewer.fileNameExtension(forType: "org.appkitcross.test.notes", saveOperation: .saveAsOperation), "notes")
        }
    }

    // MARK: Lifecycle

    func testUntitledDocumentsGetWindowsTitlesAndEditedState() {
        MainActor.assumeIsolated {
            let dc = freshController()
            dc.newDocument(nil)
            dc.newDocument(nil)
            XCTAssertEqual(dc.documents.count, 2)
            let first = dc.documents[0] as! TestDocument, second = dc.documents[1] as! TestDocument
            XCTAssertEqual(first.displayName, "Untitled")
            XCTAssertEqual(second.displayName, "Untitled 2")
            XCTAssertEqual(first.windowControllers.count, 1)
            let window = first.windowControllers[0].window!
            XCTAssertTrue(window.isVisible)
            XCTAssertEqual(window.title, "Untitled")
            XCTAssertNil(window.representedURL)
            XCTAssertFalse(window.isDocumentEdited)
            XCTAssertTrue(window.windowController === first.windowControllers[0])
            XCTAssertTrue(window.windowController?.document === first)
            XCTAssertTrue(dc.document(for: window) === first)
            XCTAssertTrue(dc.currentDocument === second)      // the last shown window is key and main

            first.updateChangeCount(.changeDone)
            XCTAssertTrue(first.isDocumentEdited)
            XCTAssertTrue(window.isDocumentEdited)
            XCTAssertTrue(dc.hasEditedDocuments)
            // The package-drawn close button carries the dot.
            XCTAssertTrue(window._ensureWindowButtons(create: true)!.close.isDocumentEdited)
            first.updateChangeCount(.changeUndone)
            XCTAssertFalse(first.isDocumentEdited)
            XCTAssertFalse(window.isDocumentEdited)
            first.updateChangeCount(.changeDone)
            first.updateChangeCount(.changeDone)
            first.updateChangeCount(.changeCleared)
            XCTAssertFalse(first.isDocumentEdited)

            // Closing the window closes the document; the controller forgets it.
            window.performClose(nil)
            XCTAssertFalse(window.isVisible)
            XCTAssertEqual(dc.documents.count, 1)
            XCTAssertTrue(dc.documents[0] === second)
            XCTAssertTrue(first.windowControllers.isEmpty)
            second.close()
            XCTAssertTrue(dc.documents.isEmpty)
        }
    }

    func testUndoManagerDrivesTheChangeCount() {
        MainActor.assumeIsolated {
            let dc = freshController()
            let doc = try! dc.makeUntitledDocument(ofType: "public.plain-text") as! TestDocument
            XCTAssertTrue(doc.hasUndoManager)
            let undo = doc.undoManager!
            XCTAssertTrue(doc.undoManager === undo)
            doc.setText("one")
            XCTAssertFalse(doc.isDocumentEdited)         // the event group is still open
            pump()                                        // the run loop closes it
            XCTAssertTrue(doc.isDocumentEdited)
            XCTAssertTrue(undo.canUndo)
            undo.undo()
            XCTAssertEqual(doc.text, "")
            XCTAssertFalse(doc.isDocumentEdited)
            XCTAssertTrue(undo.canRedo)
            undo.redo()
            XCTAssertEqual(doc.text, "one")
            XCTAssertTrue(doc.isDocumentEdited)
            doc.hasUndoManager = false
            XCTAssertNil(doc.undoManager)
            doc.close()
        }
    }

    func testSaveRevertAndReopenRoundTrip() throws {
        try MainActor.assumeIsolated {
            let dc = freshController()
            let dir = tempDirectory("roundtrip")
            dc.newDocument(nil)
            let doc = dc.documents[0] as! TestDocument
            let window = doc.windowControllers[0].window!
            doc.text = "hello"
            doc.updateChangeCount(.changeDone)
            let url = dir.appendingPathComponent("note.txt")
            var saveError: (any Error)? = nil
            var completed = false
            doc.save(to: url, ofType: "public.plain-text", for: .saveAsOperation) { saveError = $0; completed = true }
            XCTAssertTrue(completed)
            XCTAssertNil(saveError)
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "hello")
            XCTAssertEqual(doc.fileURL, url)
            XCTAssertEqual(doc.fileType, "public.plain-text")
            XCTAssertFalse(doc.isDocumentEdited)
            XCTAssertNotNil(doc.fileModificationDate)
            XCTAssertEqual(doc.displayName, "note.txt")
            XCTAssertEqual(window.title, "note.txt")
            XCTAssertEqual(window.representedURL, url)
            XCTAssertEqual(window.representedFilename, url.path)
            XCTAssertFalse(window.isDocumentEdited)
            XCTAssertEqual(dc.recentDocumentURLs.first?.lastPathComponent, "note.txt")
            XCTAssertTrue(dc.document(for: url) === doc)

            // Save in place through the responder chain (the key window's chain ends at the document).
            doc.text = "hello again"
            doc.updateChangeCount(.changeDone)
            XCTAssertTrue(window.isDocumentEdited)
            window.makeKeyAndOrderFront(nil)
            XCTAssertTrue(NSApplication.shared.sendAction(Selector(("saveDocument:")), to: nil, from: nil))
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "hello again")
            XCTAssertFalse(doc.isDocumentEdited)

            // A save-to writes elsewhere and leaves the document on its file.
            let copy = dir.appendingPathComponent("copy.txt")
            doc.save(to: copy, ofType: "public.plain-text", for: .saveToOperation) { XCTAssertNil($0) }
            XCTAssertEqual(doc.fileURL, url)
            XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))

            // Revert reads the file back and clears the change count.
            doc.text = "scratch"
            doc.updateChangeCount(.changeDone)
            try! doc.revert(toContentsOf: url, ofType: "public.plain-text")
            XCTAssertEqual(doc.text, "hello again")
            XCTAssertFalse(doc.isDocumentEdited)

            // Reopening the same file answers with the open document; after closing, a new one.
            var reopened: NSDocument? = nil, wasOpen = false
            dc.openDocument(withContentsOf: url, display: true) { d, open, error in reopened = d; wasOpen = open; XCTAssertNil(error) }
            XCTAssertTrue(reopened === doc)
            XCTAssertTrue(wasOpen)
            doc.close()
            XCTAssertTrue(dc.documents.isEmpty)
            dc.openDocument(withContentsOf: url, display: true) { d, open, error in reopened = d; wasOpen = open; XCTAssertNil(error) }
            XCTAssertFalse(wasOpen)
            let fresh = reopened as! TestDocument
            XCTAssertEqual(fresh.text, "hello again")
            XCTAssertEqual(fresh.windowControllers.first?.window?.title, "note.txt")
            XCTAssertFalse(fresh.isDocumentEdited)
            // An unknown type reports an error rather than a document.
            let png = dir.appendingPathComponent("x.png")
            try! Data([1]).write(to: png)
            var failure: (any Error)? = nil
            dc.openDocument(withContentsOf: png, display: false) { d, _, e in XCTAssertNil(d); failure = e }
            XCTAssertNotNil(failure)
            fresh.close()
        }
    }

    func testWindowTitleHookAndRepresentedFilename() {
        MainActor.assumeIsolated {
            let dc = freshController()
            let doc = try! dc.makeUntitledDocument(ofType: "public.plain-text") as! TestDocument
            doc.windowTitleSuffix = " — Edited in Test"
            dc.addDocument(doc)
            doc.makeWindowControllers()
            doc.showWindows()
            let window = doc.windowControllers[0].window!
            XCTAssertEqual(window.title, "Untitled — Edited in Test")
            doc.fileURL = URL(fileURLWithPath: "/tmp/x/report.txt")
            XCTAssertEqual(window.title, "report.txt — Edited in Test")
            XCTAssertEqual(window.representedFilename, "/tmp/x/report.txt")
            let plain = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            plain.setTitleWithRepresentedFilename("/var/data/sheet.csv")
            XCTAssertEqual(plain.title, "sheet.csv")
            XCTAssertEqual(plain.representedURL?.path, "/var/data/sheet.csv")
            plain.close()
            doc.close()
        }
    }

    // MARK: Menus and the responder chain

    func testOpenRecentMenuAndMenuValidation() {
        MainActor.assumeIsolated {
            let dc = freshController()
            let main = NSMenu(title: "Main")
            let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
            let file = NSMenu(title: "File")
            let newItem = file.addItem(withTitle: "New", action: Selector(("newDocument:")), keyEquivalent: "n")
            let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
            let recent = NSMenu(title: "Open Recent")
            recentItem.submenu = recent
            file.addItem(recentItem)
            let revert = file.addItem(withTitle: "Revert to Saved", action: Selector(("revertDocumentToSaved:")), keyEquivalent: "")
            let save = file.addItem(withTitle: "Save", action: Selector(("saveDocument:")), keyEquivalent: "s")
            fileItem.submenu = file
            main.addItem(fileItem)
            NSApplication.shared.mainMenu = main
            // Installed: Clear Menu alone.
            XCTAssertEqual(recent.items.map { $0.title }, ["Clear Menu"])
            let dir = tempDirectory("recent")
            let a = dir.appendingPathComponent("a.txt"), b = dir.appendingPathComponent("b.txt")
            try! "A".write(to: a, atomically: true, encoding: .utf8)
            try! "B".write(to: b, atomically: true, encoding: .utf8)
            dc.noteNewRecentDocumentURL(a)
            dc.noteNewRecentDocumentURL(b)
            dc.noteNewRecentDocumentURL(a)       // moves to the front, no duplicate
            XCTAssertEqual(dc.recentDocumentURLs.map { $0.lastPathComponent }, ["a.txt", "b.txt"])
            XCTAssertEqual(recent.items.map { $0.title }, ["a.txt", "b.txt", "", "Clear Menu"])
            XCTAssertLessThanOrEqual(dc.recentDocumentURLs.count, dc.maximumRecentDocumentCount)
            // Choosing a recent item opens it.
            let item = recent.items[1]
            XCTAssertTrue(NSApplication.shared.sendAction(item.action!, to: item.target, from: item))
            XCTAssertEqual(dc.documents.count, 1)
            XCTAssertEqual((dc.documents[0] as! TestDocument).text, "B")
            // Validation: Revert needs a file and changes; Save is on; New reaches the controller.
            let window = dc.documents[0].windowControllers[0].window!
            window.makeKeyAndOrderFront(nil)
            file.update()
            XCTAssertTrue(newItem.isEnabled)
            XCTAssertFalse(revert.isEnabled)
            XCTAssertFalse(save.isEnabled)
            dc.documents[0].updateChangeCount(.changeDone)
            file.update()
            XCTAssertTrue(revert.isEnabled)
            XCTAssertTrue(save.isEnabled)
            XCTAssertTrue(NSApplication.shared.sendAction(Selector(("newDocument:")), to: nil, from: nil))
            XCTAssertEqual(dc.documents.count, 2)
            dc.clearRecentDocuments(nil)
            XCTAssertEqual(recent.items.map { $0.title }, ["Clear Menu"])
            XCTAssertTrue(dc.recentDocumentURLs.isEmpty)
            for d in dc.documents { d.updateChangeCount(.changeCleared); d.close() }
        }
    }

    // MARK: Unsaved changes on close

    func testClosingAnEditedWindowAsksAndHonoursEachAnswer() throws {
        try MainActor.assumeIsolated {
            let dc = freshController()
            let dir = tempDirectory("close")
            dc.newDocument(nil)
            let doc = dc.documents[0] as! TestDocument
            let window = doc.windowControllers[0].window!
            doc.text = "draft"
            doc.updateChangeCount(.changeDone)

            // Cancel keeps the window and the document.
            window.performClose(nil)
            XCTAssertNotNil(visibleAlertButton("Don\u{2019}t Save"))
            visibleAlertButton("Cancel")!.performClick(nil)
            XCTAssertTrue(window.isVisible)
            XCTAssertEqual(dc.documents.count, 1)
            XCTAssertNil(visibleAlertButton("Cancel"))

            // Save runs the save panel as a sheet; confirming it writes and closes.
            window.performClose(nil)
            visibleAlertButton("Save")!.performClick(nil)
            let panel = window.attachedSheet as? NSSavePanel
            XCTAssertNotNil(panel)
            panel!.directoryURL = dir
            panel!.nameFieldStringValue = "draft"
            // Apple's UTType knows nothing of the test's declared type; the port's registry does.
            XCTAssertEqual(panel!.allowedContentTypes.first?.identifier, "public.plain-text")
            #if !canImport(Darwin)
            XCTAssertEqual(panel!.allowedContentTypes.map { $0.identifier }, ["public.plain-text", "org.appkitcross.test.notes"])
            #endif
            panel!.ok(nil)
            XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("draft.txt"), encoding: .utf8), "draft")
            XCTAssertFalse(window.isVisible)
            XCTAssertTrue(dc.documents.isEmpty)

            // Don't Save closes without writing.
            dc.newDocument(nil)
            let second = dc.documents[0] as! TestDocument
            let w2 = second.windowControllers[0].window!
            second.updateChangeCount(.changeDone)
            w2.performClose(nil)
            visibleAlertButton("Don\u{2019}t Save")!.performClick(nil)
            XCTAssertFalse(w2.isVisible)
            XCTAssertTrue(dc.documents.isEmpty)

            // The platform's own close button takes the same path (the document decides).
            dc.newDocument(nil)
            let third = dc.documents[0]
            third.updateChangeCount(.changeDone)
            let w3 = third.windowControllers[0].window!
            XCTAssertFalse(w3.platformWindowShouldClose())
            visibleAlertButton("Don\u{2019}t Save")!.performClick(nil)
            XCTAssertFalse(w3.isVisible)
            XCTAssertTrue(dc.documents.isEmpty)
        }
    }

    func testReviewUnsavedDocumentsBeforeQuitting() {
        MainActor.assumeIsolated {
            let dc = freshController()
            dc.newDocument(nil)
            dc.newDocument(nil)
            for d in dc.documents { d.updateChangeCount(.changeDone) }
            var answer: Bool? = nil
            // Two edited documents: the summary alert runs modally; Discard Changes answers yes.
            Platform.backend.post { visibleAlertButton("Discard Changes")!.performClick(nil) }
            dc._reviewUnsavedDocuments(title: "Quit", cancellable: true) { answer = $0 }
            XCTAssertEqual(answer, true)
            // Cancel answers no, and nothing was closed.
            answer = nil
            Platform.backend.post { visibleAlertButton("Cancel")!.performClick(nil) }
            dc._reviewUnsavedDocuments(title: "Quit", cancellable: true) { answer = $0 }
            XCTAssertEqual(answer, false)
            XCTAssertEqual(dc.documents.count, 2)
            // Review Changes asks each document in turn.
            answer = nil
            Platform.backend.post { visibleAlertButton("Review Changes\u{2026}")!.performClick(nil) }
            dc._reviewUnsavedDocuments(title: "Quit", cancellable: true) { answer = $0 }
            XCTAssertNil(answer)                          // the first document's sheet is up
            visibleAlertButton("Don\u{2019}t Save")!.performClick(nil)
            XCTAssertNil(answer)                          // then the second's
            visibleAlertButton("Don\u{2019}t Save")!.performClick(nil)
            XCTAssertEqual(answer, true)
            for d in dc.documents { d.updateChangeCount(.changeCleared); d.close() }
        }
    }

    /// The PC scenario: two documents made as File > New does, each edited by typing into
    /// its own window's text view (the second window must have become key with its text
    /// view as first responder), then Quit: the two-document review alert, not one
    /// document's Save / Cancel / Don't Save.
    func testQuitWithTwoDocumentsEditedThroughTheirTextViews() {
        MainActor.assumeIsolated {
            _ = freshController()
            var plist = testInfoPlist
            plist["CFBundleDocumentTypes"] = [["CFBundleTypeName": "Plain Text", "CFBundleTypeRole": "Editor", "LSItemContentTypes": ["public.plain-text"],
                                              "CFBundleTypeExtensions": ["txt"], "NSDocumentClass": "AppKitTests.TextViewDocument"]]
            NSDocumentController._shared = nil
            NSDocumentController._infoDictionaryOverride = plist
            let dc = NSDocumentController()
            let app = NSApplication.shared
            var docs: [TextViewDocument] = []
            for _ in 0..<2 {
                XCTAssertTrue(app.sendAction(Selector(("newDocument:")), to: nil, from: nil))
                guard let d = dc.documents.last as? TextViewDocument else { XCTFail("no TextViewDocument"); return }
                docs.append(d)
                let window = d.windowControllers[0].window!
                XCTAssertTrue(app.keyWindow === window, "the new document's window is key")
                XCTAssertTrue(window.firstResponder === d.textView, "its text view is first responder")
                sendKey("a", code: 0, to: window)
                XCTAssertEqual(d.textView?.string, "a")
                XCTAssertTrue(d.isDocumentEdited)
                XCTAssertTrue(window.isDocumentEdited)
            }
            XCTAssertEqual(docs[0].displayName, "Untitled")
            XCTAssertEqual(docs[1].displayName, "Untitled 2")
            XCTAssertEqual(dc.documents.filter { $0.isDocumentEdited }.count, 2)
            // Quit through the menu's action: the review alert is up; Cancel keeps running.
            var sawReview = false
            Platform.backend.post {
                sawReview = visibleAlertButton("Discard Changes") != nil && visibleAlertButton("Review Changes\u{2026}") != nil
                visibleAlertButton("Cancel")!.performClick(nil)
            }
            XCTAssertTrue(app.sendAction(Selector(("terminate:")), to: nil, from: nil))
            XCTAssertTrue(sawReview, "the two-document alert, not a single document's prompt")
            XCTAssertEqual(dc.documents.count, 2)
            for d in dc.documents { d.updateChangeCount(.changeCleared); d.close() }
        }
    }

    // MARK: The package-drawn panels

    func testSavePanelDrivenProgrammatically() {
        MainActor.assumeIsolated {
            let dir = tempDirectory("savepanel")
            let panel = NSSavePanel()
            panel.directoryURL = dir
            panel.allowedContentTypes = [.plainText]
            panel.message = "Save your notes"
            var response: NSApplication.ModalResponse? = nil
            panel.begin { response = $0 }
            XCTAssertTrue(panel.isVisible)
            XCTAssertEqual(panel.title, "Save")
            let controller = panel._controller!
            XCTAssertTrue(controller.built)
            XCTAssertEqual(controller.directory.path, dir.path)
            XCTAssertFalse(controller.typePopUp.isHidden)
            XCTAssertEqual(controller.okButton.title, "Save")
            // The extension of the chosen type is added to a bare name.
            panel.nameFieldStringValue = "notes"
            panel.ok(nil)
            XCTAssertEqual(response, .OK)
            XCTAssertEqual(panel.url?.path, dir.appendingPathComponent("notes.txt").path)
            XCTAssertFalse(panel.isVisible)
            XCTAssertEqual(panel.directoryURL?.path, dir.path)

            // runModal: the OK arrives from a posted block; Escape cancels the next run.
            let modal = NSSavePanel()
            modal.directoryURL = dir
            modal.nameFieldStringValue = "modal.txt"
            Platform.backend.post { modal.ok(nil) }
            XCTAssertEqual(modal.runModal(), .OK)
            XCTAssertEqual(modal.url?.lastPathComponent, "modal.txt")
            Platform.backend.post { sendKey("\u{1b}", code: 53, to: modal) }
            XCTAssertEqual(modal.runModal(), .cancel)
            XCTAssertNil(modal.url)

            // Replacing an existing file asks first; Replace goes ahead.
            try! "old".write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
            let again = NSSavePanel()
            again.directoryURL = dir
            again.nameFieldStringValue = "notes.txt"
            Platform.backend.post {
                XCTAssertNotNil(visibleAlertButton("Replace"))
                visibleAlertButton("Replace")!.performClick(nil)
            }
            var sheetResponse: NSApplication.ModalResponse? = nil
            let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
            parent.makeKeyAndOrderFront(nil)
            again.beginSheetModal(for: parent) { sheetResponse = $0 }
            XCTAssertTrue(parent.attachedSheet === again)
            again.ok(nil)        // the posted block answers the Replace alert while it runs modally
            XCTAssertEqual(sheetResponse, .OK)
            XCTAssertNil(parent.attachedSheet)

            // New Folder creates and enters the folder; the delegate can veto names.
            final class Delegate: NSObject, NSOpenSavePanelDelegate {
                var directories: [URL] = []
                func panel(_ sender: Any, userEnteredFilename filename: String, confirmed okFlag: Bool) -> String? { filename == "forbidden" ? nil : filename }
                func panel(_ sender: Any, didChangeToDirectoryURL url: URL?) { if let url { directories.append(url) } }
                func panel(_ sender: Any, validate url: URL) throws {
                    if url.lastPathComponent.hasPrefix("bad") { throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bad name"]) }
                }
            }
            let delegate = Delegate()
            let folders = NSSavePanel()
            folders.delegate = delegate
            folders.directoryURL = dir
            var folderResponse: NSApplication.ModalResponse? = nil
            folders.begin { folderResponse = $0 }
            folders._controller!.createFolder(named: "Sub")
            XCTAssertEqual(folders.directoryURL?.lastPathComponent, "Sub")
            XCTAssertEqual(delegate.directories.last?.lastPathComponent, "Sub")
            folders._controller!.goUp()
            XCTAssertEqual(folders.directoryURL?.path, dir.path)
            folders.nameFieldStringValue = "forbidden"
            folders.ok(nil)
            XCTAssertNil(folderResponse)
            folders.nameFieldStringValue = "bad.txt"
            Platform.backend.post { visibleAlertButton("OK")?.performClick(nil) }
            folders.ok(nil)
            XCTAssertNil(folderResponse)
            folders.nameFieldStringValue = "good.txt"
            folders.ok(nil)
            XCTAssertEqual(folderResponse, .OK)
            XCTAssertEqual(folders.url?.lastPathComponent, "good.txt")
            parent.close()
        }
    }

    func testOpenPanelFiltersSelectsAndNavigates() {
        MainActor.assumeIsolated {
            let dir = tempDirectory("openpanel")
            for name in ["alpha.txt", "beta.png", "gamma.txt"] { try! Data([0]).write(to: dir.appendingPathComponent(name)) }
            try! FileManager.default.createDirectory(at: dir.appendingPathComponent("Folder"), withIntermediateDirectories: true)
            try! Data([0]).write(to: dir.appendingPathComponent("Folder/inner.txt"))
            final class Delegate: NSObject, NSOpenSavePanelDelegate {
                var selections = 0
                func panel(_ sender: Any, shouldEnable url: URL) -> Bool { url.lastPathComponent != "gamma.txt" }
                func panelSelectionDidChange(_ sender: Any?) { selections += 1 }
            }
            let delegate = Delegate()
            let panel = NSOpenPanel()
            panel.delegate = delegate
            panel.directoryURL = dir
            panel.allowedContentTypes = [.plainText]
            panel.allowsMultipleSelection = true
            var response: NSApplication.ModalResponse? = nil
            panel.begin { response = $0 }
            let c = panel._controller!
            // Sorted by name, case-insensitively, folders among files (as the Finder lists).
            XCTAssertEqual(c.entries.map { $0.name }, ["alpha.txt", "beta.png", "Folder", "gamma.txt"])
            XCTAssertEqual(c.entries.map { $0.isEnabled }, [true, false, true, false])    // type filter, delegate
            XCTAssertTrue(panel.firstResponder === c.table)
            // Keyboard: down selects the first row; a disabled row refuses selection.
            sendKey("\u{F701}", code: 125, to: panel)
            XCTAssertEqual(c.table.selectedRow, 0)
            XCTAssertGreaterThan(delegate.selections, 0)
            XCTAssertFalse(c.table.delegate!.tableView(c.table, shouldSelectRow: 1))
            // Return on a folder enters it; Up comes back with the folder selected.
            c.table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
            sendKey("\r", code: 36, to: panel)
            XCTAssertEqual(panel.directoryURL?.lastPathComponent, "Folder")
            XCTAssertEqual(c.entries.map { $0.name }, ["inner.txt"])
            c.goUp()
            XCTAssertEqual(c.table.selectedRow, 2)
            // Typing a path in the Where field navigates.
            c.pathField.stringValue = dir.appendingPathComponent("Folder").path
            c.pathField.performClick(nil)
            XCTAssertEqual(panel.directoryURL?.lastPathComponent, "Folder")
            c.goUp()
            // OK with an enabled text file selected answers its URL (a disabled one cannot join).
            c.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            c.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: true)
            XCTAssertFalse(c.table.isRowSelected(1))
            panel.ok(nil)
            XCTAssertEqual(response, .OK)
            XCTAssertEqual(panel.urls.map { $0.lastPathComponent }, ["alpha.txt"])
            XCTAssertEqual(panel.url?.lastPathComponent, "alpha.txt")

            // Directories only: OK with nothing selected is the directory itself.
            let folders = NSOpenPanel()
            folders.canChooseFiles = false
            folders.canChooseDirectories = true
            folders.directoryURL = dir
            var folderResponse: NSApplication.ModalResponse? = nil
            folders.begin { folderResponse = $0 }
            XCTAssertEqual(folders._controller!.entries.map { $0.isEnabled }, [false, false, true, false])
            folders.ok(nil)
            XCTAssertEqual(folderResponse, .OK)
            XCTAssertEqual(folders.url?.path, dir.path)
            // Cancel answers no URLs.
            let cancelled = NSOpenPanel()
            cancelled.directoryURL = dir
            var cancelResponse: NSApplication.ModalResponse? = nil
            cancelled.begin { cancelResponse = $0 }
            cancelled.cancel(nil)
            XCTAssertEqual(cancelResponse, .cancel)
            XCTAssertTrue(cancelled.urls.isEmpty)
            XCTAssertFalse(cancelled.isVisible)
        }
    }

    func testNativeDialogIsUsedWhenTheBackendOffersOne() {
        MainActor.assumeIsolated {
            let host = Platform.backend as! HostBackend
            let native = HostFileDialog(result: [URL(fileURLWithPath: "/tmp/native.txt")])
            host.fileDialogOverride = native
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = "x.txt"
            var response: NSApplication.ModalResponse? = nil
            panel.begin { response = $0 }
            XCTAssertEqual(response, .OK)
            XCTAssertEqual(native.runCount, 1)
            XCTAssertNil(panel._controller)                 // nothing drawn
            XCTAssertEqual(native.lastOptions?.allowedExtensions, ["txt", "text"])
            XCTAssertEqual(native.lastOptions?.allowedTypeDescriptions.first, UTType.plainText.localizedDescription)
            XCTAssertEqual(panel.url?.lastPathComponent, "native.txt")
            host.fileDialogOverride = nil
        }
    }

    // MARK: Foundation shims (Apple's on macOS, the port's elsewhere)

    func testFileWrapperDirectoryRoundTrip() throws {
        try MainActor.assumeIsolated {
            let dir = tempDirectory("wrapper")
            let a = FileWrapper(regularFileWithContents: Data("A".utf8))
            a.preferredFilename = "a.txt"
            let package = FileWrapper(directoryWithFileWrappers: ["a.txt": a])
            let b = package.addRegularFile(withContents: Data("B".utf8), preferredFilename: "b.txt")
            XCTAssertEqual(b, "b.txt")
            XCTAssertTrue(package.isDirectory)
            XCTAssertEqual(package.fileWrappers?.keys.sorted(), ["a.txt", "b.txt"])
            let url = dir.appendingPathComponent("Pack.bundle")
            try! package.write(to: url, options: .atomic, originalContentsURL: nil)
            XCTAssertEqual(try String(contentsOf: url.appendingPathComponent("b.txt"), encoding: .utf8), "B")
            let back = try! FileWrapper(url: url, options: .immediate)
            XCTAssertTrue(back.isDirectory)
            XCTAssertEqual(back.fileWrappers?["a.txt"]?.regularFileContents, Data("A".utf8))
            XCTAssertTrue(back.matchesContents(of: url))
            package.removeFileWrapper(a)
            XCTAssertEqual(package.fileWrappers?.keys.sorted(), ["b.txt"])
            let file = try! FileWrapper(url: url.appendingPathComponent("b.txt"))
            XCTAssertTrue(file.isRegularFile)
            XCTAssertEqual(file.filename, "b.txt")
        }
    }

    func testUndoManagerGroupsAndNames() {
        MainActor.assumeIsolated {
            final class Counter: @unchecked Sendable {
                var value = 0
                weak var undo: UndoManager?
                func set(_ v: Int) {
                    let old = value
                    undo?.registerUndo(withTarget: self) { $0.set(old) }
                    value = v
                }
            }
            let counter = Counter()
            let undo = UndoManager()
            counter.undo = undo
            undo.groupsByEvent = false
            XCTAssertFalse(undo.canUndo)
            undo.beginUndoGrouping()
            counter.set(1)
            undo.setActionName("Increment")
            undo.endUndoGrouping()
            XCTAssertTrue(undo.canUndo)
            XCTAssertEqual(undo.undoActionName, "Increment")
            XCTAssertEqual(undo.undoMenuItemTitle, "Undo Increment")
            let didUndo = Counter()
            let o = NotificationCenter.default.addObserver(forName: .NSUndoManagerDidUndoChange, object: undo, queue: nil) { _ in didUndo.value += 1 }
            undo.undo()
            XCTAssertEqual(counter.value, 0)
            XCTAssertEqual(didUndo.value, 1)
            XCTAssertTrue(undo.canRedo)
            undo.redo()
            XCTAssertEqual(counter.value, 1)
            undo.removeAllActions()
            XCTAssertFalse(undo.canUndo)
            NotificationCenter.default.removeObserver(o)
            // Grouping by event: registrations in one run-loop cycle form one group.
            let byEvent = UndoManager()
            counter.undo = byEvent
            counter.set(10)
            counter.set(20)
            pump()
            XCTAssertEqual(byEvent.groupingLevel, 0)
            byEvent.undo()
            XCTAssertEqual(counter.value, 1)         // both edits undone as one group
            XCTAssertFalse(byEvent.canUndo)
            XCTAssertTrue(byEvent.canRedo)
        }
    }

    // MARK: RTF

    func testRTFRoundTripKeepsFontColourUnderlineAndAlignment() {
        MainActor.assumeIsolated {
            let text = NSMutableAttributedString(string: "Bold red\nCentred & \u{201C}quoted\u{201D} caf\u{E9} \u{1F600}\n", attributes: [.font: NSFont.systemFont(ofSize: 12)])
            text.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 12), range: NSRange(location: 0, length: 4))
            text.addAttribute(.foregroundColor, value: NSColor(red: 1, green: 0, blue: 0, alpha: 1), range: NSRange(location: 5, length: 3))
            text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 5, length: 3))
            let centred = NSMutableParagraphStyle()
            centred.alignment = .center
            text.addAttribute(.paragraphStyle, value: centred, range: NSRange(location: 9, length: text.length - 9))
            let data = _RTFWriter(attributedString: text, range: NSRange(location: 0, length: text.length)).write()!
            let source = String(decoding: data, as: UTF8.self)
            XCTAssertTrue(source.hasPrefix("{\\rtf1\\ansi"))
            XCTAssertTrue(source.contains("\\qc"))
            XCTAssertTrue(source.contains("\\red255\\green0\\blue0"))
            let back = _RTFReader(data: data).read()!
            XCTAssertEqual(back.string, text.string)
            let bold = back.attribute(.font, at: 1, effectiveRange: nil) as? NSFont
            XCTAssertTrue(NSFontManager.shared.traits(of: bold!).contains(.boldFontMask))
            let regular = back.attribute(.font, at: 6, effectiveRange: nil) as? NSFont
            XCTAssertFalse(NSFontManager.shared.traits(of: regular!).contains(.boldFontMask))
            XCTAssertEqual((back.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor)?.redComponent, 1)
            XCTAssertEqual((back.attribute(.underlineStyle, at: 6, effectiveRange: nil) as? Int) ?? (back.attribute(.underlineStyle, at: 6, effectiveRange: nil) as? NSNumber)?.intValue, 1)
            XCTAssertEqual((back.attribute(.paragraphStyle, at: 12, effectiveRange: nil) as? NSParagraphStyle)?.alignment, .center)
            #if !canImport(Darwin)
            // The public API (Apple's own on macOS): data(from:) defaults to plain text,
            // init(data:) detects RTF.
            let plain = try! text.data(from: NSRange(location: 0, length: text.length))
            XCTAssertEqual(String(decoding: plain, as: UTF8.self), text.string)
            let detected = try! NSAttributedString(data: data, options: [:], documentAttributes: nil)
            XCTAssertEqual(detected.string, text.string)
            XCTAssertEqual(NSAttributedString(rtf: data, documentAttributes: nil)?.string, text.string)
            XCTAssertEqual(text.rtf(from: NSRange(location: 0, length: text.length)), data)
            #endif
            // Other editors' RTF: Word-style escapes, a skipped destination, a line break.
            let foreign = "{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0\\fswiss Arial;}}{\\*\\generator Riched20;}\\viewkind4\\uc1\\pard\\f0\\fs20 Caf\\'e9 \\u8212?x\\line next\\par}"
            let parsed = _RTFReader(data: Data(foreign.utf8)).read()!
            XCTAssertEqual(parsed.string, "Caf\u{E9} \u{2014}x\nnext\n")
            XCTAssertEqual((parsed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize, 10)
        }
    }
}
