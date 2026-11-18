// NSAccessibilitySearchKey (hand-written; ADR-0037).
//
// The keys are macOS 26 string constants, so the raw-value probe (run on macOS 15) could not
// record them. Their values are the accessibility search-predicate keys macOS has long used
// between assistive technology and apps ("AX<Name>SearchKey", "AXTextStateChangeType",
// "AXTextStateSync"); every one of these strings is present in the macOS 15 system
// libraries, and the NSAccessibility constants name the same keys.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey
public struct NSAccessibilitySearchKey: RawRepresentable, Hashable, Equatable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/anytypesearchkey
    @available(macOS 26.0, *)
    static public var anyTypeSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXAnyTypeSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/articlesearchkey
    @available(macOS 26.0, *)
    static public var articleSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXArticleSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/blockquotesamelevelsearchkey
    @available(macOS 26.0, *)
    static public var blockquoteSameLevelSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXBlockquoteSameLevelSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/blockquotesearchkey
    @available(macOS 26.0, *)
    static public var blockquoteSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXBlockquoteSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/boldfontsearchkey
    @available(macOS 26.0, *)
    static public var boldFontSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXBoldFontSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/buttonsearchkey
    @available(macOS 26.0, *)
    static public var buttonSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXButtonSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/checkboxsearchkey
    @available(macOS 26.0, *)
    static public var checkBoxSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXCheckBoxSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/controlsearchkey
    @available(macOS 26.0, *)
    static public var controlSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXControlSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/differenttypesearchkey
    @available(macOS 26.0, *)
    static public var differentTypeSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXDifferentTypeSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/fontchangesearchkey
    @available(macOS 26.0, *)
    static public var fontChangeSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXFontChangeSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/fontcolorchangesearchkey
    @available(macOS 26.0, *)
    static public var fontColorChangeSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXFontColorChangeSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/framesearchkey
    @available(macOS 26.0, *)
    static public var frameSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXFrameSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/graphicsearchkey
    @available(macOS 26.0, *)
    static public var graphicSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXGraphicSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/headinglevel1searchkey
    @available(macOS 26.0, *)
    static public var headingLevel1SearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXHeadingLevel1SearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/headinglevel2searchkey
    @available(macOS 26.0, *)
    static public var headingLevel2SearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXHeadingLevel2SearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/headinglevel3searchkey
    @available(macOS 26.0, *)
    static public var headingLevel3SearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXHeadingLevel3SearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/headinglevel4searchkey
    @available(macOS 26.0, *)
    static public var headingLevel4SearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXHeadingLevel4SearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/headinglevel5searchkey
    @available(macOS 26.0, *)
    static public var headingLevel5SearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXHeadingLevel5SearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/headinglevel6searchkey
    @available(macOS 26.0, *)
    static public var headingLevel6SearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXHeadingLevel6SearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/headingsamelevelsearchkey
    @available(macOS 26.0, *)
    static public var headingSameLevelSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXHeadingSameLevelSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/headingsearchkey
    @available(macOS 26.0, *)
    static public var headingSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXHeadingSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/italicfontsearchkey
    @available(macOS 26.0, *)
    static public var italicFontSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXItalicFontSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/keyboardfocusablesearchkey
    @available(macOS 26.0, *)
    static public var keyboardFocusableSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXKeyboardFocusableSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/landmarksearchkey
    @available(macOS 26.0, *)
    static public var landmarkSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXLandmarkSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/linksearchkey
    @available(macOS 26.0, *)
    static public var linkSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXLinkSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/listsearchkey
    @available(macOS 26.0, *)
    static public var listSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXListSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/liveregionsearchkey
    @available(macOS 26.0, *)
    static public var liveRegionSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXLiveRegionSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/misspelledwordsearchkey
    @available(macOS 26.0, *)
    static public var misspelledWordSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXMisspelledWordSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/outlinesearchkey
    @available(macOS 26.0, *)
    static public var outlineSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXOutlineSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/plaintextsearchkey
    @available(macOS 26.0, *)
    static public var plainTextSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXPlainTextSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/radiogroupsearchkey
    @available(macOS 26.0, *)
    static public var radioGroupSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXRadioGroupSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/sametypesearchkey
    @available(macOS 26.0, *)
    static public var sameTypeSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXSameTypeSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/statictextsearchkey
    @available(macOS 26.0, *)
    static public var staticTextSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXStaticTextSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/stylechangesearchkey
    @available(macOS 26.0, *)
    static public var styleChangeSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXStyleChangeSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/tablesamelevelsearchkey
    @available(macOS 26.0, *)
    static public var tableSameLevelSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXTableSameLevelSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/tablesearchkey
    @available(macOS 26.0, *)
    static public var tableSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXTableSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/textfieldsearchkey
    @available(macOS 26.0, *)
    static public var textFieldSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXTextFieldSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/textstatechangetypekey
    @available(macOS 26.0, *)
    static public var textStateChangeTypeKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXTextStateChangeType") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/textstatesynckey
    @available(macOS 26.0, *)
    static public var textStateSyncKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXTextStateSync") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/underlinesearchkey
    @available(macOS 26.0, *)
    static public var underlineSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXUnderlineSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/unvisitedlinksearchkey
    @available(macOS 26.0, *)
    static public var unvisitedLinkSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXUnvisitedLinkSearchKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitysearchkey/visitedlinksearchkey
    @available(macOS 26.0, *)
    static public var visitedLinkSearchKey: NSAccessibilitySearchKey { NSAccessibilitySearchKey(rawValue: "AXVisitedLinkSearchKey") }
}
