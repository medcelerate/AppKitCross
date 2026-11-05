// NSFontManager: the shared manager's trait and weight conversions over NSFont (the font
// panel, menus and collections are still stubs). `Font.italic()` in SwiftUI and attributed
// markdown go through `convert(_:toHaveTrait:)`.

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
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/action
    open var action: Selector {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/addcollection(_:options:)
    open func addCollection(_ collectionName: String, options collectionOptions: NSFontCollectionOptions = []) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/addfontdescriptors(_:tocollection:)
    open func addFontDescriptors(_ descriptors: [Any], toCollection collectionName: String) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/addfonttrait(_:)
    open func addFontTrait(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/availablefontfamilies
    open var availableFontFamilies: [String] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/availablefontnames(matching:)
    open func availableFontNames(matching descriptor: NSFontDescriptor) -> [Any]? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/availablefontnames(with:)
    open func availableFontNames(with someTraits: NSFontTraitMask) -> [String]? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/availablefonts
    open var availableFonts: [String] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/availablemembers(offontfamily:)
    open func availableMembers(ofFontFamily fam: String) -> [[Any]]? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/collectionnames
    open var collectionNames: [Any] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/convert(_:)
    open func convert(_ fontObj: NSFont) -> NSFont { fontObj }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/convert(_:toface:)
    open func convert(_ fontObj: NSFont, toFace typeface: String) -> NSFont? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/convert(_:tofamily:)
    open func convert(_ fontObj: NSFont, toFamily family: String) -> NSFont { unimplemented() }
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
    open func convertAttributes(_ attributes: [String : Any] = [:]) -> [String : Any] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/convertfonttraits(_:)
    open func convertFontTraits(_ traits: NSFontTraitMask) -> NSFontTraitMask { traits }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/convertweight(_:of:)
    open func convertWeight(_ upFlag: Bool, of fontObj: NSFont) -> NSFont {
        // AppKit's 0...15 scale: regular is 5, bold 9; one step is a tenth of NSFont.Weight.
        fontObj._converted(italic: nil, weight: max(-1, min(1, fontObj._weightValue + (upFlag ? 0.1 : -0.1))), monospaced: nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/currentfontaction
    open var currentFontAction: NSFontAction { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/delegate
    open var delegate: AnyObject? {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/font(withfamily:traits:weight:size:)
    open func font(withFamily family: String, traits: NSFontTraitMask, weight: Int, size: CGFloat) -> NSFont? {
        guard let f = NSFont(name: family, size: size) else { return nil }
        return f._converted(italic: traits.contains(.italicFontMask), weight: CGFloat(weight - 5) / 10, monospaced: traits.contains(.fixedPitchFontMask) ? true : nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/fontdescriptors(incollection:)
    open func fontDescriptors(inCollection collectionNames: String) -> [Any]? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/fontmenu(_:)
    open func fontMenu(_ create: Bool) -> NSMenu? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/fontnamed(_:hastraits:)
    open func fontNamed(_ fName: String, hasTraits someTraits: NSFontTraitMask) -> Bool {
        guard let f = NSFont(name: fName, size: NSFont.systemFontSize) else { return false }
        return traits(of: f).isSuperset(of: someTraits)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/fontpanel(_:)
    open func fontPanel(_ create: Bool) -> NSFontPanel? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/isenabled
    open var isEnabled: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/ismultiple
    open var isMultiple: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/localizedname(forfamily:face:)
    open func localizedName(forFamily family: String, face faceKey: String?) -> String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/modifyfont(_:)
    open func modifyFont(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/modifyfontviapanel(_:)
    open func modifyFontViaPanel(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/orderfrontfontpanel(_:)
    open func orderFrontFontPanel(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/orderfrontstylespanel(_:)
    open func orderFrontStylesPanel(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/removecollection(_:)
    open func removeCollection(_ collectionName: String) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/removefontdescriptor(_:fromcollection:)
    open func removeFontDescriptor(_ descriptor: NSFontDescriptor, fromCollection collection: String) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/removefonttrait(_:)
    open func removeFontTrait(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/selectedfont
    open var selectedFont: NSFont? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/sendaction()
    open func sendAction() -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/setfontmanagerfactory(_:)
    public class func setFontManagerFactory(_ factoryId: AnyClass?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/setfontmenu(_:)
    open func setFontMenu(_ newMenu: NSMenu) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/setfontpanelfactory(_:)
    public class func setFontPanelFactory(_ factoryId: AnyClass?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/setselectedattributes(_:ismultiple:)
    open func setSelectedAttributes(_ attributes: [String : Any], isMultiple flag: Bool) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/setselectedfont(_:ismultiple:)
    open func setSelectedFont(_ fontObj: NSFont, isMultiple flag: Bool) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/shared
    class public var shared: NSFontManager { _shared }
    nonisolated(unsafe) private static let _shared = NSFontManager()
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontmanager/target
    open var target: AnyObject? {
        get { unimplemented() }
        set { unimplemented() }
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
}
