// NSFontManager: the shared manager's trait, weight, family and face conversions over
// NSFont, the installed families through CoreText, the font panel's owner and the
// `changeFont:` sender (ADR-0022). `Font.italic()` in SwiftUI and attributed markdown go
// through `convert(_:toHaveTrait:)`.
//
// The panel and the Font menu both end in `sendAction()`: the manager records what the
// user asked for (`currentFontAction`) and sends `changeFont:` with itself as the sender
// through the responder chain; the receiver passes each font it holds to `convert(_:)`,
// which applies that action.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager
open class NSFontManager: NSObject, NSMenuItemValidation {
    // MARK: Storage
    private var _action: Selector = Selector(("changeFont:"))
    private weak var _target: AnyObject?
    private weak var _delegate: AnyObject?
    private var _isEnabled = true
    private var _selectedFont: NSFont? = nil
    private var _isMultiple = false
    private var _selectedAttributes: [String: Any] = [:]
    private var _currentAction: NSFontAction = .noFontChangeAction
    private var _pendingTrait: NSFontTraitMask = []
    private var _fontMenu: NSMenu? = nil
    nonisolated(unsafe) internal static var _fontPanelFactory: AnyClass? = nil
    nonisolated(unsafe) private static var _factory: AnyClass? = nil

    /// Installed families, cached for the process (the font set does not change under it).
    nonisolated(unsafe) private static var _familyCache: [String]? = nil
    nonisolated(unsafe) private static var _memberCache: [String: [[Any]]] = [:]

    /// The panel's selection changed: record the action and tell the responder chain.
    @MainActor internal func _panelDidChangeFont() {
        _currentAction = .viaPanelFontAction
        _ = sendAction()
    }

    /// The key window's responder that would handle `changeFont:` (a text view with a
    /// selection, a view of the application's); nil when nothing would.
    @MainActor internal func _fontChangingResponder() -> NSResponder? {
        let app = NSApplication.shared
        let action = _action
        var windows: [NSWindow] = []
        if let k = app.keyWindow, !(k is NSFontPanel), !(k is NSColorPanel) { windows.append(k) }
        if let m = app.mainWindow, !windows.contains(where: { $0 === m }) { windows.append(m) }
        for w in windows {
            var r: NSResponder? = w.firstResponder
            while let cur = r {
                if ActionRegistry.canPerform(action, on: cur) { return cur }
                r = cur.nextResponder
            }
        }
        return nil
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/action
    open var action: Selector {
        get { _action }
        set { _action = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/addcollection(_:options:)
    open func addCollection(_ collectionName: String, options collectionOptions: NSFontCollectionOptions = []) -> Bool {
        let name = NSFontCollection.Name(collectionName)
        let visibility: NSFontCollection.Visibility = collectionOptions.contains(.applicationOnlyMask) ? .process : .user
        let existing = NSFontCollection(name: name) ?? NSFontCollection(descriptors: [])
        do { try NSFontCollection.show(existing, withName: name, visibility: visibility) } catch { return false }
        return true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/addfontdescriptors(_:tocollection:)
    open func addFontDescriptors(_ descriptors: [Any], toCollection collectionName: String) {
        let name = NSFontCollection.Name(collectionName)
        let c = (NSFontCollection(name: name)?.mutableCopy() as? NSMutableFontCollection) ?? NSMutableFontCollection(descriptors: [])
        c.addQuery(for: descriptors.compactMap { $0 as? NSFontDescriptor })
        try? NSFontCollection.show(c, withName: name, visibility: .user)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/addfonttrait(_:)
    open func addFontTrait(_ sender: Any?) {
        _pendingTrait = NSFontTraitMask(rawValue: UInt(max(0, NSFontManager._tag(of: sender))))
        _currentAction = .addTraitFontAction
        _ = sendAction()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/availablefontfamilies
    open var availableFontFamilies: [String] {
        if let c = NSFontManager._familyCache { return c }
        #if canImport(CoreText)
        let names = (CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []
        #else
        let names: [String] = []
        #endif
        // Apple's hidden system families (".SF NS Text", ".AppleSystemUIFont") stay out, as in AppKit.
        let visible = names.filter { !$0.hasPrefix(".") }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        NSFontManager._familyCache = visible
        return visible
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/availablefontnames(matching:)
    open func availableFontNames(matching descriptor: NSFontDescriptor) -> [Any]? {
        let names = descriptor.matchingFontDescriptors(withMandatoryKeys: Set(descriptor.fontAttributes.keys)).compactMap { $0.postscriptName }
        return names.isEmpty ? nil : names
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/availablefontnames(with:)
    open func availableFontNames(with someTraits: NSFontTraitMask) -> [String]? {
        var out: [String] = []
        for family in availableFontFamilies {
            for member in availableMembers(ofFontFamily: family) ?? [] {
                guard let name = member[0] as? String, let raw = member[3] as? UInt else { continue }
                let traits = NSFontTraitMask(rawValue: raw)
                let wanted = someTraits.subtracting([.unboldFontMask, .unitalicFontMask])
                if traits.isSuperset(of: wanted),
                   !(someTraits.contains(.unboldFontMask) && traits.contains(.boldFontMask)),
                   !(someTraits.contains(.unitalicFontMask) && traits.contains(.italicFontMask)) { out.append(name) }
            }
        }
        return out
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/availablefonts
    open var availableFonts: [String] {
        availableFontFamilies.flatMap { (availableMembers(ofFontFamily: $0) ?? []).compactMap { $0.first as? String } }
    }
    /// The family's faces as `[postScriptName, styleName, weight (0...15), traits]`, as AppKit.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/availablemembers(offontfamily:)
    open func availableMembers(ofFontFamily fam: String) -> [[Any]]? {
        if let c = NSFontManager._memberCache[fam] { return c.isEmpty ? nil : c }
        let faces = NSFontDescriptor(fontAttributes: [.family: fam]).matchingFontDescriptors(withMandatoryKeys: [.family])
        var out: [[Any]] = []
        for d in faces {
            guard let name = d.postscriptName else { continue }
            let sym = d.symbolicTraits
            let weightValue = NSFontDescriptor._number(d._traits[.weight]) ?? (sym.contains(.bold) ? 0.4 : 0)
            var traits: NSFontTraitMask = []
            if sym.contains(.italic) { traits.insert(.italicFontMask) }
            if sym.contains(.bold) || weightValue >= Double(NSFont.Weight.semibold.rawValue) { traits.insert(.boldFontMask) }
            if sym.contains(.monoSpace) { traits.insert(.fixedPitchFontMask) }
            if sym.contains(.condensed) { traits.insert(.condensedFontMask) }
            if sym.contains(.expanded) { traits.insert(.expandedFontMask) }
            let weight = max(0, min(15, Int((weightValue * 10).rounded()) + 5))
            let style = (d.object(forKey: .face) as? String) ?? NSFontManager._styleName(traits: traits)
            out.append([name, style, weight, traits.rawValue])
        }
        out.sort { a, b in
            let ta = NSFontTraitMask(rawValue: a[3] as? UInt ?? 0), tb = NSFontTraitMask(rawValue: b[3] as? UInt ?? 0)
            if ta.contains(.italicFontMask) != tb.contains(.italicFontMask) { return !ta.contains(.italicFontMask) }
            let wa = a[2] as? Int ?? 5, wb = b[2] as? Int ?? 5
            if wa != wb { return abs(wa - 5) < abs(wb - 5) || (abs(wa - 5) == abs(wb - 5) && wa < wb) }
            return (a[1] as? String ?? "") < (b[1] as? String ?? "")
        }
        NSFontManager._memberCache[fam] = out
        return out.isEmpty ? nil : out
    }
    private static func _styleName(traits: NSFontTraitMask) -> String {
        switch (traits.contains(.boldFontMask), traits.contains(.italicFontMask)) {
        case (true, true): return "Bold Italic"
        case (true, false): return "Bold"
        case (false, true): return "Italic"
        case (false, false): return "Regular"
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/collectionnames
    open var collectionNames: [Any] { NSFontCollection.allFontCollectionNames.map { $0.rawValue } }
    /// The font the current action turns `fontObj` into: the panel's choice, a trait added
    /// or removed, a size or weight step.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/convert(_:)
    open func convert(_ fontObj: NSFont) -> NSFont {
        switch _currentAction {
        case .viaPanelFontAction:
            return MainActor.assumeIsolated { fontPanel(false)?.convert(fontObj) ?? fontObj }
        case .addTraitFontAction: return convert(fontObj, toHaveTrait: _pendingTrait)
        case .removeTraitFontAction: return convert(fontObj, toNotHaveTrait: _pendingTrait)
        case .sizeUpFontAction: return convert(fontObj, toSize: fontObj.pointSize + 1)
        case .sizeDownFontAction: return convert(fontObj, toSize: max(1, fontObj.pointSize - 1))
        case .heavierFontAction: return convertWeight(true, of: fontObj)
        case .lighterFontAction: return convertWeight(false, of: fontObj)
        case .noFontChangeAction: return fontObj
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/convert(_:toface:)
    open func convert(_ fontObj: NSFont, toFace typeface: String) -> NSFont? {
        if fontObj.fontName == typeface || fontObj.handle.postScriptName == typeface { return fontObj }
        return NSFont(name: typeface, size: fontObj.pointSize)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/convert(_:tofamily:)
    open func convert(_ fontObj: NSFont, toFamily family: String) -> NSFont {
        if fontObj.familyName?.lowercased() == family.lowercased() { return fontObj }
        guard let base = NSFont(name: family, size: fontObj.pointSize) else { return fontObj }
        return base._converted(italic: fontObj._isItalic, weight: fontObj._weightValue, monospaced: nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/convert(_:tohavetrait:)
    open func convert(_ fontObj: NSFont, toHaveTrait trait: NSFontTraitMask) -> NSFont {
        var italic: Bool? = nil, weight: CGFloat? = nil, monospaced: Bool? = nil
        if trait.contains(.italicFontMask) { italic = true }
        if trait.contains(.unitalicFontMask) { italic = false }
        if trait.contains(.boldFontMask) { weight = NSFont.Weight.bold.rawValue }
        if trait.contains(.unboldFontMask) { weight = NSFont.Weight.regular.rawValue }
        if trait.contains(.fixedPitchFontMask) { monospaced = true }
        return fontObj._converted(italic: italic, weight: weight, monospaced: monospaced)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/convert(_:tonothavetrait:)
    open func convert(_ fontObj: NSFont, toNotHaveTrait trait: NSFontTraitMask) -> NSFont {
        var italic: Bool? = nil, weight: CGFloat? = nil, monospaced: Bool? = nil
        if trait.contains(.italicFontMask) { italic = false }
        if trait.contains(.boldFontMask) { weight = NSFont.Weight.regular.rawValue }
        if trait.contains(.fixedPitchFontMask) { monospaced = false }
        return fontObj._converted(italic: italic, weight: weight, monospaced: monospaced)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/convert(_:tosize:)
    open func convert(_ fontObj: NSFont, toSize size: CGFloat) -> NSFont { fontObj.pointSize == size ? fontObj : fontObj.withSize(size) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/convertattributes(_:)
    open func convertAttributes(_ attributes: [String : Any] = [:]) -> [String : Any] {
        var out = attributes
        if let f = attributes[NSAttributedString.Key.font.rawValue] as? NSFont { out[NSAttributedString.Key.font.rawValue] = convert(f) }
        return out
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/convertfonttraits(_:)
    open func convertFontTraits(_ traits: NSFontTraitMask) -> NSFontTraitMask {
        switch _currentAction {
        case .addTraitFontAction: return traits.union(_pendingTrait)
        case .removeTraitFontAction: return traits.subtracting(_pendingTrait)
        default: return traits
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/convertweight(_:of:)
    open func convertWeight(_ upFlag: Bool, of fontObj: NSFont) -> NSFont {
        // AppKit's 0...15 scale: regular is 5, bold 9; one step is a tenth of NSFont.Weight.
        fontObj._converted(italic: nil, weight: max(-1, min(1, fontObj._weightValue + (upFlag ? 0.1 : -0.1))), monospaced: nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/currentfontaction
    open var currentFontAction: NSFontAction { _currentAction }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/delegate
    open var delegate: AnyObject? {
        get { _delegate }
        set { _delegate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/font(withfamily:traits:weight:size:)
    open func font(withFamily family: String, traits: NSFontTraitMask, weight: Int, size: CGFloat) -> NSFont? {
        guard let f = NSFont(name: family, size: size) else { return nil }
        return f._converted(italic: traits.contains(.italicFontMask), weight: CGFloat(weight - 5) / 10, monospaced: traits.contains(.fixedPitchFontMask) ? true : nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/fontdescriptors(incollection:)
    open func fontDescriptors(inCollection collectionNames: String) -> [Any]? {
        NSFontCollection(name: NSFontCollection.Name(collectionNames))?.queryDescriptors
    }
    /// The Font menu (Show Fonts, Bold, Italic, Underline, Bigger, Smaller), created on demand.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/fontmenu(_:)
    open func fontMenu(_ create: Bool) -> NSMenu? {
        if let m = _fontMenu { return m }
        guard create else { return nil }
        return MainActor.assumeIsolated {
            let menu = NSMenu(title: "Font")
            @MainActor func item(_ title: String, _ action: String, key: String = "", tag: Int = 0, modifiers: NSEvent.ModifierFlags = [.command]) {
                let i = NSMenuItem(title: title, action: Selector((action)), keyEquivalent: key)
                i.keyEquivalentModifierMask = modifiers
                i.target = self
                i.tag = tag
                menu.addItem(i)
            }
            item("Show Fonts", "orderFrontFontPanel:", key: "t")
            item("Bold", "addFontTrait:", key: "b", tag: Int(NSFontTraitMask.boldFontMask.rawValue))
            item("Italic", "addFontTrait:", key: "i", tag: Int(NSFontTraitMask.italicFontMask.rawValue))
            item("Underline", "underline:", key: "u")
            menu.addItem(NSMenuItem.separator())
            item("Bigger", "modifyFont:", key: "+", tag: NSFontAction.sizeUpFontAction.rawValue)
            item("Smaller", "modifyFont:", key: "-", tag: NSFontAction.sizeDownFontAction.rawValue)
            _fontMenu = menu
            return menu
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/fontnamed(_:hastraits:)
    open func fontNamed(_ fName: String, hasTraits someTraits: NSFontTraitMask) -> Bool {
        guard let f = NSFont(name: fName, size: NSFont.systemFontSize) else { return false }
        return traits(of: f).isSuperset(of: someTraits)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/fontpanel(_:)
    open func fontPanel(_ create: Bool) -> NSFontPanel? {
        MainActor.assumeIsolated {
            if NSFontPanel.sharedFontPanelExists || create { return NSFontPanel.shared }
            return nil
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/isenabled
    open var isEnabled: Bool {
        get { _isEnabled }
        set {
            _isEnabled = newValue
            MainActor.assumeIsolated { fontPanel(false)?.isEnabled = newValue }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/ismultiple
    open var isMultiple: Bool { _isMultiple }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/localizedname(forfamily:face:)
    open func localizedName(forFamily family: String, face faceKey: String?) -> String {
        guard let face = faceKey, !face.isEmpty else { return family }
        return "\(family) \(face)"
    }
    /// The menu's size and weight commands: the sender's tag is an `NSFontAction`.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/modifyfont(_:)
    open func modifyFont(_ sender: Any?) {
        _currentAction = NSFontAction(rawValue: NSFontManager._tag(of: sender)) ?? .noFontChangeAction
        _ = sendAction()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/modifyfontviapanel(_:)
    open func modifyFontViaPanel(_ sender: Any?) {
        _currentAction = .viaPanelFontAction
        _ = sendAction()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/orderfrontfontpanel(_:)
    open func orderFrontFontPanel(_ sender: Any?) {
        MainActor.assumeIsolated {
            guard let panel = fontPanel(true) else { return }
            panel._refreshValidModes()
            if let f = _selectedFont { panel.setPanelFont(f, isMultiple: _isMultiple) }
            panel.isEnabled = _isEnabled
            panel.orderFront(sender)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/orderfrontstylespanel(_:)
    open func orderFrontStylesPanel(_ sender: Any?) { orderFrontFontPanel(sender) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/removecollection(_:)
    open func removeCollection(_ collectionName: String) -> Bool {
        let name = NSFontCollection.Name(collectionName)
        var stored = NSFontCollection._stored
        guard stored[name.rawValue] != nil else { return false }
        stored[name.rawValue] = nil
        NSFontCollection._stored = stored
        return true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/removefontdescriptor(_:fromcollection:)
    open func removeFontDescriptor(_ descriptor: NSFontDescriptor, fromCollection collection: String) {
        let name = NSFontCollection.Name(collection)
        guard let c = NSFontCollection(name: name)?.mutableCopy() as? NSMutableFontCollection else { return }
        c.removeQuery(for: [descriptor])
        try? NSFontCollection.show(c, withName: name, visibility: .user)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/removefonttrait(_:)
    open func removeFontTrait(_ sender: Any?) {
        _pendingTrait = NSFontTraitMask(rawValue: UInt(max(0, NSFontManager._tag(of: sender))))
        _currentAction = .removeTraitFontAction
        _ = sendAction()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/selectedfont
    open var selectedFont: NSFont? { _selectedFont }
    /// Sends `changeFont:` (or the action set) to the target, or with no target through the
    /// responder chain, with the manager as the sender.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/sendaction()
    open func sendAction() -> Bool {
        guard _isEnabled else { _NSPanelTrace.log("NSFontManager.sendAction: disabled"); return false }
        return MainActor.assumeIsolated {
            let app = NSApplication.shared
            if _NSPanelTrace.enabled {
                @MainActor func describe(_ w: NSWindow?) -> String { w.map { "'\($0.title)' first responder \(type(of: $0.firstResponder ?? $0))" } ?? "nil" }
                _NSPanelTrace.log("NSFontManager.sendAction \(NSStringFromSelector(_action)) action=\(_currentAction) target=\(_target.map { String(describing: type(of: $0)) } ?? "nil") key=\(describe(app.keyWindow)) main=\(describe(app.mainWindow))")
            }
            let sent = app.sendAction(_action, to: _target, from: self)
            _NSPanelTrace.log("NSFontManager.sendAction -> \(sent)")
            return sent
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/setfontmanagerfactory(_:)
    public class func setFontManagerFactory(_ factoryId: AnyClass?) { _factory = factoryId }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/setfontmenu(_:)
    open func setFontMenu(_ newMenu: NSMenu) { _fontMenu = newMenu }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/setfontpanelfactory(_:)
    public class func setFontPanelFactory(_ factoryId: AnyClass?) { _fontPanelFactory = factoryId }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/setselectedattributes(_:ismultiple:)
    open func setSelectedAttributes(_ attributes: [String : Any], isMultiple flag: Bool) {
        _selectedAttributes = attributes
        if let f = attributes[NSAttributedString.Key.font.rawValue] as? NSFont { setSelectedFont(f, isMultiple: flag) }
    }
    /// The font of the selection the panel should show (a text view reports it as the
    /// selection moves); the panel follows when it exists.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/setselectedfont(_:ismultiple:)
    open func setSelectedFont(_ fontObj: NSFont, isMultiple flag: Bool) {
        _selectedFont = fontObj
        _isMultiple = flag
        MainActor.assumeIsolated { fontPanel(false)?.setPanelFont(fontObj, isMultiple: flag) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/shared
    class public var shared: NSFontManager { _shared }
    nonisolated(unsafe) private static let _shared = NSFontManager()
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/target
    open var target: AnyObject? {
        get { _target }
        set { _target = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/traits(of:)
    open func traits(of fontObj: NSFont) -> NSFontTraitMask {
        var t: NSFontTraitMask = []
        if fontObj._isItalic { t.insert(.italicFontMask) }
        if fontObj._weightValue >= NSFont.Weight.semibold.rawValue { t.insert(.boldFontMask) }
        if fontObj.isFixedPitch { t.insert(.fixedPitchFontMask) }
        return t
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/weight(of:)
    open func weight(of fontObj: NSFont) -> Int { max(0, min(15, Int((fontObj._weightValue * 10).rounded()) + 5)) }

    /// Bold/Italic items reflect the selected font; everything else is enabled while a
    /// responder handles `changeFont:`.
    @MainActor public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if let a = menuItem.action, NSStringFromSelector(a) == "addFontTrait:", let f = _selectedFont {
            let t = NSFontTraitMask(rawValue: UInt(max(0, menuItem.tag)))
            menuItem.state = traits(of: f).isSuperset(of: t) ? .on : .off
        }
        if let a = menuItem.action, NSStringFromSelector(a) == "orderFrontFontPanel:" { return true }
        return _fontChangingResponder() != nil
    }

    private static func _tag(of sender: Any?) -> Int {
        MainActor.assumeIsolated {
            if let i = sender as? NSMenuItem { return i.tag }
            if let c = sender as? NSControl { return c.tag }
            return 0
        }
    }
}

extension NSFontManager: NSSelectorHandling {
    /// The Font menu's items target the manager by selector.
    public func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch NSStringFromSelector(action) {
        case "orderFrontFontPanel:": orderFrontFontPanel(sender)
        case "orderFrontStylesPanel:": orderFrontStylesPanel(sender)
        case "addFontTrait:": addFontTrait(sender)
        case "removeFontTrait:": removeFontTrait(sender)
        case "modifyFont:": modifyFont(sender)
        case "modifyFontViaPanel:": modifyFontViaPanel(sender)
        default: return false
        }
        return true
    }
    public func respondsToSelectorAction(_ action: Selector) -> Bool {
        ["orderFrontFontPanel:", "orderFrontStylesPanel:", "addFontTrait:", "removeFontTrait:", "modifyFont:", "modifyFontViaPanel:"].contains(NSStringFromSelector(action))
    }
}

/// `APPKITWIN_TRACE_PANELS=1`: the panels' action path on stderr (which window is key and
/// main, who receives `changeFont:`/`changeColor:`, what changed), for the Windows PC.
internal enum _NSPanelTrace {
    nonisolated(unsafe) static let enabled = ProcessInfo.processInfo.environment["APPKITWIN_TRACE_PANELS"] == "1"
    static func log(_ message: @autoclosure () -> String) { if enabled { fputs("[panels] \(message())\n", stderr) } }
}
