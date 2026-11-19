// Foundation's localized-string API that swift-corelibs-foundation lacks: `String(localized:)`,
// `String.LocalizationValue` and `LocalizedStringResource` (ADR-0045). Declared on Windows and
// Linux only (macOS apps get Apple's) and visible through `import AppKit`, `Cocoa` or `SwiftUI`;
// a file that imports only Foundation does not see them.
//
// A localization value is a key in Apple's format: the literal text with each interpolation
// replaced by its format specifier (`%@` for strings and objects, `%lld` for Int, `%lf` for
// Double, ...), so `String(localized: "\(count) files")` looks up `"%lld files"` (the key
// Xcode extracts) and formats the result, `.stringsdict` plurals included, with the values.

import Foundation

/// A localization key with its arguments, as `String.LocalizationValue` and SwiftUI's
/// `LocalizedStringKey` build it (port only).
public struct _LocalizationKey: @unchecked Sendable, Equatable {
    /// The key: literals with `%` doubled and interpolations as format specifiers.
    public var key = ""
    /// The interpolated values, in order.
    public var arguments: [CVarArg] = []
    /// The text with the values in place: what an untranslated key shows.
    public var fallback = ""

    public init() {}
    public init(_ literal: String) { appendLiteral(literal) }

    public mutating func appendLiteral(_ literal: String) {
        key += literal.replacingOccurrences(of: "%", with: "%%")
        fallback += literal
    }
    public mutating func append(_ argument: CVarArg, specifier: String) {
        key += specifier
        arguments.append(argument)
        fallback += String(format: specifier, argument)
    }

    /// The localized text of the key in a bundle (the main one when nil): the table's entry,
    /// else `defaultValue`'s text, formatted with the arguments.
    public func resolve(table: String?, bundle: Bundle?, locale: Locale?, lookupKey: String? = nil, defaultValue: _LocalizationKey? = nil) -> String {
        _AppBundle.installMainBundle()
        let app = bundle.map(_AppBundle.forBundle) ?? _AppBundle.main
        let wanted = lookupKey ?? key
        let args = defaultValue?.arguments ?? arguments
        if let entry = app.localizedEntry(forKey: wanted, table: table) {
            let language = app.preferredLocalizations.first ?? app.developmentLocalization
            return _PluralFormat.format(entry, language: language, locale: locale, arguments: args)
        }
        return (defaultValue ?? self).fallback
    }

    public static func == (a: _LocalizationKey, b: _LocalizationKey) -> Bool { a.key == b.key && a.fallback == b.fallback }

    /// The format specifier Apple's key extraction uses for a value's type.
    public static func specifier(for value: Any) -> String {
        switch value {
        case is Int, is Int64: return "%lld"
        case is UInt, is UInt64: return "%llu"
        case is Int8, is Int16, is Int32: return "%d"
        case is UInt8, is UInt16, is UInt32: return "%u"
        case is Double, is CGFloat: return "%lf"
        case is Float: return "%f"
        default: return "%@"
        }
    }
}

#if !canImport(Darwin)

extension String {
    /// - SeeAlso: https://developer.apple.com/documentation/swift/string/localizationvalue
    public struct LocalizationValue: Equatable, ExpressibleByStringInterpolation, Sendable, CustomDebugStringConvertible {
        public var _key: _LocalizationKey

        public init(_ value: String) { _key = _LocalizationKey(value) }
        public init(stringLiteral value: String) { _key = _LocalizationKey(value) }
        public init(stringInterpolation: StringInterpolation) { _key = stringInterpolation._key }
        public var debugDescription: String { "LocalizationValue(\(String(reflecting: _key.key)))" }

        /// - SeeAlso: https://developer.apple.com/documentation/swift/string/localizationvalue/stringinterpolation
        public struct StringInterpolation: StringInterpolationProtocol, Sendable {
            public var _key = _LocalizationKey()
            public init(literalCapacity: Int, interpolationCount: Int) {}
            public mutating func appendLiteral(_ literal: String) { _key.appendLiteral(literal) }
            public mutating func appendInterpolation(_ string: String) { _key.append(string, specifier: "%@") }
            public mutating func appendInterpolation<S: StringProtocol>(_ string: S) { _key.append(String(string), specifier: "%@") }
            public mutating func appendInterpolation(_ value: Int) { _key.append(value, specifier: "%lld") }
            public mutating func appendInterpolation(_ value: Int8) { _key.append(Int32(value), specifier: "%d") }
            public mutating func appendInterpolation(_ value: Int16) { _key.append(Int32(value), specifier: "%d") }
            public mutating func appendInterpolation(_ value: Int32) { _key.append(value, specifier: "%d") }
            public mutating func appendInterpolation(_ value: Int64) { _key.append(value, specifier: "%lld") }
            public mutating func appendInterpolation(_ value: UInt) { _key.append(value, specifier: "%llu") }
            public mutating func appendInterpolation(_ value: UInt8) { _key.append(UInt32(value), specifier: "%u") }
            public mutating func appendInterpolation(_ value: UInt16) { _key.append(UInt32(value), specifier: "%u") }
            public mutating func appendInterpolation(_ value: UInt32) { _key.append(value, specifier: "%u") }
            public mutating func appendInterpolation(_ value: UInt64) { _key.append(value, specifier: "%llu") }
            public mutating func appendInterpolation(_ value: Double) { _key.append(value, specifier: "%lf") }
            public mutating func appendInterpolation(_ value: Float) { _key.append(value, specifier: "%f") }
            public mutating func appendInterpolation(_ value: CGFloat) { _key.append(Double(value), specifier: "%lf") }
            /// `"\(value, specifier: "%.2f")"`.
            public mutating func appendInterpolation<T: CVarArg>(_ value: T, specifier: String) { _key.append(value, specifier: specifier) }
            public mutating func appendInterpolation<T: NSObject>(_ object: T) { _key.append(object.description, specifier: "%@") }
            public mutating func appendInterpolation<T: CustomStringConvertible>(_ value: T) { _key.append(value.description, specifier: "%@") }
            public mutating func appendInterpolation<F: FormatStyle>(_ input: F.FormatInput, format: F) where F.FormatOutput == String {
                _key.append(format.format(input), specifier: "%@")
            }
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/swift/string/init(localized:table:bundle:locale:comment:)
    public init(localized keyAndValue: String.LocalizationValue, table: String? = nil, bundle: Bundle? = nil, locale: Locale = .current, comment: StaticString? = nil) {
        self = keyAndValue._key.resolve(table: table, bundle: bundle, locale: locale)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/swift/string/init(localized:defaultvalue:table:bundle:locale:comment:)
    public init(localized key: StaticString, defaultValue: String.LocalizationValue, table: String? = nil, bundle: Bundle? = nil, locale: Locale = .current, comment: StaticString? = nil) {
        self = defaultValue._key.resolve(table: table, bundle: bundle, locale: locale, lookupKey: "\(key)", defaultValue: defaultValue._key)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/swift/string/init(localized:)
    public init(localized resource: LocalizedStringResource) {
        self = resource._resolve()
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/foundation/localizedstringresource
public struct LocalizedStringResource: Equatable, ExpressibleByStringInterpolation, Sendable, CustomStringConvertible {
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/localizedstringresource/bundledescription
    public enum BundleDescription: Sendable, Equatable {
        case main
        case forClass(AnyClass)
        case atURL(URL)
        public static func == (a: BundleDescription, b: BundleDescription) -> Bool {
            switch (a, b) {
            case (.main, .main): return true
            case (.forClass(let x), .forClass(let y)): return x == y
            case (.atURL(let x), .atURL(let y)): return x == y
            default: return false
            }
        }
        var bundle: Bundle? {
            switch self {
            case .main: return nil
            case .forClass(let c): return Bundle(for: c)
            case .atURL(let url): return Bundle(url: url)
            }
        }
    }

    public var key: String
    public var defaultValue: String.LocalizationValue
    public var table: String?
    public var locale: Locale
    public var bundle: BundleDescription
    public var comment: String?

    public init(_ keyAndValue: String.LocalizationValue, table: String? = nil, locale: Locale = .current, bundle: BundleDescription = .main, comment: StaticString? = nil) {
        key = keyAndValue._key.key
        defaultValue = keyAndValue
        self.table = table
        self.locale = locale
        self.bundle = bundle
        self.comment = comment.map { "\($0)" }
    }
    public init(_ key: StaticString, defaultValue: String.LocalizationValue, table: String? = nil, locale: Locale = .current, bundle: BundleDescription = .main, comment: StaticString? = nil) {
        self.key = "\(key)"
        self.defaultValue = defaultValue
        self.table = table
        self.locale = locale
        self.bundle = bundle
        self.comment = comment.map { "\($0)" }
    }
    public init(stringLiteral value: String) { self.init(String.LocalizationValue(value)) }
    public init(stringInterpolation: String.LocalizationValue.StringInterpolation) { self.init(String.LocalizationValue(stringInterpolation: stringInterpolation)) }

    public var description: String { _resolve() }

    func _resolve() -> String {
        defaultValue._key.resolve(table: table, bundle: bundle.bundle, locale: locale, lookupKey: key, defaultValue: defaultValue._key)
    }
}

#endif
