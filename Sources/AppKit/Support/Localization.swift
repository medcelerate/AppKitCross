// Localization for Windows and Linux (ADR-0045): which of a bundle's localizations the user
// wants, the strings tables (`.strings`, `.stringsdict`, String Catalogs), plural rules, and
// the format substitution `.stringsdict` variables need.
//
// swift-corelibs-foundation 6.2 has the API but not the behaviour: its user-language list is
// hard-wired to English off Darwin (CFBundle_Locale.c, "could perhaps read out of LANG"),
// every `.stringsdict` key crashes `Bundle.localizedString` (the CF result is a dictionary the
// Swift bridge reads as a string), `developmentLocalization` traps when the Info.plist has no
// `CFBundleDevelopmentRegion`, and `String(localized:)`, `String.LocalizationValue` and
// `LocalizedStringResource` do not exist. This file is the port's engine; `AppBundle.swift`
// routes `Bundle.main` to it and the end of this file declares the missing Foundation API.

import Foundation

// MARK: - The user's languages

/// The process's language preferences, most preferred first, as BCP 47 tags.
public enum _PreferredLanguages {
    /// `-AppleLanguages "(de, en)"` on the command line (macOS's argument-domain override),
    /// else the operating system's: the user's UI languages on Windows
    /// (`GetUserPreferredUILanguages`), `LANGUAGE`/`LC_ALL`/`LC_MESSAGES`/`LANG` on Linux,
    /// `Locale.preferredLanguages` on macOS.
    public static var current: [String] {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        let value = compute()
        cached = value
        return value
    }
    /// Pins the list (tests); nil goes back to the system's.
    public static func _override(_ languages: [String]?) {
        lock.lock(); cached = languages; lock.unlock()
        _LocalizationTables.flush()
    }

    nonisolated(unsafe) private static var cached: [String]? = nil
    private static let lock = NSLock()

    private static func compute() -> [String] {
        if let fromArguments = appleLanguagesArgument(CommandLine.arguments), !fromArguments.isEmpty { return fromArguments }
        #if os(Windows)
        let system = _win32PreferredUILanguages()
        #elseif canImport(Darwin)
        let system = Locale.preferredLanguages
        #else
        let system = posixLanguages(ProcessInfo.processInfo.environment)
        #endif
        return system.isEmpty ? ["en"] : system
    }

    /// The value of `-AppleLanguages`, written as an old-style plist array (`(de, en)`,
    /// `("de-AT", en)`) or a single tag.
    static func appleLanguagesArgument(_ arguments: [String]) -> [String]? {
        guard let i = arguments.firstIndex(of: "-AppleLanguages"), i + 1 < arguments.count else { return nil }
        var raw = arguments[i + 1].trimmingCharacters(in: .whitespaces)
        if raw.hasPrefix("(") { raw.removeFirst() }
        if raw.hasSuffix(")") { raw.removeLast() }
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'")) }.filter { !$0.isEmpty }.map(bcp47)
    }

    /// gettext's order: `LANGUAGE` (a colon-separated list, honoured unless the locale is
    /// C/POSIX), then the first of `LC_ALL`, `LC_MESSAGES`, `LANG`.
    static func posixLanguages(_ env: [String: String]) -> [String] {
        let locale = [env["LC_ALL"], env["LC_MESSAGES"], env["LANG"]].compactMap { $0 }.first { !$0.isEmpty }
        let isC = locale == nil || locale == "C" || locale == "POSIX" || locale!.hasPrefix("C.")
        var out: [String] = []
        if !isC, let list = env["LANGUAGE"], !list.isEmpty {
            out += list.split(separator: ":").map { bcp47(String($0)) }.filter { !$0.isEmpty }
        }
        if let locale, !isC { out.append(bcp47(locale)) }
        var seen = Set<String>()
        out = out.filter { seen.insert($0.lowercased()).inserted }
        return out.isEmpty ? ["en"] : out
    }

    /// `de_DE.UTF-8@euro` → `de-DE`, `sr_RS@latin` → `sr-Latn-RS`, `zh_TW` → `zh-TW`.
    static func bcp47(_ posix: String) -> String {
        var s = posix
        var script: String? = nil
        if let at = s.firstIndex(of: "@") {
            let modifier = s[s.index(after: at)...].lowercased()
            if modifier == "latin" { script = "Latn" } else if modifier == "cyrillic" { script = "Cyrl" }
            s = String(s[..<at])
        }
        if let dot = s.firstIndex(of: ".") { s = String(s[..<dot]) }
        var parts = s.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        guard !parts.isEmpty else { return "" }
        parts[0] = parts[0].lowercased()
        if let script { parts.insert(script, at: 1) }
        return parts.joined(separator: "-")
    }
}

// MARK: - Choosing a localization

public enum _LocalizationMatching {
    /// Legacy `.lproj` names macOS still accepts.
    private static let legacyNames: [String: String] = [
        "english": "en", "german": "de", "french": "fr", "spanish": "es", "italian": "it", "japanese": "ja",
        "dutch": "nl", "swedish": "sv", "danish": "da", "norwegian": "no", "finnish": "fi", "portuguese": "pt",
        "russian": "ru", "korean": "ko", "chinese": "zh", "polish": "pl", "czech": "cs", "turkish": "tr",
    ]

    /// A localization name in comparable form: lower case, `-` separated, legacy names mapped.
    static func normalized(_ name: String) -> String {
        let s = name.replacingOccurrences(of: "_", with: "-").lowercased()
        return legacyNames[s] ?? s
    }

    /// The localizations to use, best first: the first of `preferences` that one of
    /// `available` serves (exactly, then by its language with the region or script dropped,
    /// then a regional variant of the language), else the development localization, else
    /// `Base`, else the first available. One element, as `Bundle.preferredLocalizations`
    /// answers on macOS.
    public static func preferred(from available: [String], preferences: [String], development: String?) -> [String] {
        let usable = available.filter { $0 != "Base" }
        let byName = Dictionary(usable.map { (normalized($0), $0) }, uniquingKeysWith: { a, _ in a })
        for pref in preferences {
            let p = normalized(pref)
            if let exact = byName[p] { return [exact] }
            var parts = p.split(separator: "-").map(String.init)
            while parts.count > 1 {
                parts.removeLast()
                if let hit = byName[parts.joined(separator: "-")] { return [hit] }
            }
            if let lang = parts.first, let variant = usable.first(where: { normalized($0).hasPrefix(lang + "-") }) { return [variant] }
        }
        if let development, let hit = byName[normalized(development)] { return [hit] }
        if available.contains("Base") { return ["Base"] }
        if let development, available.isEmpty { return [development] }
        return usable.first.map { [$0] } ?? []
    }
}

// MARK: - Tables

/// One entry of a strings table.
public enum _LocalizedEntry: Equatable {
    case string(String)
    /// A `.stringsdict` entry (or a String Catalog plural): the format with `%#@name@`
    /// variables and each variable's rule dictionary (`NSStringFormatSpecTypeKey`,
    /// `NSStringFormatValueTypeKey`, and the plural categories).
    case plural(format: String, variables: [String: [String: String]])

    /// The text when no arguments are at hand (`Bundle.localizedString`): variables take
    /// their `other` form and conversions stay sequential (corelibs' `String(format:)`
    /// mishandles explicit positions, and the caller formats this).
    public var unformatted: String {
        switch self {
        case .string(let s): return s
        case .plural(let format, let variables):
            return _PluralFormat.substitute(format, variables: variables, positional: false) { _ in ("other", false) }
        }
    }
}

/// Parsed tables, cached by file.
enum _LocalizationTables {
    nonisolated(unsafe) private static var cache: [String: [String: _LocalizedEntry]] = [:]
    nonisolated(unsafe) private static var catalogs: [String: [String: Any]] = [:]
    private static let lock = NSRecursiveLock()

    static func flush() { lock.lock(); cache = [:]; catalogs = [:]; lock.unlock() }

    /// The table `name` of localization `localization` across the roots: `.strings`, then
    /// `.stringsdict` (which wins for the keys it has), then a String Catalog
    /// (`<name>.xcstrings`, uncompiled, as SwiftPM copies it off macOS) at a root.
    static func table(_ name: String, localization: String, roots: [URL], sourceLanguage: String?) -> [String: _LocalizedEntry] {
        let key = roots.map(\.path).joined(separator: "|") + "#" + localization + "#" + name
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        var out: [String: _LocalizedEntry] = [:]
        for root in roots.reversed() {   // earlier roots win
            if let catalog = catalog(root.appendingPathComponent(name + ".xcstrings")) {
                for (k, v) in entries(fromCatalog: catalog, localization: localization, sourceLanguage: sourceLanguage) { out[k] = v }
            }
            let lproj = root.appendingPathComponent(localization + ".lproj", isDirectory: true)
            if let data = FileManager.default.contents(atPath: lproj.appendingPathComponent(name + ".strings").path),
               let strings = _StringsFile.parse(data) {
                for (k, v) in strings { out[k] = .string(v) }
            }
            if let data = FileManager.default.contents(atPath: lproj.appendingPathComponent(name + ".stringsdict").path),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                for (k, v) in plist {
                    guard let rule = v as? [String: Any], let format = rule["NSStringLocalizedFormatKey"] as? String else { continue }
                    var variables: [String: [String: String]] = [:]
                    for (vk, vv) in rule where vk != "NSStringLocalizedFormatKey" {
                        if let dict = vv as? [String: Any] { variables[vk] = dict.compactMapValues { $0 as? String } }
                    }
                    out[k] = .plural(format: format, variables: variables)
                }
            }
        }
        cache[key] = out
        return out
    }

    private static func catalog(_ url: URL) -> [String: Any]? {
        if let hit = catalogs[url.path] { return hit }
        guard let data = FileManager.default.contents(atPath: url.path),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        catalogs[url.path] = json
        return json
    }

    /// A String Catalog's entries for one localization: the string unit, or its plural
    /// variations as a one-variable plural rule over the first argument. Keys without a
    /// unit for the localization are left out (so the lookup falls back), except in the
    /// catalog's source language, where the key is its own value.
    static func entries(fromCatalog catalog: [String: Any], localization: String, sourceLanguage: String?) -> [String: _LocalizedEntry] {
        guard let strings = catalog["strings"] as? [String: Any] else { return [:] }
        let source = (catalog["sourceLanguage"] as? String) ?? sourceLanguage ?? "en"
        let isSource = _LocalizationMatching.normalized(source) == _LocalizationMatching.normalized(localization)
        var out: [String: _LocalizedEntry] = [:]
        for (key, value) in strings {
            let locs = ((value as? [String: Any])?["localizations"] as? [String: Any]) ?? [:]
            let loc = locs.first { _LocalizationMatching.normalized($0.key) == _LocalizationMatching.normalized(localization) }?.value as? [String: Any]
            if let loc, let entry = catalogEntry(loc) { out[key] = entry }
            else if isSource { out[key] = .string(key) }
        }
        return out
    }

    private static func catalogEntry(_ loc: [String: Any]) -> _LocalizedEntry? {
        if let unit = loc["stringUnit"] as? [String: Any], let value = unit["value"] as? String { return .string(value) }
        guard let variations = loc["variations"] as? [String: Any] else { return nil }
        if let plural = variations["plural"] as? [String: Any] {
            var rule: [String: String] = ["NSStringFormatSpecTypeKey": "NSStringPluralRuleType"]
            for (category, v) in plural {
                if let value = ((v as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String { rule[category] = value }
            }
            return .plural(format: "%#@__plural@", variables: ["__plural": rule])
        }
        if let device = variations["device"] as? [String: Any] {
            let pick = (device["mac"] ?? device["other"]) as? [String: Any]
            return pick.flatMap(catalogEntry)
        }
        return nil
    }
}

/// The `.strings` file format: `"key" = "value";` pairs, `/* */` and `//` comments,
/// `\n \t \" \\ \Uxxxx` escapes, unquoted words, and `"key";` (the key as its value), in
/// UTF-8 or UTF-16 with a byte order mark. Also accepts a property list (binary or XML)
/// whose root is a dictionary of strings, as Xcode can emit.
enum _StringsFile {
    static func parse(_ data: Data) -> [String: String]? {
        if data.starts(with: Array("bplist".utf8)) || data.starts(with: Array("<?xml".utf8)) {
            return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: String]
        }
        let text: String?
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) { text = String(data: data, encoding: .utf16) }
        else if data.starts(with: [0xEF, 0xBB, 0xBF]) { text = String(decoding: data.dropFirst(3), as: UTF8.self) }
        else { text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) }
        guard let text else { return nil }
        return parse(text)
    }

    static func parse(_ text: String) -> [String: String]? {
        let chars = Array(text.unicodeScalars)
        var i = 0
        var out: [String: String] = [:]
        func skipSpace() {
            while i < chars.count {
                let c = chars[i]
                if c == " " || c == "\t" || c == "\n" || c == "\r" || c == "\u{FEFF}" { i += 1; continue }
                if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                    i += 2
                    while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                    i = min(i + 2, chars.count); continue
                }
                if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                    while i < chars.count, chars[i] != "\n" { i += 1 }
                    continue
                }
                break
            }
        }
        func token() -> String? {
            guard i < chars.count else { return nil }
            if chars[i] == "\"" {
                i += 1
                var s = String.UnicodeScalarView()
                while i < chars.count, chars[i] != "\"" {
                    if chars[i] == "\\", i + 1 < chars.count {
                        i += 1
                        let e = chars[i]
                        switch e {
                        case "n": s.append("\n")
                        case "t": s.append("\t")
                        case "r": s.append("\r")
                        case "\"": s.append("\"")
                        case "\\": s.append("\\")
                        case "U", "u":
                            var hex = ""
                            while hex.count < 4, i + 1 < chars.count, chars[i + 1].properties.isASCIIHexDigit { i += 1; hex.unicodeScalars.append(chars[i]) }
                            if let v = UInt32(hex, radix: 16), let u = Unicode.Scalar(v) { s.append(u) }
                        default:
                            if ("0"..."7").contains(e) {   // octal \ooo
                                var oct = String(e)
                                while oct.count < 3, i + 1 < chars.count, ("0"..."7").contains(chars[i + 1]) { i += 1; oct.unicodeScalars.append(chars[i]) }
                                if let v = UInt32(oct, radix: 8), let u = Unicode.Scalar(v) { s.append(u) }
                            } else { s.append(e) }
                        }
                    } else { s.append(chars[i]) }
                    i += 1
                }
                guard i < chars.count else { return nil }
                i += 1
                return String(s)
            }
            var s = String.UnicodeScalarView()
            while i < chars.count {
                let c = chars[i]
                if c.properties.isAlphabetic || c.properties.numericType != nil || "_$:./-".unicodeScalars.contains(c) { s.append(c); i += 1 } else { break }
            }
            return s.isEmpty ? nil : String(s)
        }
        skipSpace()
        if i < chars.count, chars[i] == "{" { i += 1 }   // a dictionary written with braces
        while true {
            skipSpace()
            if i >= chars.count || chars[i] == "}" { break }
            guard let key = token() else { return out.isEmpty ? nil : out }
            skipSpace()
            if i < chars.count, chars[i] == ";" { i += 1; out[key] = key; continue }
            guard i < chars.count, chars[i] == "=" else { return out.isEmpty ? nil : out }
            i += 1
            skipSpace()
            guard let value = token() else { return out.isEmpty ? nil : out }
            out[key] = value
            skipSpace()
            if i < chars.count, chars[i] == ";" { i += 1 }
        }
        return out
    }
}

// MARK: - Plurals

/// CLDR cardinal plural categories.
public enum _PluralRules {
    /// The category (`zero`, `one`, `two`, `few`, `many`, `other`) of `value` in `language`.
    public static func category(of value: Double, language: String) -> String {
        let lang = _LocalizationMatching.normalized(language).split(separator: "-").first.map(String.init) ?? "en"
        let n = abs(value)
        let isInteger = n.rounded() == n && n < 1e15
        let i = isInteger ? Int(n) : Int(n.rounded(.towardZero))
        let v = isInteger ? 0 : 1   // visible fraction digits (only zero / non-zero matters here)
        let i10 = i % 10, i100 = i % 100
        switch lang {
        case "ja", "zh", "ko", "vi", "th", "id", "ms", "lo", "my", "km", "yue", "jv", "su", "bo", "dz", "ig", "yo", "sah", "to", "wo":
            return "other"
        case "fr", "ff", "kab", "hy":
            return i == 0 || i == 1 ? "one" : (v == 0 && i != 0 && i % 1_000_000 == 0 ? "many" : "other")
        case "pt":
            if language.lowercased().hasPrefix("pt-pt") { return i == 1 && v == 0 ? "one" : "other" }
            return i == 0 || i == 1 ? "one" : (v == 0 && i != 0 && i % 1_000_000 == 0 ? "many" : "other")
        case "es", "it", "ca":
            if i == 1 && v == 0 { return "one" }
            return v == 0 && i != 0 && i % 1_000_000 == 0 ? "many" : "other"
        case "ru", "uk", "be":
            guard v == 0 else { return "other" }
            if i10 == 1 && i100 != 11 { return "one" }
            if (2...4).contains(i10) && !(12...14).contains(i100) { return "few" }
            return "many"
        case "pl":
            guard v == 0 else { return "other" }
            if i == 1 { return "one" }
            if (2...4).contains(i10) && !(12...14).contains(i100) { return "few" }
            return "many"
        case "cs", "sk":
            if v != 0 { return "many" }
            if i == 1 { return "one" }
            return (2...4).contains(i) ? "few" : "other"
        case "hr", "sr", "bs", "sh":
            guard v == 0 else { return "other" }
            if i10 == 1 && i100 != 11 { return "one" }
            if (2...4).contains(i10) && !(12...14).contains(i100) { return "few" }
            return "other"
        case "sl":
            if v != 0 { return "few" }
            switch i100 { case 1: return "one"; case 2: return "two"; case 3, 4: return "few"; default: return "other" }
        case "lt":
            if v != 0 { return "many" }
            if i10 == 1 && !(11...19).contains(i100) { return "one" }
            if (2...9).contains(i10) && !(11...19).contains(i100) { return "few" }
            return "other"
        case "lv":
            if i10 == 0 || (11...19).contains(i100) { return "zero" }
            return i10 == 1 && i100 != 11 ? "one" : "other"
        case "ro", "mo":
            if i == 1 && v == 0 { return "one" }
            return v != 0 || i == 0 || (2...19).contains(i100) ? "few" : "other"
        case "ar":
            if v != 0 { return "other" }
            switch i { case 0: return "zero"; case 1: return "one"; case 2: return "two"; default: break }
            if (3...10).contains(i100) { return "few" }
            return (11...99).contains(i100) ? "many" : "other"
        case "he", "iw":
            if (i == 1 && v == 0) || (i == 0 && v != 0) { return "one" }
            return i == 2 && v == 0 ? "two" : "other"
        case "ga":
            guard v == 0 else { return "other" }
            switch i { case 1: return "one"; case 2: return "two"; case 3...6: return "few"; case 7...10: return "many"; default: return "other" }
        case "cy":
            guard v == 0 else { return "other" }
            switch i { case 0: return "zero"; case 1: return "one"; case 2: return "two"; case 3: return "few"; case 6: return "many"; default: return "other" }
        case "is", "mk":
            if v != 0 { return lang == "is" ? "one" : "other" }
            return i10 == 1 && i100 != 11 ? "one" : "other"
        case "da":
            return n == 1 || (v != 0 && (i == 0 || i == 1)) ? "one" : "other"
        case "hi", "bn", "gu", "kn", "mr", "zu", "am", "fa", "as":
            return i == 0 || (n == 1) ? "one" : "other"
        default:   // en, de, nl, sv, nb, no, nn, fi, et, el, hu, tr, bg, gl, eu, af, ...
            return i == 1 && v == 0 ? "one" : "other"
        }
    }
}

/// `.stringsdict` formatting: each `%#@name@` takes the variant of `name` for its
/// argument's plural category, and every conversion is rewritten with an explicit position
/// so a variant without a number (`"one file"`) does not shift the arguments after it.
public enum _PluralFormat {
    /// Formats a table entry with arguments in `locale`, choosing plural categories by
    /// `language`.
    public static func format(_ entry: _LocalizedEntry, language: String, locale: Locale?, arguments: [CVarArg]) -> String {
        switch entry {
        case .string(let s):
            guard !arguments.isEmpty else { return s }
            return render(substitute(s, variables: [:]) { _ in ("other", false) }, locale: locale, arguments: arguments)
        case .plural(let format, let variables):
            let positional = substitute(format, variables: variables) { position in
                guard position >= 1, position <= arguments.count, let n = number(arguments[position - 1]) else { return ("other", false) }
                return (_PluralRules.category(of: n, language: language), n == 0)
            }
            return render(positional, locale: locale, arguments: arguments)
        }
    }

    /// Formats a string whose conversions all carry `n$` positions, one conversion at a time
    /// (swift-corelibs-foundation's `String(format:)` reads explicit positions wrongly, and
    /// crashes on `%n$@`).
    static func render(_ format: String, locale: Locale?, arguments: [CVarArg]) -> String {
        let s = Array(format.unicodeScalars)
        var out = ""
        var i = 0
        var literal = String.UnicodeScalarView()
        func flush() { out += String(literal); literal.removeAll() }
        while i < s.count {
            guard s[i] == "%" else { literal.append(s[i]); i += 1; continue }
            if i + 1 < s.count, s[i + 1] == "%" { literal.append("%"); i += 2; continue }
            var j = i + 1
            var digits = ""
            while j < s.count, ("0"..."9").contains(s[j]) { digits.unicodeScalars.append(s[j]); j += 1 }
            guard j < s.count, s[j] == "$", let position = Int(digits) else { literal.append(s[i]); i += 1; continue }
            j += 1
            var spec = String.UnicodeScalarView(["%"])
            while j < s.count, !isConversion(s[j]) { spec.append(s[j]); j += 1 }
            guard j < s.count else { break }
            spec.append(s[j])
            flush()
            if position >= 1, position <= arguments.count { out += String(format: String(spec), locale: locale, arguments: [arguments[position - 1]]) }
            i = j + 1
        }
        flush()
        return out
    }

    /// The format with each variable replaced by the variant `category(position)` picks
    /// (falling back to `other`; `zero` wins for 0 when the rule has it), and every
    /// conversion given an explicit `n$` position.
    static func substitute(_ format: String, variables: [String: [String: String]], positional: Bool = true, category: (Int) -> (String, Bool)) -> String {
        var next = 1
        return rewrite(format, next: &next, variables: variables, fixedPosition: nil, positional: positional, category: category, depth: 0)
    }

    private static func rewrite(_ format: String, next: inout Int, variables: [String: [String: String]], fixedPosition: Int?, positional: Bool,
                                category: (Int) -> (String, Bool), depth: Int) -> String {
        let s = Array(format.unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        while i < s.count {
            guard s[i] == "%" else { out.append(s[i]); i += 1; continue }
            if i + 1 < s.count, s[i + 1] == "%" { out.append("%"); out.append("%"); i += 2; continue }
            // %[n$][flags][width][.precision][length]conv  or  %[n$]#@name@
            var j = i + 1
            var digits = ""
            while j < s.count, ("0"..."9").contains(s[j]) { digits.unicodeScalars.append(s[j]); j += 1 }
            var explicit: Int? = nil
            if j < s.count, s[j] == "$", let n = Int(digits) { explicit = n; j += 1 } else { j = i + 1 }
            if j + 1 < s.count, s[j] == "#", s[j + 1] == "@" {
                var k = j + 2
                var name = ""
                while k < s.count, s[k] != "@" { name.unicodeScalars.append(s[k]); k += 1 }
                let position = explicit ?? { defer { next += 1 }; return next }()
                let rule = variables[name] ?? [:]
                let (plural, isZero) = category(position)
                // `zero` applies to the value 0 whatever the language (Apple's behaviour).
                let cat = isZero && rule["zero"] != nil ? "zero" : plural
                let variant = rule[cat] ?? rule["other"] ?? ""
                if depth < 4 {
                    var inner = next
                    out.append(contentsOf: rewrite(variant, next: &inner, variables: variables, fixedPosition: position, positional: positional, category: category, depth: depth + 1).unicodeScalars)
                }
                i = min(k + 1, s.count)
                continue
            }
            // An ordinary conversion: copy flags, width, precision and length, then the conversion character.
            var spec = String.UnicodeScalarView()
            while j < s.count, !isConversion(s[j]) { spec.append(s[j]); j += 1 }
            guard j < s.count else { out.append(contentsOf: s[i...]); break }
            let position = fixedPosition ?? explicit ?? { defer { next += 1 }; return next }()
            out.append("%")
            if positional { out.append(contentsOf: "\(position)$".unicodeScalars) }
            else if let explicit { out.append(contentsOf: "\(explicit)$".unicodeScalars) }
            out.append(contentsOf: spec)
            out.append(s[j])
            i = j + 1
        }
        return String(out)
    }

    private static func isConversion(_ c: Unicode.Scalar) -> Bool {
        "@dDiuUxXoOfFeEgGcCsSpaA".unicodeScalars.contains(c)
    }

    /// The numeric value of a format argument.
    static func number(_ arg: CVarArg) -> Double? {
        switch arg {
        case let v as Int: return Double(v)
        case let v as Int8: return Double(v)
        case let v as Int16: return Double(v)
        case let v as Int32: return Double(v)
        case let v as Int64: return Double(v)
        case let v as UInt: return Double(v)
        case let v as UInt8: return Double(v)
        case let v as UInt16: return Double(v)
        case let v as UInt32: return Double(v)
        case let v as UInt64: return Double(v)
        case let v as Double: return v
        case let v as Float: return Double(v)
        case let v as CGFloat: return Double(v)
        case let v as NSNumber: return v.doubleValue
        default: return nil
        }
    }
}
