// NSColorList (hand-written; seeded from the generated stub, see tools/apigen)
//
// An ordered, named list of colours (ADR-0022). The standard lists AppKit ships (Apple,
// Crayons, Web Safe Colors) are built in; lists written with `write(to:)` are property
// lists (`[name: [r, g, b, a]]` plus the key order), and `init?(name:fromFile:)` reads
// them back. There is no shared colour-list folder on these platforms, so
// `availableColorLists` is the built-in lists plus the ones this process has written.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorlist
open class NSColorList: NSObject, NSSecureCoding, NSCoding {
    // MARK: Storage
    private var _name: NSColorList.Name?
    private var _keys: [NSColor.Name] = []
    private var _colors: [NSColor.Name: NSColor] = [:]
    private var _file: String? = nil
    private var _isEditable = true
    nonisolated(unsafe) private static var _created: [NSColorList] = []
    nonisolated(unsafe) private static var _builtIn: [NSColorList]? = nil

    private func _changed() {
        NotificationCenter.default.post(name: NSColorList.didChangeNotification, object: self)
    }

    /// The crayon names and colours of Apple's Crayons picker (8 hues by 6 shades).
    internal static let crayons: [(String, NSColor)] = [
        ("Cayenne", NSColor(red: 0.58, green: 0.07, blue: 0, alpha: 1)), ("Mocha", NSColor(red: 0.58, green: 0.3, blue: 0, alpha: 1)),
        ("Asparagus", NSColor(red: 0.58, green: 0.58, blue: 0, alpha: 1)), ("Fern", NSColor(red: 0.3, green: 0.58, blue: 0, alpha: 1)),
        ("Clover", NSColor(red: 0, green: 0.58, blue: 0, alpha: 1)), ("Moss", NSColor(red: 0, green: 0.58, blue: 0.3, alpha: 1)),
        ("Teal", NSColor(red: 0, green: 0.58, blue: 0.58, alpha: 1)), ("Ocean", NSColor(red: 0, green: 0.3, blue: 0.58, alpha: 1)),
        ("Midnight", NSColor(red: 0, green: 0.07, blue: 0.58, alpha: 1)), ("Eggplant", NSColor(red: 0.3, green: 0, blue: 0.58, alpha: 1)),
        ("Plum", NSColor(red: 0.58, green: 0, blue: 0.58, alpha: 1)), ("Maroon", NSColor(red: 0.58, green: 0, blue: 0.3, alpha: 1)),
        ("Maraschino", NSColor(red: 1, green: 0.15, blue: 0, alpha: 1)), ("Tangerine", NSColor(red: 1, green: 0.58, blue: 0, alpha: 1)),
        ("Lemon", NSColor(red: 1, green: 1, blue: 0, alpha: 1)), ("Lime", NSColor(red: 0.58, green: 1, blue: 0, alpha: 1)),
        ("Spring", NSColor(red: 0, green: 1, blue: 0, alpha: 1)), ("Sea Foam", NSColor(red: 0, green: 1, blue: 0.58, alpha: 1)),
        ("Turquoise", NSColor(red: 0, green: 1, blue: 1, alpha: 1)), ("Aqua", NSColor(red: 0, green: 0.58, blue: 1, alpha: 1)),
        ("Blueberry", NSColor(red: 0, green: 0.15, blue: 1, alpha: 1)), ("Grape", NSColor(red: 0.58, green: 0, blue: 1, alpha: 1)),
        ("Magenta", NSColor(red: 1, green: 0, blue: 1, alpha: 1)), ("Strawberry", NSColor(red: 1, green: 0, blue: 0.58, alpha: 1)),
        ("Salmon", NSColor(red: 1, green: 0.5, blue: 0.5, alpha: 1)), ("Cantaloupe", NSColor(red: 1, green: 0.8, blue: 0.5, alpha: 1)),
        ("Banana", NSColor(red: 1, green: 1, blue: 0.5, alpha: 1)), ("Honeydew", NSColor(red: 0.8, green: 1, blue: 0.5, alpha: 1)),
        ("Flora", NSColor(red: 0.5, green: 1, blue: 0.5, alpha: 1)), ("Spindrift", NSColor(red: 0.5, green: 1, blue: 0.8, alpha: 1)),
        ("Ice", NSColor(red: 0.5, green: 1, blue: 1, alpha: 1)), ("Sky", NSColor(red: 0.5, green: 0.8, blue: 1, alpha: 1)),
        ("Lavender", NSColor(red: 0.5, green: 0.5, blue: 1, alpha: 1)), ("Orchid", NSColor(red: 0.8, green: 0.5, blue: 1, alpha: 1)),
        ("Bubblegum", NSColor(red: 1, green: 0.5, blue: 1, alpha: 1)), ("Carnation", NSColor(red: 1, green: 0.5, blue: 0.8, alpha: 1)),
        ("Licorice", NSColor(white: 0, alpha: 1)), ("Lead", NSColor(white: 0.1, alpha: 1)), ("Tungsten", NSColor(white: 0.2, alpha: 1)),
        ("Iron", NSColor(white: 0.3, alpha: 1)), ("Steel", NSColor(white: 0.4, alpha: 1)), ("Tin", NSColor(white: 0.5, alpha: 1)),
        ("Nickel", NSColor(white: 0.55, alpha: 1)), ("Aluminum", NSColor(white: 0.6, alpha: 1)), ("Magnesium", NSColor(white: 0.7, alpha: 1)),
        ("Silver", NSColor(white: 0.8, alpha: 1)), ("Mercury", NSColor(white: 0.9, alpha: 1)), ("Snow", NSColor(white: 1, alpha: 1)),
    ]

    private static func _makeBuiltIn() -> [NSColorList] {
        func list(_ name: String, _ entries: [(String, NSColor)]) -> NSColorList {
            let l = NSColorList(name: name)
            for (k, c) in entries { l._keys.append(k); l._colors[k] = c }
            l._isEditable = false
            return l
        }
        let apple: [(String, NSColor)] = [
            ("Black", .black), ("Blue", .blue), ("Brown", .brown), ("Cyan", .cyan), ("Green", .green), ("Magenta", .magenta),
            ("Orange", .orange), ("Purple", .purple), ("Red", .red), ("Yellow", .yellow), ("White", .white),
        ]
        var web: [(String, NSColor)] = []
        for r in stride(from: 0, through: 255, by: 51) { for g in stride(from: 0, through: 255, by: 51) { for b in stride(from: 0, through: 255, by: 51) {
            web.append((String(format: "%02X%02X%02X", r, g, b), NSColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)))
        } } }
        return [list("Apple", apple), list("Crayons", crayons), list("Web Safe Colors", web)]
    }

    open override var description: String { "<NSColorList \(_name ?? "") \(_keys.count) colors>" }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorlist/init(name:)
    public init(name: NSColorList.Name) {
        _name = name
        super.init()
    }
    /// Reads a list written by `write(to:)` (or `write(toFile:)`); a nil path makes an empty list.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorlist/init(name:fromfile:)
    public init?(name: NSColorList.Name, fromFile path: String?) {
        _name = name
        super.init()
        if let path {
            guard let data = FileManager.default.contents(atPath: path),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let keys = plist["keys"] as? [String], let colors = plist["colors"] as? [String: [Double]] else { return nil }
            for k in keys {
                guard let c = colors[k], c.count >= 4 else { continue }
                _keys.append(k)
                _colors[k] = NSColor(red: CGFloat(c[0]), green: CGFloat(c[1]), blue: CGFloat(c[2]), alpha: CGFloat(c[3]))
            }
            _file = path
            _isEditable = FileManager.default.isWritableFile(atPath: path)
        }
        NSColorList._created.append(self)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorlist/init(named:)
    public convenience init?(named name: NSColorList.Name) {
        guard let found = NSColorList.availableColorLists.first(where: { $0.name == name }) else { return nil }
        self.init(name: name)
        NSColorList._created.removeAll { $0 === self }
        _keys = found._keys
        _colors = found._colors
        _isEditable = found._isEditable
        _file = found._file
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorlist/allkeys
    open var allKeys: [NSColor.Name] { _keys }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorlist/availablecolorlists
    class public var availableColorLists: [NSColorList] {
        if _builtIn == nil { _builtIn = _makeBuiltIn() }
        return (_builtIn ?? []) + _created.filter { l in !(_builtIn ?? []).contains { $0 === l } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorlist/color(withkey:)
    open func color(withKey key: NSColor.Name) -> NSColor? { _colors[key] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorlist/didchangenotification
    static public var didChangeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSColorListDidChangeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorlist/insertcolor(_:key:at:)
    open func insertColor(_ color: NSColor, key: NSColor.Name, at loc: Int) {
        guard _isEditable else { return }
        _keys.removeAll { $0 == key }
        _keys.insert(key, at: max(0, min(loc, _keys.count)))
        _colors[key] = color
        _changed()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorlist/iseditable
    open var isEditable: Bool { _isEditable }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorlist/name
    open var name: NSColorList.Name? { _name }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorlist/removecolor(withkey:)
    open func removeColor(withKey key: NSColor.Name) {
        guard _isEditable, _colors[key] != nil else { return }
        _keys.removeAll { $0 == key }
        _colors[key] = nil
        _changed()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorlist/removefile()
    open func removeFile() {
        if let f = _file { try? FileManager.default.removeItem(atPath: f) }
        _file = nil
        NSColorList._created.removeAll { $0 === self }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorlist/setcolor(_:forkey:)
    open func setColor(_ color: NSColor, forKey key: NSColor.Name) {
        guard _isEditable else { return }
        if _colors[key] == nil { _keys.append(key) }
        _colors[key] = color
        _changed()
    }
    private func _plistData() throws -> Data {
        var colors: [String: [Double]] = [:]
        for k in _keys { if let c = _colors[k] { colors[k] = [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent)] } }
        let plist: [String: Any] = ["name": _name ?? "", "keys": _keys, "colors": colors]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
    /// Writes the list; nil goes to `~/Library/Colors/<name>.clr` as on macOS.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorlist/write(to:)
    @available(macOS 10.11, *)
    open func write(to url: URL?) throws {
        let target = url ?? NSColorList._defaultURL(for: _name ?? "Untitled")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try _plistData().write(to: target)
        _file = target.path
        if !NSColorList._created.contains(where: { $0 === self }) { NSColorList._created.append(self) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorlist/write(tofile:)
    open func write(toFile path: String?) -> Bool {
        do { try write(to: path.map { URL(fileURLWithPath: $0) }); return true } catch { return false }
    }
    private static func _defaultURL(for name: String) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library").appendingPathComponent("Colors").appendingPathComponent("\(name).clr")
    }
    // Requirement of NSSecureCoding
    class public var supportsSecureCoding: Bool { true }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) {
        coder.encode(_name, forKey: "NSColorListName")
        coder.encode(_keys as NSArray, forKey: "NSColorListKeys")
        var comps: [String: [Double]] = [:]
        for k in _keys { if let c = _colors[k] { comps[k] = [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent)] } }
        coder.encode(comps as NSDictionary, forKey: "NSColorListColors")
    }
    // Requirement of NSCoding
    public required init?(coder: NSCoder) {
        _name = coder.decodeObject(forKey: "NSColorListName") as? String
        super.init()
        _keys = (coder.decodeObject(forKey: "NSColorListKeys") as? [String]) ?? []
        let comps = (coder.decodeObject(forKey: "NSColorListColors") as? [String: [Double]]) ?? [:]
        for k in _keys { if let c = comps[k], c.count >= 4 { _colors[k] = NSColor(red: CGFloat(c[0]), green: CGFloat(c[1]), blue: CGFloat(c[2]), alpha: CGFloat(c[3])) } }
    }
}
