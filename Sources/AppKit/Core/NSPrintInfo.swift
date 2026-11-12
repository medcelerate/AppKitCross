// NSPrintInfo (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() are stubs awaiting implementation.
//
// The settings of a print job (ADR-0022): paper, orientation, margins, scaling,
// pagination, the printer, the job disposition, and the attribute dictionary the print
// panel and `NSPrintOperation` read (copies, page range, the saving URL). The Carbon
// `PM*` accessors have no counterpart on these platforms and stay unimplemented.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo
open class NSPrintInfo: NSObject, NSCopying, NSCoding {
    // MARK: Storage
    /// Paper size in points, oriented (landscape papers are wider than tall), as AppKit keeps it.
    private var _paperSize: NSSize
    private var _paperName: NSPrinter.PaperName?
    private var _orientation: NSPrintInfo.PaperOrientation = .portrait
    private var _leftMargin: CGFloat = 72
    private var _rightMargin: CGFloat = 72
    private var _topMargin: CGFloat = 90
    private var _bottomMargin: CGFloat = 90
    private var _scalingFactor: CGFloat = 1
    private var _horizontalPagination: NSPrintInfo.PaginationMode = .clip
    private var _verticalPagination: NSPrintInfo.PaginationMode = .automatic
    private var _horizontallyCentered = true
    private var _verticallyCentered = true
    private var _jobDisposition: NSPrintInfo.JobDisposition = .spool
    private var _selectionOnly = false
    private var _printer: NSPrinter?
    /// Attributes without a property of their own (copies, page range, the saving URL,
    /// headers and footers, ...).
    private var _extra: [NSPrintInfo.AttributeKey: Any] = [:]
    private let _printSettings = NSMutableDictionary()

    nonisolated(unsafe) private static var _shared: NSPrintInfo? = nil

    /// The paper the locale prints on: US Letter where it is the norm, A4 elsewhere.
    internal static func _defaultPaper() -> NSPrinter.Paper {
        let region = Locale.current.regionCode ?? ""
        let letter = ["US", "CA", "MX", "PH", "CL", "CO", "CR", "GT", "PA", "DO", "SV", "NI", "VE"].contains(region)
        return NSPrinter.papers[letter ? 0 : 5]
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/init()
    public override convenience init() { self.init(dictionary: [:]) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/init(coder:)
    public required init(coder: NSCoder) {
        let paper = NSPrintInfo._defaultPaper()
        _paperSize = paper.size
        _paperName = paper.name
        super.init()
        _paperSize = NSSize(width: CGFloat(coder.decodeDouble(forKey: "NSPaperWidth")), height: CGFloat(coder.decodeDouble(forKey: "NSPaperHeight")))
        if _paperSize.width <= 0 || _paperSize.height <= 0 { _paperSize = paper.size }
        _paperName = (coder.decodeObject(forKey: "NSPaperName") as? String).map { NSPrinter.PaperName($0) }
        _orientation = coder.decodeInteger(forKey: "NSOrientation") == 1 ? .landscape : .portrait
        if coder.containsValue(forKey: "NSLeftMargin") { _leftMargin = CGFloat(coder.decodeDouble(forKey: "NSLeftMargin")) }
        if coder.containsValue(forKey: "NSRightMargin") { _rightMargin = CGFloat(coder.decodeDouble(forKey: "NSRightMargin")) }
        if coder.containsValue(forKey: "NSTopMargin") { _topMargin = CGFloat(coder.decodeDouble(forKey: "NSTopMargin")) }
        if coder.containsValue(forKey: "NSBottomMargin") { _bottomMargin = CGFloat(coder.decodeDouble(forKey: "NSBottomMargin")) }
        if coder.containsValue(forKey: "NSScalingFactor") { _scalingFactor = CGFloat(coder.decodeDouble(forKey: "NSScalingFactor")) }
        _horizontalPagination = PaginationMode(rawValue: coder.decodeInteger(forKey: "NSHorizonalPagination")) ?? .clip
        _verticalPagination = PaginationMode(rawValue: coder.decodeInteger(forKey: "NSVerticalPagination")) ?? .automatic
        if coder.containsValue(forKey: "NSHorizontallyCentered") { _horizontallyCentered = coder.decodeBool(forKey: "NSHorizontallyCentered") }
        if coder.containsValue(forKey: "NSVerticallyCentered") { _verticallyCentered = coder.decodeBool(forKey: "NSVerticallyCentered") }
        if let d = coder.decodeObject(forKey: "NSJobDisposition") as? String { _jobDisposition = JobDisposition(rawValue: d) }
        if let name = coder.decodeObject(forKey: "NSPrinterName") as? String { _printer = NSPrinter(name: name) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/init(dictionary:)
    public init(dictionary attributes: [NSPrintInfo.AttributeKey : Any]) {
        let paper = NSPrintInfo._defaultPaper()
        _paperSize = paper.size
        _paperName = paper.name
        super.init()
        _apply(attributes)
    }

    /// Takes every known attribute from `attributes`; the rest lands in the dictionary.
    internal func _apply(_ attributes: [NSPrintInfo.AttributeKey: Any]) {
        func number(_ key: AttributeKey) -> CGFloat? {
            if let n = attributes[key] as? NSNumber { return CGFloat(n.doubleValue) }
            if let d = attributes[key] as? Double { return CGFloat(d) }
            if let i = attributes[key] as? Int { return CGFloat(i) }
            if let f = attributes[key] as? CGFloat { return f }
            return nil
        }
        func flag(_ key: AttributeKey) -> Bool? {
            if let b = attributes[key] as? Bool { return b }
            if let n = attributes[key] as? NSNumber { return n.boolValue }
            return nil
        }
        if let s = attributes[.paperSize] as? NSSize { _paperSize = s }
        else if let v = attributes[.paperSize] as? NSValue { _paperSize = v.sizeValue }
        if let name = attributes[.paperName] as? String { _paperName = NSPrinter.PaperName(name); if let s = NSPrinter._paperSize(for: _paperName!), attributes[.paperSize] == nil { _paperSize = s } }
        else if let name = attributes[.paperName] as? NSPrinter.PaperName { _paperName = name; if let s = NSPrinter._paperSize(for: name), attributes[.paperSize] == nil { _paperSize = s } }
        if let o = number(.orientation) {
            let landscape = Int(o) == PaperOrientation.landscape.rawValue
            _orientation = landscape ? .landscape : .portrait
            // A stored size is already oriented; a size from the paper table is portrait.
            if attributes[.paperSize] == nil && landscape && _paperSize.width < _paperSize.height { _paperSize = NSSize(width: _paperSize.height, height: _paperSize.width) }
        } else if attributes[.paperSize] != nil && _paperSize.width > _paperSize.height {
            _orientation = .landscape
        }
        if let v = number(.leftMargin) { _leftMargin = v }
        if let v = number(.rightMargin) { _rightMargin = v }
        if let v = number(.topMargin) { _topMargin = v }
        if let v = number(.bottomMargin) { _bottomMargin = v }
        if let v = number(.scalingFactor) { _scalingFactor = v }
        if let v = number(.horizontalPagination), let m = PaginationMode(rawValue: Int(v)) { _horizontalPagination = m }
        if let v = number(.verticalPagination), let m = PaginationMode(rawValue: Int(v)) { _verticalPagination = m }
        if let v = flag(.horizontallyCentered) { _horizontallyCentered = v }
        if let v = flag(.verticallyCentered) { _verticallyCentered = v }
        if let v = flag(.selectionOnly) { _selectionOnly = v }
        if let d = attributes[.jobDisposition] as? String { _jobDisposition = JobDisposition(rawValue: d) }
        else if let d = attributes[.jobDisposition] as? JobDisposition { _jobDisposition = d }
        if let p = attributes[.printer] as? NSPrinter { _printer = p }
        else if let name = attributes[.printerName] as? String, let p = NSPrinter(name: name) { _printer = p }
        let handled: Set<AttributeKey> = [.paperSize, .paperName, .orientation, .leftMargin, .rightMargin, .topMargin, .bottomMargin, .scalingFactor,
                                          .horizontalPagination, .verticalPagination, .horizontallyCentered, .verticallyCentered, .selectionOnly,
                                          .jobDisposition, .printer, .printerName]
        for (k, v) in attributes where !handled.contains(k) { _extra[k] = v }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/bottommargin
    open var bottomMargin: CGFloat {
        get { _bottomMargin }
        set { _bottomMargin = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/defaultprinter
    class public var defaultPrinter: NSPrinter? {
        let printers = NSPrinter._platformPrinters()
        guard let p = printers.first(where: \.isDefault) ?? printers.first else { return nil }
        return NSPrinter(_name: p.name, type: NSPrinter.TypeName(p.type))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/dictionary()
    /// A snapshot of every attribute; `init(dictionary:)` restores it.
    open func dictionary() -> NSMutableDictionary {
        let d = NSMutableDictionary()
        for (k, v) in _attributes() { d[k.rawValue] = v }
        return d
    }

    /// The attributes as a Swift dictionary (what `dictionary()` holds, typed by key).
    internal func _attributes() -> [NSPrintInfo.AttributeKey: Any] {
        var a = _extra
        a[.paperSize] = NSValue(size: _paperSize)
        if let n = _paperName { a[.paperName] = n.rawValue }
        a[.orientation] = NSNumber(value: _orientation.rawValue)
        a[.leftMargin] = NSNumber(value: Double(_leftMargin))
        a[.rightMargin] = NSNumber(value: Double(_rightMargin))
        a[.topMargin] = NSNumber(value: Double(_topMargin))
        a[.bottomMargin] = NSNumber(value: Double(_bottomMargin))
        a[.scalingFactor] = NSNumber(value: Double(_scalingFactor))
        a[.horizontalPagination] = NSNumber(value: _horizontalPagination.rawValue)
        a[.verticalPagination] = NSNumber(value: _verticalPagination.rawValue)
        a[.horizontallyCentered] = NSNumber(value: _horizontallyCentered)
        a[.verticallyCentered] = NSNumber(value: _verticallyCentered)
        a[.selectionOnly] = NSNumber(value: _selectionOnly)
        a[.jobDisposition] = _jobDisposition.rawValue
        a[.printer] = printer
        a[.printerName] = printer.name
        return a
    }

    /// Attributes without a property: `.copies`, `.firstPage`/`.lastPage`/`.allPages`,
    /// `.jobSavingURL`, `.headerAndFooter`, `.mustCollate`, `.reversePageOrder`, ...
    internal subscript(_ key: NSPrintInfo.AttributeKey) -> Any? {
        get { _extra[key] }
        set { _extra[key] = newValue }
    }
    internal func _int(_ key: NSPrintInfo.AttributeKey) -> Int? {
        if let n = _extra[key] as? NSNumber { return n.intValue }
        if let i = _extra[key] as? Int { return i }
        return nil
    }
    internal func _bool(_ key: NSPrintInfo.AttributeKey) -> Bool? {
        if let n = _extra[key] as? NSNumber { return n.boolValue }
        if let b = _extra[key] as? Bool { return b }
        return nil
    }
    /// `NSJobSavingURL`: where `.save` jobs go.
    internal var _jobSavingURL: URL? {
        get { (_extra[.jobSavingURL] as? URL) ?? (_extra[.jobSavingURL] as? String).map { URL(fileURLWithPath: $0) } }
        set { _extra[.jobSavingURL] = newValue }
    }
    /// The native dialog's driver settings (Windows: the DEVMODE), kept in the attributes
    /// so a copy of the info prints with them; nil until a native dialog ran.
    internal static let _driverSettingsKey = NSPrintInfo.AttributeKey("AppKitCrossDriverSettings")
    internal var _driverSettings: Data? {
        get { _extra[NSPrintInfo._driverSettingsKey] as? Data }
        set { _extra[NSPrintInfo._driverSettingsKey] = newValue }
    }
    /// `NSCopies`, at least 1.
    internal var _copies: Int {
        get { max(1, _int(.copies) ?? 1) }
        set { _extra[.copies] = NSNumber(value: max(1, newValue)) }
    }
    /// The requested page range (`NSFirstPage`...`NSLastPage`), nil for all pages.
    internal var _pageRange: (first: Int, last: Int)? {
        get {
            if _bool(.allPages) ?? true, _int(.firstPage) == nil { return nil }
            let first = max(1, _int(.firstPage) ?? 1)
            let last = _int(.lastPage) ?? Int.max
            return (first, max(first, last))
        }
        set {
            if let r = newValue {
                _extra[.allPages] = NSNumber(value: false)
                _extra[.firstPage] = NSNumber(value: r.first)
                _extra[.lastPage] = NSNumber(value: r.last)
            } else {
                _extra[.allPages] = NSNumber(value: true)
                _extra[.firstPage] = nil
                _extra[.lastPage] = nil
            }
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/horizontalpagination
    open var horizontalPagination: NSPrintInfo.PaginationMode {
        get { _horizontalPagination }
        set { _horizontalPagination = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/imageablepagebounds
    /// The part of the paper the printer can reach, in paper coordinates (bottom-left origin).
    open var imageablePageBounds: NSRect {
        let i = printer._imageableInsets
        return NSRect(x: i.left, y: i.bottom, width: max(0, _paperSize.width - i.left - i.right), height: max(0, _paperSize.height - i.top - i.bottom))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/ishorizontallycentered
    open var isHorizontallyCentered: Bool {
        get { _horizontallyCentered }
        set { _horizontallyCentered = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/isselectiononly
    open var isSelectionOnly: Bool {
        get { _selectionOnly }
        set { _selectionOnly = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/isverticallycentered
    open var isVerticallyCentered: Bool {
        get { _verticallyCentered }
        set { _verticallyCentered = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/jobdisposition
    open var jobDisposition: NSPrintInfo.JobDisposition {
        get { _jobDisposition }
        set { _jobDisposition = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/leftmargin
    open var leftMargin: CGFloat {
        get { _leftMargin }
        set { _leftMargin = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/localizedpapername
    open var localizedPaperName: String? {
        if let n = _paperName, let l = NSPrinter._localizedPaperName(n) { return l }
        return _paperName?.rawValue
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/orientation
    /// Changing the orientation turns the paper: the size's width and height swap.
    open var orientation: NSPrintInfo.PaperOrientation {
        get { _orientation }
        set {
            guard newValue != _orientation else { return }
            _orientation = newValue
            _paperSize = NSSize(width: _paperSize.height, height: _paperSize.width)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/papername
    open var paperName: NSPrinter.PaperName? {
        get { _paperName }
        set {
            _paperName = newValue
            if let n = newValue, let s = NSPrinter._paperSize(for: n) {
                _paperSize = _orientation == .landscape ? NSSize(width: s.height, height: s.width) : s
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/papersize
    /// Oriented: setting a size wider than tall does not change the orientation, as in
    /// AppKit; the paper name follows the size when the table knows it.
    open var paperSize: NSSize {
        get { _paperSize }
        set {
            _paperSize = newValue
            let portrait = _orientation == .landscape ? NSSize(width: newValue.height, height: newValue.width) : newValue
            _paperName = NSPrinter._paperName(for: portrait)?.name
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/pmpageformat()
    open func pmPageFormat() -> UnsafeMutableRawPointer { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/pmprintsession()
    open func pmPrintSession() -> UnsafeMutableRawPointer { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/pmprintsettings()
    open func pmPrintSettings() -> UnsafeMutableRawPointer { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/printsettings
    open var printSettings: NSMutableDictionary { _printSettings }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/printer
    /// The chosen printer, else the default printer, else the generic PDF printer.
    open var printer: NSPrinter {
        get { _printer ?? NSPrintInfo.defaultPrinter ?? NSPrinter._generic() }
        set { _printer = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/rightmargin
    open var rightMargin: CGFloat {
        get { _rightMargin }
        set { _rightMargin = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/scalingfactor
    open var scalingFactor: CGFloat {
        get { _scalingFactor }
        set { _scalingFactor = newValue > 0 ? newValue : 1 }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/setupprintoperationdefaultvalues()
    /// Resets the per-operation attributes: one copy, all pages, spool.
    open func setUpPrintOperationDefaultValues() {
        _copies = 1
        _pageRange = nil
        _extra[.mustCollate] = NSNumber(value: true)
        _extra[.reversePageOrder] = NSNumber(value: false)
        _jobDisposition = .spool
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/shared
    class public var shared: NSPrintInfo {
        get {
            if let s = _shared { return s }
            let s = NSPrintInfo()
            _shared = s
            return s
        }
        set { _shared = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/takesettings(from:)
    open func takeSettings(from inPDFInfo: NSPDFInfo) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/topmargin
    open var topMargin: CGFloat {
        get { _topMargin }
        set { _topMargin = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/updatefrompmpageformat()
    open func updateFromPMPageFormat() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/updatefrompmprintsettings()
    open func updateFromPMPrintSettings() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintinfo/verticalpagination
    open var verticalPagination: NSPrintInfo.PaginationMode {
        get { _verticalPagination }
        set { _verticalPagination = newValue }
    }
    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any {
        let c = NSPrintInfo(dictionary: _attributes())
        c._printer = _printer
        var settings: [AnyHashable: Any] = [:]
        for (k, v) in _printSettings { if let key = k as? AnyHashable { settings[key] = v } }
        c._printSettings.addEntries(from: settings)
        return c
    }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) {
        coder.encode(Double(_paperSize.width), forKey: "NSPaperWidth")
        coder.encode(Double(_paperSize.height), forKey: "NSPaperHeight")
        if let n = _paperName { coder.encode(n.rawValue, forKey: "NSPaperName") }
        coder.encode(_orientation.rawValue, forKey: "NSOrientation")
        coder.encode(Double(_leftMargin), forKey: "NSLeftMargin")
        coder.encode(Double(_rightMargin), forKey: "NSRightMargin")
        coder.encode(Double(_topMargin), forKey: "NSTopMargin")
        coder.encode(Double(_bottomMargin), forKey: "NSBottomMargin")
        coder.encode(Double(_scalingFactor), forKey: "NSScalingFactor")
        coder.encode(_horizontalPagination.rawValue, forKey: "NSHorizonalPagination")
        coder.encode(_verticalPagination.rawValue, forKey: "NSVerticalPagination")
        coder.encode(_horizontallyCentered, forKey: "NSHorizontallyCentered")
        coder.encode(_verticallyCentered, forKey: "NSVerticallyCentered")
        coder.encode(_jobDisposition.rawValue, forKey: "NSJobDisposition")
        if let p = _printer { coder.encode(p.name, forKey: "NSPrinterName") }
    }

    open override var description: String {
        "NSPrintInfo \(localizedPaperName ?? "custom") \(Int(_paperSize.width))x\(Int(_paperSize.height)) \(_orientation == .landscape ? "landscape" : "portrait") margins \(Int(_leftMargin))/\(Int(_rightMargin))/\(Int(_topMargin))/\(Int(_bottomMargin)) scale \(_scalingFactor)"
    }
}
