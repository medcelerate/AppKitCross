// The system spell checker seam (ADR-0030). NSSpellChecker asks `PlatformSpellChecking`
// for the operating system's checker: the Windows Spell Checking API or hunspell on Linux,
// both through the CSpellCheck shim. There is none on the macOS host build (Apple's checker
// lives in the AppKit this package stands in for), nor when hunspell or its dictionaries are
// missing; NSSpellChecker then uses its built-in English word list.

import Foundation
#if canImport(CSpellCheck)
import CSpellCheck
#endif

/// A spell checker for one language at a time. Languages are POSIX-style ("en_US").
public protocol PlatformSpellChecker: AnyObject {
    /// A short description for diagnostics ("hunspell", "windows", "word list").
    var name: String { get }
    var availableLanguages: [String] { get }
    var language: String { get }
    /// Switches language; false when there is no dictionary for it.
    func setLanguage(_ language: String) -> Bool
    func isCorrect(_ word: String) -> Bool
    /// Replacements for a misspelt word, best first.
    func guesses(for word: String) -> [String]
    /// Accepts the word from now on (the caller keeps the persistent list).
    func learn(_ word: String)
}

public enum PlatformSpellChecking {
    /// The operating system's checker, or nil. `APPKITWIN_SPELL_CHECKER=wordlist` turns it off.
    public static func makeSystemChecker() -> (any PlatformSpellChecker)? {
        if ProcessInfo.processInfo.environment["APPKITWIN_SPELL_CHECKER"]?.lowercased() == "wordlist" { return nil }
        #if canImport(CSpellCheck)
        return _CSpellChecker.make()
        #else
        return nil
        #endif
    }
}

#if canImport(CSpellCheck)
/// The shim's checker: Windows Spell Checking API or hunspell.
final class _CSpellChecker: PlatformSpellChecker {
    private var handle: OpaquePointer?
    private(set) var language: String
    let name: String
    let availableLanguages: [String]

    static func make() -> _CSpellChecker? {
        let backend = String(cString: cspell_backend())
        guard backend != "none" else { return nil }
        let languages = _list(cspell_languages()).map { $0.replacingOccurrences(of: "-", with: "_") }
        guard !languages.isEmpty else { return nil }
        // The user's language first, then English, then whatever is installed.
        let preferred = Locale.preferredLanguages.map { $0.replacingOccurrences(of: "-", with: "_") }
        var candidates = preferred + ["en_US", "en_GB", "en"]
        candidates += languages
        for lang in candidates {
            if let h = lang.withCString({ cspell_open($0) }) {
                return _CSpellChecker(handle: h, language: languages.first { $0 == lang || $0.hasPrefix(lang + "_") } ?? lang, name: backend, languages: languages)
            }
        }
        return nil
    }

    private init(handle: OpaquePointer, language: String, name: String, languages: [String]) {
        self.handle = handle
        self.language = language
        self.name = name
        self.availableLanguages = languages
    }
    deinit { if let handle { cspell_close(handle) } }

    func setLanguage(_ language: String) -> Bool {
        guard let h = language.withCString({ cspell_open($0) }) else { return false }
        if let old = handle { cspell_close(old) }
        handle = h
        self.language = language
        return true
    }
    func isCorrect(_ word: String) -> Bool {
        guard let handle else { return true }
        return word.withCString { cspell_check(handle, $0) } != 0
    }
    func guesses(for word: String) -> [String] {
        guard let handle else { return [] }
        return _CSpellChecker._list(word.withCString { cspell_suggest(handle, $0) })
    }
    func learn(_ word: String) {
        guard let handle else { return }
        word.withCString { cspell_add(handle, $0) }
    }

    /// Unpacks a NUL-separated, double-NUL-terminated list and frees it.
    private static func _list(_ p: UnsafeMutablePointer<CChar>?) -> [String] {
        guard let p else { return [] }
        defer { cspell_free(p) }
        var out: [String] = []
        var cursor = p
        while cursor.pointee != 0 {
            let s = String(cString: cursor)
            out.append(s)
            cursor += s.utf8.count + 1
        }
        return out
    }
}
#endif
