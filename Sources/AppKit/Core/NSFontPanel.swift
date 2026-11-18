// NSFontPanel (hand-written; seeded from the generated stub, see tools/apigen)
//
// The shared Fonts panel, drawn by the package on every backend (ADR-0022): a preview of
// the selection over three lists, Family, Typeface and Size, from `NSFontManager`'s
// installed families, a size field, and the accessory view under them. A change in the
// lists tells the font manager, which sends `changeFont:` through the responder chain;
// the receiver converts its fonts with `NSFontManager.convert(_:)`, which asks the panel.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontpanel
@MainActor open class NSFontPanel: NSPanel {
    // MARK: Storage
    nonisolated(unsafe) private static var _shared: NSFontPanel? = nil
    internal static let standardSizes: [CGFloat] = [9, 10, 11, 12, 13, 14, 18, 24, 36, 48, 64, 72, 96, 144, 288]

    private var _isEnabled = true
    private var _worksWhenModal = true
    private var _accessoryView: NSView? = nil
    private var _modeMask: NSFontPanel.ModeMask = .standardModes
    /// The font the panel was last given, and whether it stood for several fonts.
    private var _panelFont: NSFont? = nil
    private var _multiple = false
    /// What the user changed since `setPanelFont` (`.face` covers family and typeface).
    private var _changed: NSFontPanel.ModeMask = []
    internal var _syncing = false

    internal let _view: _NSFontPanelView

    /// The family, PostScript name and size the lists show.
    internal var _selectedFamily: String? { _view.selectedFamily }
    internal var _selectedFace: String? { _view.selectedFace }
    internal var _selectedSize: CGFloat { _view.selectedSize }

    @MainActor public override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        _view = _NSFontPanelView(frame: NSRect(origin: .zero, size: contentRect.size))
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        title = "Fonts"
        contentMinSize = NSSize(width: 380, height: 280)
        isReleasedWhenClosed = false
        _view.panel = self
        contentView = _view
        _view.reload()
    }
    @MainActor public required init?(coder: NSCoder) { nil }

    /// The lists changed under the user: remember what, show it, and tell the manager.
    internal func _selectionDidChange(_ what: NSFontPanel.ModeMask) {
        _NSPanelTrace.log("NSFontPanel selection changed \(what.rawValue) syncing=\(_syncing) enabled=\(_isEnabled) family=\(_selectedFamily ?? "nil") face=\(_selectedFace ?? "nil") size=\(_selectedSize)")
        guard !_syncing else { return }
        _changed.formUnion(what)
        _view.updatePreview()
        guard _isEnabled else { return }
        NSFontManager.shared._panelDidChangeFont()
    }

    /// Asks the responder that would receive `changeFont:` which parts to show.
    internal func _refreshValidModes() {
        var mask: NSFontPanel.ModeMask = .standardModes
        if let r = NSFontManager.shared._fontChangingResponder() as? NSFontChanging { mask = r.validModesForFontPanel(self) }
        _modeMask = mask
        _view.setVisibleModes(mask)
    }

    internal var _effectiveModeMask: NSFontPanel.ModeMask { _modeMask }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontpanel/accessoryview
    @MainActor open var accessoryView: NSView? {
        get { _accessoryView }
        set {
            _accessoryView?.removeFromSuperview()
            _accessoryView = newValue
            _view.accessory = newValue
            if let v = newValue { _view.addSubview(v) }
            _view.needsLayout = true
        }
    }
    /// The font the panel's selection turns `fontObj` into. With one font selected the
    /// panel's face and size replace it; when the panel stands for several fonts only
    /// the parts the user changed (family and face, or size) apply to each.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontpanel/convert(_:)
    @MainActor open func convert(_ fontObj: NSFont) -> NSFont {
        let fm = NSFontManager.shared
        let size = _selectedSize > 0 ? _selectedSize : fontObj.pointSize
        if !_multiple {
            if let ps = _selectedFace, let f = NSFont(name: ps, size: size) { return f }
            var f = fontObj
            if let fam = _selectedFamily { f = fm.convert(f, toFamily: fam) }
            return fm.convert(f, toSize: size)
        }
        var f = fontObj
        if _changed.contains(.face) {
            if let ps = _selectedFace, let face = NSFont(name: ps, size: f.pointSize) { f = face }
            else if let fam = _selectedFamily { f = fm.convert(f, toFamily: fam) }
        }
        if _changed.contains(.size) { f = fm.convert(f, toSize: size) }
        return f
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontpanel/isenabled
    @MainActor open var isEnabled: Bool {
        get { _isEnabled }
        set { _isEnabled = newValue; _view.setEnabled(newValue) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontpanel/reloaddefaultfontfamilies()
    @MainActor open func reloadDefaultFontFamilies() {
        _view.reload()
        if let f = _panelFont { setPanelFont(f, isMultiple: _multiple) }
    }
    /// Shows `fontObj` in the lists and the preview without sending anything.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontpanel/setpanelfont(_:ismultiple:)
    @MainActor open func setPanelFont(_ fontObj: NSFont, isMultiple flag: Bool) {
        _panelFont = fontObj
        _multiple = flag
        _changed = []
        _syncing = true
        _view.select(font: fontObj, multiple: flag)
        _syncing = false
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontpanel/shared
    @MainActor class public var shared: NSFontPanel {
        if let p = _shared { return p }
        let rect = NSRect(x: 0, y: 0, width: 520, height: 420)
        let style: NSWindow.StyleMask = [.titled, .closable, .resizable, .utilityWindow]
        let panel = NSFontPanel(contentRect: rect, styleMask: style, backing: .buffered, defer: false)
        panel.center()
        // Beside the key window, like AppKit's panels, when there is one.
        if let key = NSApplication.shared.keyWindow, let screen = key.screen ?? NSScreen.main {
            var origin = NSPoint(x: key.frame.maxX + 12, y: key.frame.maxY - panel.frame.height)
            if origin.x + panel.frame.width > screen.visibleFrame.maxX { origin.x = max(screen.visibleFrame.minX, key.frame.minX - panel.frame.width - 12) }
            origin.y = max(screen.visibleFrame.minY, origin.y)
            panel.setFrameOrigin(origin)
        }
        _shared = panel
        return panel
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontpanel/sharedfontpanelexists
    @MainActor class public var sharedFontPanelExists: Bool { _shared != nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontpanel/workswhenmodal
    @MainActor open override var worksWhenModal: Bool {
        get { _worksWhenModal }
        set { _worksWhenModal = newValue }
    }
    @MainActor open override var canBecomeMain: Bool { false }
}

// MARK: - The panel's content

/// Family, Typeface and Size lists over a preview, with the size field and the accessory view.
@MainActor
internal final class _NSFontPanelView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    weak var panel: NSFontPanel?
    var accessory: NSView? = nil

    let preview = _NSFontPreviewView(frame: .zero)
    let familyLabel = NSTextField(labelWithString: "Family")
    let faceLabel = NSTextField(labelWithString: "Typeface")
    let sizeLabel = NSTextField(labelWithString: "Size")
    let familyScroll = NSScrollView(frame: .zero)
    let faceScroll = NSScrollView(frame: .zero)
    let sizeScroll = NSScrollView(frame: .zero)
    let familyTable = NSTableView(frame: .zero)
    let faceTable = NSTableView(frame: .zero)
    let sizeTable = NSTableView(frame: .zero)
    let sizeField = NSTextField(string: "")

    private(set) var families: [String] = []
    /// `[postScriptName, styleName, weight, traits]` of the selected family.
    private(set) var faces: [[Any]] = []
    private var customSize: CGFloat? = nil
    private var showsFace = true, showsSize = true
    private static let fieldAction = Selector(("_fontPanelSizeField:"))

    var selectedFamily: String? { familyTable.selectedRow >= 0 && familyTable.selectedRow < families.count ? families[familyTable.selectedRow] : nil }
    var selectedFace: String? { faceTable.selectedRow >= 0 && faceTable.selectedRow < faces.count ? faces[faceTable.selectedRow][0] as? String : nil }
    var selectedSize: CGFloat {
        if let c = customSize { return c }
        let row = sizeTable.selectedRow
        return row >= 0 && row < NSFontPanel.standardSizes.count ? NSFontPanel.standardSizes[row] : 0
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        for (table, scroll, id) in [(familyTable, familyScroll, "Family"), (faceTable, faceScroll, "Typeface"), (sizeTable, sizeScroll, "Size")] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("AppKitCross.FontPanel.\(id)"))
            column.dataCell = NSTextFieldCell(textCell: "")
            table.addTableColumn(column)
            table.headerView = nil
            table.rowHeight = 18
            table.allowsEmptySelection = true
            table.allowsMultipleSelection = false
            table.dataSource = self
            table.delegate = self
            table.setAccessibilityLabel(id)
            scroll.documentView = table
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.borderType = .bezelBorder
            addSubview(scroll)
        }
        for l in [familyLabel, faceLabel, sizeLabel] { l.font = NSFont.boldSystemFont(ofSize: 11); addSubview(l) }
        sizeField.target = self
        sizeField.action = _NSFontPanelView.fieldAction
        sizeField.alignment = .right
        sizeField.setAccessibilityLabel("Size")
        setActionHandler(for: _NSFontPanelView.fieldAction) { [weak self] _ in self?.sizeFieldChanged() }
        addSubview(sizeField)
        addSubview(preview)
    }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let margin: CGFloat = 12, gap: CGFloat = 8, labelHeight: CGFloat = 16
        let w = bounds.width, h = bounds.height
        var bottom = h - margin
        if let a = accessory {
            let ah = a.frame.height
            a.frame = NSRect(x: margin, y: bottom - ah, width: w - 2 * margin, height: ah)
            bottom -= ah + gap
        }
        let previewHeight: CGFloat = 64
        preview.frame = NSRect(x: margin, y: margin, width: w - 2 * margin, height: previewHeight)
        let top = margin + previewHeight + gap
        let columnsWidth = w - 2 * margin
        let sizeWidth: CGFloat = showsSize ? 72 : 0
        let remaining = columnsWidth - (showsSize ? sizeWidth + gap : 0)
        let familyWidth = showsFace ? (remaining - gap) * 0.55 : remaining
        let faceWidth = showsFace ? remaining - gap - familyWidth : 0
        var x = margin
        familyLabel.frame = NSRect(x: x, y: top, width: familyWidth, height: labelHeight)
        familyScroll.frame = NSRect(x: x, y: top + labelHeight + 2, width: familyWidth, height: bottom - top - labelHeight - 2)
        x += familyWidth + gap
        faceLabel.isHidden = !showsFace
        faceScroll.isHidden = !showsFace
        if showsFace {
            faceLabel.frame = NSRect(x: x, y: top, width: faceWidth, height: labelHeight)
            faceScroll.frame = NSRect(x: x, y: top + labelHeight + 2, width: faceWidth, height: bottom - top - labelHeight - 2)
            x += faceWidth + gap
        }
        sizeLabel.isHidden = !showsSize
        sizeScroll.isHidden = !showsSize
        sizeField.isHidden = !showsSize
        if showsSize {
            sizeLabel.frame = NSRect(x: x, y: top, width: sizeWidth, height: labelHeight)
            let fieldHeight: CGFloat = 22
            sizeField.frame = NSRect(x: x, y: top + labelHeight + 2, width: sizeWidth, height: fieldHeight)
            sizeScroll.frame = NSRect(x: x, y: top + labelHeight + 2 + fieldHeight + 4, width: sizeWidth, height: bottom - top - labelHeight - 6 - fieldHeight)
        }
        for (scroll, table) in [(familyScroll, familyTable), (faceScroll, faceTable), (sizeScroll, sizeTable)] {
            scroll.tile()
            if let c = table.tableColumns.first { c.width = max(10, scroll.contentView.bounds.width) }
            table.tile()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath.fill(bounds)
    }

    // MARK: Contents

    func reload() {
        families = NSFontManager.shared.availableFontFamilies
        familyTable.reloadData()
        sizeTable.reloadData()
        reloadFaces()
    }

    private func reloadFaces() {
        faces = selectedFamily.flatMap { NSFontManager.shared.availableMembers(ofFontFamily: $0) } ?? []
        faceTable.reloadData()
    }

    func setVisibleModes(_ mask: NSFontPanel.ModeMask) {
        showsFace = mask.contains(.face)
        showsSize = mask.contains(.size)
        needsLayout = true
    }

    func setEnabled(_ enabled: Bool) {
        for t in [familyTable, faceTable, sizeTable] { t.isEnabled = enabled }
        sizeField.isEnabled = enabled
    }

    /// Selects `font`'s family, face and size (a size outside the list goes in the field).
    func select(font: NSFont, multiple: Bool) {
        if families.isEmpty { reload() }
        let family = font.familyName ?? font.fontName
        if let row = families.firstIndex(where: { $0.lowercased() == family.lowercased() }) {
            familyTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            familyTable.scrollRowToVisible(row)
        } else {
            familyTable.deselectAll(nil)
        }
        reloadFaces()
        let ps = font.handle.postScriptName
        let traits = NSFontManager.shared.traits(of: font)
        var faceRow = faces.firstIndex { ($0[0] as? String) == ps || ($0[0] as? String) == font.fontName }
        if faceRow == nil {
            faceRow = faces.firstIndex { NSFontTraitMask(rawValue: $0[3] as? UInt ?? 0).intersection([.boldFontMask, .italicFontMask]) == traits.intersection([.boldFontMask, .italicFontMask]) }
        }
        if let r = faceRow {
            faceTable.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false)
            faceTable.scrollRowToVisible(r)
        } else {
            faceTable.deselectAll(nil)
        }
        if let r = NSFontPanel.standardSizes.firstIndex(of: font.pointSize) {
            customSize = nil
            sizeTable.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false)
            sizeTable.scrollRowToVisible(r)
        } else {
            customSize = font.pointSize
            sizeTable.deselectAll(nil)
        }
        sizeField.stringValue = _NSFontPanelView.format(font.pointSize)
        updatePreview(multiple: multiple)
        // A font outside the lists (the system font's hidden family) still previews.
        if preview.font == nil { preview.font = font; preview.needsDisplay = true }
    }

    static func format(_ size: CGFloat) -> String {
        size == size.rounded() ? String(Int(size)) : String(format: "%.1f", Double(size))
    }

    /// The font the lists describe, for the preview.
    var previewFont: NSFont? {
        let size = selectedSize > 0 ? selectedSize : 13
        if let ps = selectedFace, let f = NSFont(name: ps, size: size) { return f }
        if let fam = selectedFamily, let f = NSFont(name: fam, size: size) { return f }
        return nil
    }

    func updatePreview(multiple: Bool = false) {
        preview.font = previewFont
        preview.multiple = multiple
        preview.needsDisplay = true
    }

    private func sizeFieldChanged() {
        guard let v = Double(sizeField.stringValue.trimmingCharacters(in: .whitespaces)), v > 0 else {
            sizeField.stringValue = _NSFontPanelView.format(selectedSize)
            return
        }
        let size = CGFloat(v)
        if let r = NSFontPanel.standardSizes.firstIndex(of: size) {
            customSize = nil
            sizeTable.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false)   // notifies, which sends
        } else {
            customSize = size
            sizeTable.deselectAll(nil)
            panel?._selectionDidChange(.size)
        }
    }

    // MARK: Tables

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === familyTable { return families.count }
        if tableView === faceTable { return faces.count }
        return NSFontPanel.standardSizes.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        if tableView === familyTable { return row < families.count ? families[row] : nil }
        if tableView === faceTable { return row < faces.count ? faces[row][1] as? String : nil }
        return row < NSFontPanel.standardSizes.count ? _NSFontPanelView.format(NSFontPanel.standardSizes[row]) : nil
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView else { return }
        if table === familyTable {
            let previousFace = selectedFace.flatMap { ps in faces.first { ($0[0] as? String) == ps } }
            reloadFaces()
            // Keep the typeface by traits when the new family has one like it, else the regular one.
            var row = 0
            if let p = previousFace, let t = p[3] as? UInt, let r = faces.firstIndex(where: { ($0[3] as? UInt) == t }) { row = r }
            if !faces.isEmpty {
                let wasSyncing = panel?._syncing ?? false
                panel?._syncing = true
                faceTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                panel?._syncing = wasSyncing
            }
            panel?._selectionDidChange(.face)
        } else if table === faceTable {
            panel?._selectionDidChange(.face)
        } else if table === sizeTable {
            if sizeTable.selectedRow >= 0 {
                customSize = nil
                sizeField.stringValue = _NSFontPanelView.format(selectedSize)
            }
            panel?._selectionDidChange(.size)
        }
    }
}

/// A bordered box showing the selected font's name set in that font.
@MainActor
internal final class _NSFontPreviewView: NSView {
    var font: NSFont? = nil
    var multiple = false
    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        NSBezierPath.fill(bounds)
        NSColor.separatorColor.setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
        guard let f = font else {
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]
            let s = multiple ? "Multiple fonts" : "No font selected"
            let size = s.size(withAttributes: attrs)
            s.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attrs)
            return
        }
        let shown = f.withSize(min(f.pointSize, bounds.height - 12))
        let name = "\(f.familyName ?? f.fontName) \(f._styleName) \(_NSFontPanelView.format(f.pointSize))"
        let attrs: [NSAttributedString.Key: Any] = [.font: shown, .foregroundColor: NSColor.textColor]
        let size = name.size(withAttributes: attrs)
        let x = max(6, (bounds.width - size.width) / 2)
        name.draw(at: NSPoint(x: x, y: max(0, (bounds.height - size.height) / 2)), withAttributes: attrs)
    }
}
