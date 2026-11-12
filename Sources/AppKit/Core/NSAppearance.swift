// NSAppearance (hand-written; seeded from the generated stub, see tools/apigen)
// Light and dark appearances. Views, windows and the application resolve an effective
// appearance by inheritance; while a view draws, its effective appearance is the current
// drawing appearance and semantic NSColors resolve to its light or dark values.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsappearance
open class NSAppearance: NSObject, NSSecureCoding, NSCoding {
    public let name: NSAppearance.Name

    private static let darkNames: Set<String> = [
        NSAppearance.Name.darkAqua.rawValue, NSAppearance.Name.vibrantDark.rawValue,
        NSAppearance.Name.accessibilityHighContrastDarkAqua.rawValue, NSAppearance.Name.accessibilityHighContrastVibrantDark.rawValue,
    ]
    private static let knownNames: Set<String> = darkNames.union([
        NSAppearance.Name.aqua.rawValue, NSAppearance.Name.vibrantLight.rawValue, NSAppearance.Name.lightContent.rawValue,
        NSAppearance.Name.accessibilityHighContrastAqua.rawValue, NSAppearance.Name.accessibilityHighContrastVibrantLight.rawValue,
    ])

    /// Whether this is a dark appearance (semantic colours use their dark values).
    public var isDark: Bool { NSAppearance.darkNames.contains(name.rawValue) }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsappearance/init(named:)
    public init?(named name: NSAppearance.Name) {
        guard NSAppearance.knownNames.contains(name.rawValue) else { return nil }
        self.name = name
        super.init()
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsappearance/init(appearancenamed:bundle:)
    public convenience init?(appearanceNamed name: NSAppearance.Name, bundle: Bundle?) { self.init(named: name) }

    public required init?(coder: NSCoder) { return nil }
    open func encode(with coder: NSCoder) {}
    class public var supportsSecureCoding: Bool { true }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsappearance/allowsvibrancy
    open var allowsVibrancy: Bool { name == .vibrantLight || name == .vibrantDark }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsappearance/bestmatch(from:)
    open func bestMatch(from appearances: [NSAppearance.Name]) -> NSAppearance.Name? {
        if appearances.contains(name) { return name }
        let order: [NSAppearance.Name] = isDark
            ? [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark, .aqua, .vibrantLight]
            : [.aqua, .vibrantLight, .accessibilityHighContrastAqua, .accessibilityHighContrastVibrantLight, .darkAqua, .vibrantDark]
        return order.first { appearances.contains($0) } ?? appearances.first
    }

    nonisolated(unsafe) private static var _current: NSAppearance? = nil

    /// The appearance used for drawing on the current thread (set while a view draws).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsappearance/current
    class public var current: NSAppearance! {
        get { _current ?? NSAppearance(named: .aqua)! }
        set { _current = newValue }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsappearance/currentdrawing()
    public class func currentDrawing() -> NSAppearance { current }

    /// True while a dark appearance is current (read by NSColor on every resolution).
    static var currentIsDark: Bool { _current?.isDark ?? false }
    /// The appearance pages are printed under (aqua), see `NSView._drawingAppearance`.
    nonisolated(unsafe) static let _printing: NSAppearance = NSAppearance(named: .aqua)!

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsappearance/performascurrentdrawingappearance(_:)
    open func performAsCurrentDrawingAppearance(_ block: () -> Void) {
        let previous = NSAppearance._current
        NSAppearance._current = self
        defer { NSAppearance._current = previous }
        block()
    }

    open override func isEqual(_ object: Any?) -> Bool { (object as? NSAppearance)?.name == name }
    open override var hash: Int { name.rawValue.hashValue }
    open override var description: String { "<NSAppearance \(name.rawValue)>" }
}
