// SwiftUI's AttributedString attributes (font, colours, line styles, kerning) and the
// Text that draws them, as swift-markdown-ui builds its inline text.

import Foundation

extension AttributeScopes {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/attributescopes/swiftuiattributes
    public struct SwiftUIAttributes: AttributeScope {
        public let font: FontAttribute
        public let foregroundColor: ForegroundColorAttribute
        public let backgroundColor: BackgroundColorAttribute
        public let strikethroughStyle: StrikethroughStyleAttribute
        public let underlineStyle: UnderlineStyleAttribute
        public let kern: KerningAttribute
        public let tracking: TrackingAttribute
        public let baselineOffset: BaselineOffsetAttribute
        public let foundation: AttributeScopes.FoundationAttributes

        public enum FontAttribute: AttributedStringKey { public typealias Value = Font; public static let name = "SwiftUI.Font" }
        public enum ForegroundColorAttribute: AttributedStringKey { public typealias Value = Color; public static let name = "SwiftUI.ForegroundColor" }
        public enum BackgroundColorAttribute: AttributedStringKey { public typealias Value = Color; public static let name = "SwiftUI.BackgroundColor" }
        public enum StrikethroughStyleAttribute: AttributedStringKey { public typealias Value = Text.LineStyle; public static let name = "SwiftUI.StrikethroughStyle" }
        public enum UnderlineStyleAttribute: AttributedStringKey { public typealias Value = Text.LineStyle; public static let name = "SwiftUI.UnderlineStyle" }
        public enum KerningAttribute: AttributedStringKey { public typealias Value = CGFloat; public static let name = "SwiftUI.Kern" }
        public enum TrackingAttribute: AttributedStringKey { public typealias Value = CGFloat; public static let name = "SwiftUI.Tracking" }
        public enum BaselineOffsetAttribute: AttributedStringKey { public typealias Value = CGFloat; public static let name = "SwiftUI.BaselineOffset" }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/attributescopes/swiftui
    public var swiftUI: SwiftUIAttributes.Type { SwiftUIAttributes.self }
}

extension AttributeDynamicLookup {
    public subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.SwiftUIAttributes, T>) -> T { self[T.self] }
}

extension Text {
    /// The runs of an attributed string: SwiftUI attributes and Foundation's inline
    /// presentation intents (strong, emphasis, code, strikethrough) become text runs.
    static func _runs(of attributed: AttributedString) -> [Run] {
        #if os(Windows)
        // swift.org's Windows toolchain (6.2) fails to link the `_FoundationCollections`
        // index metadata that run ranges pull in (fine with 6.4): the plain text for now.
        return [Run(string: String(attributed.characters))]
        #else
        return attributed.runs.map { run in
            var r = Run(string: String(attributed[run.range].characters))
            r.font = run.font
            r.color = run.foregroundColor
            r.backgroundColor = run.backgroundColor
            r.underline = run.underlineStyle
            r.strikethrough = run.strikethroughStyle
            r.kerning = run.kern ?? 0
            r.tracking = run.tracking ?? 0
            r.baselineOffset = run.baselineOffset ?? 0
            #if canImport(Darwin)
            // swift-corelibs-foundation does not expose the inline presentation intents yet.
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.stronglyEmphasized) { r.bold = true }
                if intent.contains(.emphasized) { r.italic = true }
                if intent.contains(.strikethrough) { r.strikethrough = r.strikethrough ?? .single }
                if intent.contains(.code) { r.font = (r.font ?? .body).monospaced() }
            }
            #endif
            return r
        }
        #endif
    }
}
