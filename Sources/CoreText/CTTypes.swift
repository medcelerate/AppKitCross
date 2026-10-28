// CoreText for Windows and Linux (ADR-0007). This file carries the CoreFoundation-shaped
// types the API is expressed in. On these platforms the CF container types are the
// corelibs Foundation classes, so the `as` casts code written for Apple's CoreText uses
// (`name as CFString`, `CTLineGetGlyphRuns(line) as! [CTRun]`) compile unchanged.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public typealias CFIndex = Int
public typealias UniChar = UInt16
public typealias CFTypeRef = AnyObject
public typealias CFString = NSString
public typealias CFArray = NSArray
public typealias CFDictionary = NSDictionary
public typealias CFNumber = NSNumber
public typealias CFAttributedString = NSAttributedString
public typealias CFMutableAttributedString = NSMutableAttributedString
public typealias CFCharacterSet = NSCharacterSet
public typealias CFData = NSData
public typealias CFMutableData = NSMutableData
public typealias CFURL = NSURL
public typealias CFTypeID = UInt

public struct CFRange: Equatable, Sendable {
    public var location: CFIndex
    public var length: CFIndex
    public init() { location = 0; length = 0 }
    public init(location: CFIndex, length: CFIndex) { self.location = location; self.length = length }
}

@inline(__always) public func CFRangeMake(_ loc: CFIndex, _ len: CFIndex) -> CFRange { CFRange(location: loc, length: len) }

extension CFRange {
    var nsRange: NSRange { NSRange(location: location, length: length) }
    init(_ r: NSRange) { self.init(location: r.location, length: r.length) }
}

// MARK: Enumerations (CTLine.h, CTParagraphStyle.h, CTStringAttributes.h, CTFont.h, CTFontTraits.h)

public struct CTLineBoundsOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let excludeTypographicLeading = CTLineBoundsOptions(rawValue: 1 << 0)
    public static let excludeTypographicShifts = CTLineBoundsOptions(rawValue: 1 << 1)
    public static let useHangingPunctuation = CTLineBoundsOptions(rawValue: 1 << 2)
    public static let useGlyphPathBounds = CTLineBoundsOptions(rawValue: 1 << 3)
    public static let useOpticalBounds = CTLineBoundsOptions(rawValue: 1 << 4)
    public static let includeLanguageExtents = CTLineBoundsOptions(rawValue: 1 << 5)
}

public enum CTLineTruncationType: UInt32, Sendable {
    case start = 0, end = 1, middle = 2
}

public enum CTTextAlignment: UInt8, Sendable {
    case left = 0, right = 1, center = 2, justified = 3, natural = 4
}

public enum CTLineBreakMode: UInt8, Sendable {
    case byWordWrapping = 0, byCharWrapping = 1, byClipping = 2, byTruncatingHead = 3, byTruncatingTail = 4, byTruncatingMiddle = 5
}

public enum CTWritingDirection: Int8, Sendable {
    case natural = -1, leftToRight = 0, rightToLeft = 1
}

public enum CTParagraphStyleSpecifier: UInt32, Sendable {
    case alignment = 0, firstLineHeadIndent = 1, headIndent = 2, tailIndent = 3, tabStops = 4, defaultTabInterval = 5,
         lineBreakMode = 6, lineHeightMultiple = 7, maximumLineHeight = 8, minimumLineHeight = 9, lineSpacing = 10,
         paragraphSpacing = 11, paragraphSpacingBefore = 12, baseWritingDirection = 13, maximumLineSpacing = 14,
         minimumLineSpacing = 15, lineSpacingAdjustment = 16, lineBoundsOptions = 17
}

public struct CTUnderlineStyle: OptionSet, Sendable {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }
    public static let single = CTUnderlineStyle(rawValue: 0x01)
    public static let thick = CTUnderlineStyle(rawValue: 0x02)
    public static let double = CTUnderlineStyle(rawValue: 0x09)
}

public struct CTUnderlineStyleModifiers: OptionSet, Sendable {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }
    public static let patternSolid = CTUnderlineStyleModifiers(rawValue: 0x0000)
    public static let patternDot = CTUnderlineStyleModifiers(rawValue: 0x0100)
    public static let patternDash = CTUnderlineStyleModifiers(rawValue: 0x0200)
    public static let patternDashDot = CTUnderlineStyleModifiers(rawValue: 0x0300)
    public static let patternDashDotDot = CTUnderlineStyleModifiers(rawValue: 0x0400)
}

public struct CTFontOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let preventAutoActivation = CTFontOptions(rawValue: 1 << 0)
    public static let preventAutoDownload = CTFontOptions(rawValue: 1 << 1)
    public static let preferSystemFont = CTFontOptions(rawValue: 1 << 2)
}

public enum CTFontUIFontType: UInt32, Sendable {
    case none = 0xFFFF_FFFF, user = 0, userFixedPitch = 1, system = 2, emphasizedSystem = 3, smallSystem = 4,
         smallEmphasizedSystem = 5, miniSystem = 6, miniEmphasizedSystem = 7, views = 8, application = 9, label = 10,
         menuTitle = 11, menuItem = 12, menuItemMark = 13, menuItemCmdKey = 14, windowTitle = 15, pushButton = 16,
         utilityWindowTitle = 17, alertHeader = 18, systemDetail = 19, emphasizedSystemDetail = 20, toolbar = 21,
         smallToolbar = 22, message = 23, palette = 24, toolTip = 25, controlContent = 26
}

public struct CTFontSymbolicTraits: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let traitItalic = CTFontSymbolicTraits(rawValue: 1 << 0)
    public static let traitBold = CTFontSymbolicTraits(rawValue: 1 << 1)
    public static let traitExpanded = CTFontSymbolicTraits(rawValue: 1 << 5)
    public static let traitCondensed = CTFontSymbolicTraits(rawValue: 1 << 6)
    public static let traitMonoSpace = CTFontSymbolicTraits(rawValue: 1 << 10)
    public static let traitVertical = CTFontSymbolicTraits(rawValue: 1 << 11)
    public static let traitUIOptimized = CTFontSymbolicTraits(rawValue: 1 << 12)
    public static let traitColorGlyphs = CTFontSymbolicTraits(rawValue: 1 << 13)
    public static let traitComposite = CTFontSymbolicTraits(rawValue: 1 << 14)
    public static let traitClassMask = CTFontSymbolicTraits(rawValue: 15 << 28)
}

public struct CTFontTableOptions: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let noOptions = CTFontTableOptions([])
}

public typealias CTFontTableTag = UInt32

public enum CTFrameProgression: UInt32, Sendable { case topToBottom = 0, rightToLeft = 1, leftToRight = 2 }
public enum CTFramePathFillRule: UInt32, Sendable { case evenOdd = 0, windingNumber = 1 }

public struct CTRunStatus: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let noStatus = CTRunStatus([])
    public static let rightToLeft = CTRunStatus(rawValue: 1 << 0)
    public static let nonMonotonic = CTRunStatus(rawValue: 1 << 1)
    public static let hasNonIdentityMatrix = CTRunStatus(rawValue: 1 << 2)
}

// MARK: String attribute names (CTStringAttributes.h). Values match Apple's.

public let kCTFontAttributeName: CFString = "NSFont"
public let kCTForegroundColorFromContextAttributeName: CFString = "CTForegroundColorFromContext"
public let kCTKernAttributeName: CFString = "CTKern"
public let kCTTrackingAttributeName: CFString = "CTTracking"
public let kCTLigatureAttributeName: CFString = "CTLigature"
public let kCTForegroundColorAttributeName: CFString = "CTForegroundColor"
public let kCTBackgroundColorAttributeName: CFString = "CTBackgroundColor"
public let kCTParagraphStyleAttributeName: CFString = "CTParagraphStyle"
public let kCTStrokeWidthAttributeName: CFString = "CTStrokeWidth"
public let kCTStrokeColorAttributeName: CFString = "CTStrokeColor"
public let kCTSuperscriptAttributeName: CFString = "CTSuperscript"
public let kCTUnderlineColorAttributeName: CFString = "CTUnderlineColor"
public let kCTUnderlineStyleAttributeName: CFString = "CTUnderlineStyle"
public let kCTVerticalFormsAttributeName: CFString = "CTVerticalForms"
public let kCTHorizontalInVerticalFormsAttributeName: CFString = "CTHorizontalInVerticalForms"
public let kCTGlyphInfoAttributeName: CFString = "CTGlyphInfo"
public let kCTLanguageAttributeName: CFString = "CTLanguage"
public let kCTWritingDirectionAttributeName: CFString = "CTWritingDirection"
public let kCTBaselineOffsetAttributeName: CFString = "CTBaselineOffset"
public let kCTBaselineClassAttributeName: CFString = "CTBaselineClass"
public let kCTBaselineInfoAttributeName: CFString = "CTBaselineInfo"
public let kCTBaselineReferenceInfoAttributeName: CFString = "CTBaselineReferenceInfo"
public let kCTRunDelegateAttributeName: CFString = "CTRunDelegate"
public let kCTRubyAnnotationAttributeName: CFString = "CTRubyAnnotation"
public let kCTCharacterShapeAttributeName: CFString = "CTCharacterShape"
public let kCTAdaptiveImageProviderAttributeName: CFString = "CTAdaptiveImageProvider"

// MARK: Font descriptor attribute names (CTFontDescriptor.h, CTFontTraits.h)

public let kCTFontURLAttribute: CFString = "NSCTFontFileURLAttribute"
public let kCTFontNameAttribute: CFString = "NSFontNameAttribute"
public let kCTFontDisplayNameAttribute: CFString = "NSFontVisibleNameAttribute"
public let kCTFontFamilyNameAttribute: CFString = "NSFontFamilyAttribute"
public let kCTFontStyleNameAttribute: CFString = "NSFontFaceAttribute"
public let kCTFontTraitsAttribute: CFString = "NSCTFontTraitsAttribute"
public let kCTFontVariationAttribute: CFString = "NSCTFontVariationAttribute"
public let kCTFontSizeAttribute: CFString = "NSFontSizeAttribute"
public let kCTFontMatrixAttribute: CFString = "NSCTFontMatrixAttribute"
public let kCTFontCascadeListAttribute: CFString = "NSCTFontCascadeListAttribute"
public let kCTFontCharacterSetAttribute: CFString = "NSCTFontCharacterSetAttribute"
public let kCTFontLanguagesAttribute: CFString = "NSCTFontLanguagesAttribute"
public let kCTFontBaselineAdjustAttribute: CFString = "NSCTFontBaselineAdjustAttribute"
public let kCTFontMacintoshEncodingsAttribute: CFString = "NSCTFontMacintoshEncodingsAttribute"
public let kCTFontFeaturesAttribute: CFString = "NSCTFontFeaturesAttribute"
public let kCTFontFeatureSettingsAttribute: CFString = "NSCTFontFeatureSettingsAttribute"
public let kCTFontFixedAdvanceAttribute: CFString = "NSCTFontFixedAdvanceAttribute"
public let kCTFontOrientationAttribute: CFString = "NSCTFontOrientationAttribute"
public let kCTFontFormatAttribute: CFString = "NSCTFontFormatAttribute"
public let kCTFontRegistrationScopeAttribute: CFString = "NSCTFontRegistrationScopeAttribute"
public let kCTFontPriorityAttribute: CFString = "NSCTFontPriorityAttribute"
public let kCTFontEnabledAttribute: CFString = "NSCTFontEnabledAttribute"
public let kCTFontDownloadableAttribute: CFString = "NSCTFontDownloadableAttribute"
public let kCTFontDownloadedAttribute: CFString = "NSCTFontDownloadedAttribute"

public let kCTFontSymbolicTrait: CFString = "NSCTFontSymbolicTrait"
public let kCTFontWeightTrait: CFString = "NSCTFontWeightTrait"
public let kCTFontWidthTrait: CFString = "NSCTFontWidthTrait"
public let kCTFontSlantTrait: CFString = "NSCTFontSlantTrait"

// MARK: Frame attribute names (CTFrame.h)

public let kCTFrameProgressionAttributeName: CFString = "CTFrameProgression"
public let kCTFramePathFillRuleAttributeName: CFString = "CTFramePathFillRule"
public let kCTFramePathWidthAttributeName: CFString = "CTFramePathWidth"
public let kCTFrameClippingPathsAttributeName: CFString = "CTFrameClippingPaths"
public let kCTFramePathClippingPathAttributeName: CFString = "CTFramePathClippingPath"

// MARK: Font name keys (CTFont.h)

public let kCTFontCopyrightNameKey: CFString = "CTFontCopyrightName"
public let kCTFontFamilyNameKey: CFString = "CTFontFamilyName"
public let kCTFontSubFamilyNameKey: CFString = "CTFontSubFamilyName"
public let kCTFontStyleNameKey: CFString = "CTFontStyleName"
public let kCTFontUniqueNameKey: CFString = "CTFontUniqueName"
public let kCTFontFullNameKey: CFString = "CTFontFullName"
public let kCTFontVersionNameKey: CFString = "CTFontVersionName"
public let kCTFontPostScriptNameKey: CFString = "CTFontPostScriptName"
public let kCTFontTrademarkNameKey: CFString = "CTFontTrademarkName"
public let kCTFontManufacturerNameKey: CFString = "CTFontManufacturerName"
public let kCTFontDesignerNameKey: CFString = "CTFontDesignerName"
public let kCTFontDescriptionNameKey: CFString = "CTFontDescriptionName"
public let kCTFontVendorURLNameKey: CFString = "CTFontVendorURLName"
public let kCTFontDesignerURLNameKey: CFString = "CTFontDesignerURLName"
public let kCTFontLicenseNameKey: CFString = "CTFontLicenseName"
public let kCTFontLicenseURLNameKey: CFString = "CTFontLicenseURLName"
public let kCTFontSampleTextNameKey: CFString = "CTFontSampleTextName"
public let kCTFontPostScriptCIDNameKey: CFString = "CTFontPostScriptCIDName"

/// UTF-16 units of an attributed string's backing store, with helpers shared by the module.
struct CTText {
    let string: NSString
    let units: [UInt16]
    init(_ s: NSString) {
        string = s
        var u = [UInt16](repeating: 0, count: s.length)
        if !u.isEmpty { u.withUnsafeMutableBufferPointer { s.getCharacters($0.baseAddress!, range: NSRange(location: 0, length: s.length)) } }
        units = u
    }
    var count: Int { units.count }
    static func isWhitespace(_ u: UInt16) -> Bool { u == 0x20 || u == 0x09 || u == 0x0A || u == 0x0D || u == 0x2028 || u == 0x2029 || u == 0x00A0 || u == 0x3000 }
    static func isParagraphBreak(_ u: UInt16) -> Bool { u == 0x0A || u == 0x0D || u == 0x2028 || u == 0x2029 || u == 0x0C }
    static func isNewline(_ u: UInt16) -> Bool { isParagraphBreak(u) }
}
