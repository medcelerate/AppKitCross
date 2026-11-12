import AppKit

// The Layout Demo's Browser tab (ADR-0032): an NSBrowser over a small file-system-like
// tree (item-based delegate), a radio NSMatrix choosing the column resizing, and an NSForm
// whose "Go to" entry sets the browser's path on Return.

/// A folder (with children) or a file in the demo tree.
final class DemoFile: NSObject {
    let name: String
    let children: [DemoFile]?
    init(_ name: String, _ children: [DemoFile]? = nil) { self.name = name; self.children = children }
}

final class BrowserDemoViewController: NSViewController, NSBrowserDelegate, NSSelectorHandling {
    let root = DemoFile("/", [
        DemoFile("Applications", [DemoFile("Calculator.app"), DemoFile("TextEdit.app"), DemoFile("Workspace.app")]),
        DemoFile("Library", [
            DemoFile("Fonts", [DemoFile("Inter.ttf"), DemoFile("Menlo.ttc"), DemoFile("Segoe UI.ttf")]),
            DemoFile("Preferences", [DemoFile("com.example.demo.plist")]),
        ]),
        DemoFile("System", [DemoFile("Library", [DemoFile("Frameworks", [DemoFile("AppKit.framework"), DemoFile("Foundation.framework"), DemoFile("SwiftUI.framework")])])]),
        DemoFile("Users", [DemoFile("guest", [
            DemoFile("Desktop", []),
            DemoFile("Documents", [DemoFile("Notes.txt"), DemoFile("Report.rtf"), DemoFile("Budget.numbers")]),
            DemoFile("Downloads", [DemoFile("archive.zip")]),
        ])]),
        DemoFile("readme.txt"),
    ])
    let browser = NSBrowser(frame: NSRect(x: 12, y: 84, width: 576, height: 168))
    let resizing = NSMatrix(frame: NSRect(x: 12, y: 8, width: 176, height: 64), mode: .radioModeMatrix,
                            prototype: { let c = NSButtonCell(textCell: ""); c.setButtonType(.radio); return c }(),
                            numberOfRows: 3, numberOfColumns: 1)
    let form = NSForm(frame: NSRect(x: 200, y: 30, width: 388, height: 52))
    let status = NSTextField(labelWithString: "Click a folder, or use the arrow keys.")

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Browser"
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 260))
        browser.target = self
        browser.action = Selector(("browserClicked:"))
        browser.doubleAction = Selector(("browserDoubleClicked:"))
        browser.autoresizingMask = [.width, .height]
        content.addSubview(browser)

        for (i, title) in ["Columns fill the browser", "Drag column edges", "Fixed column widths"].enumerated() {
            resizing.cell(atRow: i, column: 0)?.title = title
            resizing.cell(atRow: i, column: 0)?.tag = [NSBrowser.ColumnResizingType.autoColumnResizing, .userColumnResizing, .noColumnResizing][i].rawValue
        }
        resizing.intercellSpacing = NSSize(width: 0, height: 2)
        resizing.cellSize = NSSize(width: 176, height: 20)
        resizing.target = self
        resizing.action = Selector(("resizingChanged:"))
        content.addSubview(resizing)

        form.addEntry("Go to:").placeholderString = "/Users/guest/Documents"
        _ = form.addEntry("Note:")
        form.target = self
        form.action = Selector(("formEntered:"))
        content.addSubview(form)

        status.frame = NSRect(x: 200, y: 6, width: 388, height: 18)
        content.addSubview(status)
        view = content
        browser.delegate = self
        _ = browser.setPath("/Users/guest/Documents")
    }

    // MARK: Item-based browser delegate

    func rootItem(for browser: NSBrowser) -> Any? { root }
    func browser(_ browser: NSBrowser, numberOfChildrenOfItem item: Any?) -> Int { (item as? DemoFile)?.children?.count ?? 0 }
    func browser(_ browser: NSBrowser, child index: Int, ofItem item: Any?) -> Any { (item as! DemoFile).children![index] }
    func browser(_ browser: NSBrowser, isLeafItem item: Any?) -> Bool { (item as? DemoFile)?.children == nil }
    func browser(_ browser: NSBrowser, objectValueForItem item: Any?) -> Any? { (item as? DemoFile)?.name }

    // MARK: Actions

    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch action {
        case Selector(("browserClicked:")):
            status.stringValue = "Selected \(browser.path())"
        case Selector(("browserDoubleClicked:")):
            status.stringValue = "Opened \(browser.path())"
        case Selector(("resizingChanged:")):
            if let type = NSBrowser.ColumnResizingType(rawValue: resizing.selectedTag()) {
                browser.columnResizingType = type
                status.stringValue = "Column resizing: \(resizing.selectedCell()?.title ?? "")"
            }
        case Selector(("formEntered:")):
            guard form.indexOfSelectedItem() == 0, let entry = form.cell(at: 0) as? NSFormCell else {
                status.stringValue = "Note: \((form.cell(at: 1) as? NSFormCell)?.stringValue ?? "")"
                return true
            }
            let path = entry.stringValue
            status.stringValue = browser.setPath(path) ? "Went to \(browser.path())" : "No such path: \(path)"
        default:
            return false
        }
        return true
    }
}
