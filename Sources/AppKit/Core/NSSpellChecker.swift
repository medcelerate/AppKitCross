// NSSpellChecker (hand-written; seeded from the generated stub, see tools/apigen)
//
// The shared spell checker (ADR-0030). Words are checked by the operating system's checker
// (`PlatformSpellChecking`: the Windows Spell Checking API, hunspell on Linux) or, where
// there is none, by a built-in English word list. On top of either the checker keeps what
// AppKit keeps: learned words (persistent, in the user defaults), ignored words per spell
// document tag, completions from a word list, and the Spelling and Substitutions panels.
// Grammar checking is not implemented: `checkGrammar` finds nothing. Language
// identification is not either: `automaticallyIdentifiesLanguages` is stored and the
// current language checks every word.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The fallback checker: the built-in list plus /usr/share/dict/words when present.
final class _NSWordListSpellChecker: PlatformSpellChecker {
    let name = "word list"
    var language = "en"
    var availableLanguages: [String] { ["en"] }
    private var words: Set<String>
    private let usesSystemWords: Bool
    private lazy var systemWords: Set<String> = {
        guard usesSystemWords, let text = try? String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8) else { return [] }
        return Set(text.split(whereSeparator: \.isNewline).map { $0.lowercased() })
    }()

    /// `words` replaces the built-in list (tests use a known vocabulary).
    init(words: [String]? = nil, usesSystemWords: Bool? = nil) {
        if let words {
            self.words = Set(words.map { $0.lowercased() })
            self.usesSystemWords = usesSystemWords ?? false
        } else {
            self.words = Set(_EnglishWordList.common.split(whereSeparator: { $0 == " " || $0 == "\n" }).map { String($0).lowercased() })
            self.usesSystemWords = usesSystemWords ?? true
        }
    }

    func setLanguage(_ language: String) -> Bool { language.hasPrefix("en") }

    private func known(_ w: String) -> Bool { words.contains(w) || systemWords.contains(w) }

    func isCorrect(_ word: String) -> Bool {
        let w = word.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        if known(w) { return true }
        // Common inflections of a listed word.
        for (suffix, replacements) in [("'s", [""]), ("ies", ["y"]), ("es", ["", "e"]), ("s", [""]), ("ied", ["y"]), ("ed", ["", "e"]),
                                       ("ing", ["", "e"]), ("ly", [""]), ("er", ["", "e"]), ("est", ["", "e"])] where w.hasSuffix(suffix) && w.count > suffix.count + 1 {
            let stem = String(w.dropLast(suffix.count))
            for r in replacements where known(stem + r) { return true }
            // Doubled consonant: "stopped", "running".
            if let last = stem.last, stem.count > 2, stem.dropLast().last == last, known(String(stem.dropLast())) { return true }
        }
        return false
    }

    func guesses(for word: String) -> [String] {
        let w = word.lowercased()
        var scored: [(String, Int)] = []
        for candidate in words.union(systemWords) where abs(candidate.count - w.count) <= 2 && candidate != w {
            let d = _NSWordListSpellChecker.distance(w, candidate, limit: 2)
            if d <= 2 { scored.append((candidate, d)) }
        }
        scored.sort { a, b in a.1 != b.1 ? a.1 < b.1 : abs(a.0.count - w.count) != abs(b.0.count - w.count) ? abs(a.0.count - w.count) < abs(b.0.count - w.count) : a.0 < b.0 }
        let capitalized = word.first?.isUppercase == true
        return scored.prefix(10).map { capitalized ? $0.0.prefix(1).uppercased() + $0.0.dropFirst() : $0.0 }
    }

    func learn(_ word: String) { words.insert(word.lowercased()) }

    /// Words with `prefix`, for completions.
    func words(withPrefix prefix: String) -> [String] {
        let p = prefix.lowercased()
        return words.union(systemWords).filter { $0.hasPrefix(p) && $0 != p }.sorted { $0.count != $1.count ? $0.count < $1.count : $0 < $1 }
    }

    /// Damerau–Levenshtein (optimal string alignment) distance, stopping early above `limit`.
    static func distance(_ a: String, _ b: String, limit: Int) -> Int {
        let s = Array(a), t = Array(b)
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }
        var prev2 = [Int](repeating: 0, count: t.count + 1)
        var prev = Array(0...t.count)
        var cur = [Int](repeating: 0, count: t.count + 1)
        for i in 1...s.count {
            cur[0] = i
            var rowMin = cur[0]
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                if i > 1, j > 1, s[i - 1] == t[j - 2], s[i - 2] == t[j - 1] { cur[j] = min(cur[j], prev2[j - 2] + 1) }
                rowMin = min(rowMin, cur[j])
            }
            if rowMin > limit { return limit + 1 }
            prev2 = prev; prev = cur
        }
        return prev[t.count]
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker
open class NSSpellChecker: NSObject {
    nonisolated(unsafe) private static var _sharedInstance: NSSpellChecker?
    nonisolated(unsafe) private static var _nextTag = 1

    /// The checker words go to. Tests replace it with a word list of their own.
    internal var _engine: any PlatformSpellChecker
    private var _automaticallyIdentifiesLanguages = true
    private var _ignored: [Int: Set<String>] = [:]
    private var _learned: Set<String>
    private var _accessoryView: NSView?
    private var _substitutionsAccessory: NSViewController?
    private static let _learnedKey = "NSSpellCheckerLearnedWords"

    private override init() {
        _engine = PlatformSpellChecking.makeSystemChecker() ?? _NSWordListSpellChecker()
        _learned = Set(UserDefaults.standard.stringArray(forKey: NSSpellChecker._learnedKey) ?? [])
        super.init()
        for w in _learned { _engine.learn(w) }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/shared
    class public var shared: NSSpellChecker {
        if let s = _sharedInstance { return s }
        let s = NSSpellChecker()
        _sharedInstance = s
        return s
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/sharedspellcheckerexists
    class public var sharedSpellCheckerExists: Bool { _sharedInstance != nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/uniquespelldocumenttag()
    public class func uniqueSpellDocumentTag() -> Int {
        defer { _nextTag += 1 }
        return _nextTag
    }

    // MARK: Languages

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/availablelanguages
    open var availableLanguages: [String] { _engine.availableLanguages }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/userpreferredlanguages
    open var userPreferredLanguages: [String] { [_engine.language] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/automaticallyidentifieslanguages
    open var automaticallyIdentifiesLanguages: Bool {
        get { _automaticallyIdentifiesLanguages }
        set { _automaticallyIdentifiesLanguages = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/language()
    open func language() -> String { _engine.language }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/setlanguage(_:)
    open func setLanguage(_ language: String) -> Bool {
        let ok = _engine.setLanguage(language.replacingOccurrences(of: "-", with: "_"))
        if ok { for w in _learned { _engine.learn(w) } }
        return ok
    }
    /// Without language identification every word is in the current language.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/language(forwordrange:in:orthography:)
    open func language(forWordRange range: NSRange, in string: String, orthography: NSOrthography?) -> String? { _engine.language }

    // MARK: Checking

    /// The words of `string` (UTF-16 ranges): letters, digits and inner apostrophes/hyphens.
    internal static func _words(in string: String, from start: Int = 0, to end: Int? = nil) -> [NSRange] {
        let s = string as NSString
        let limit = min(end ?? s.length, s.length)
        var out: [NSRange] = []
        var i = max(0, start)
        func isLetter(_ c: unichar) -> Bool {
            guard let u = UnicodeScalar(c) else { return c >= 0xD800 && c <= 0xDFFF }
            return CharacterSet.letters.contains(u) || CharacterSet.decimalDigits.contains(u) || CharacterSet.nonBaseCharacters.contains(u)
        }
        while i < limit {
            while i < limit && !isLetter(s.character(at: i)) { i += 1 }
            guard i < limit else { break }
            let a = i
            while i < limit {
                let c = s.character(at: i)
                if isLetter(c) { i += 1; continue }
                // An apostrophe or hyphen between letters belongs to the word ("don't").
                if (c == 0x27 || c == 0x2019) && i + 1 < limit && isLetter(s.character(at: i + 1)) { i += 1; continue }
                break
            }
            out.append(NSRange(location: a, length: i - a))
        }
        return out
    }

    /// Whether a word counts as misspelt for `tag`.
    internal func _isMisspelled(_ word: String, tag: Int) -> Bool {
        guard word.count > 1, !word.contains(where: { $0.isNumber }) else { return false }
        let normalized = word.replacingOccurrences(of: "\u{2019}", with: "'")
        if _learned.contains(normalized.lowercased()) || _ignored[tag]?.contains(normalized) == true { return false }
        return !_engine.isCorrect(normalized)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/checkspelling(of:startingat:)
    open func checkSpelling(of stringToCheck: String, startingAt startingOffset: Int) -> NSRange {
        checkSpelling(of: stringToCheck, startingAt: startingOffset, language: nil, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/checkspelling(of:startingat:language:wrap:inspelldocumentwithtag:wordcount:)
    open func checkSpelling(of stringToCheck: String, startingAt startingOffset: Int, language: String?, wrap wrapFlag: Bool, inSpellDocumentWithTag tag: Int, wordCount: UnsafeMutablePointer<Int>?) -> NSRange {
        let s = stringToCheck as NSString
        if let language, language != _engine.language { _ = setLanguage(language) }
        var counted = 0
        func scan(_ from: Int, _ to: Int) -> NSRange? {
            for r in NSSpellChecker._words(in: stringToCheck, from: from, to: to) {
                counted += 1
                if _isMisspelled(s.substring(with: r), tag: tag) { return r }
            }
            return nil
        }
        // Start at a word boundary: a start inside a word skips the rest of that word.
        var start = min(max(0, startingOffset), s.length)
        if start > 0, start < s.length, let w = NSSpellChecker._words(in: stringToCheck, from: max(0, start - 64), to: min(s.length, start + 64)).first(where: { $0.location < start && NSMaxRange($0) > start }) {
            start = NSMaxRange(w)
        }
        var found = scan(start, s.length)
        if found == nil && wrapFlag { found = scan(0, start) }
        wordCount?.pointee = found == nil ? counted : -1
        return found ?? NSRange(location: NSNotFound, length: 0)
    }
    /// Grammar checking is not implemented: nothing is found.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/checkgrammar(of:startingat:language:wrap:inspelldocumentwithtag:details:)
    open func checkGrammar(of stringToCheck: String, startingAt startingOffset: Int, language: String?, wrap wrapFlag: Bool, inSpellDocumentWithTag tag: Int, details: AutoreleasingUnsafeMutablePointer<NSArray?>?) -> NSRange {
        details?.pointee = nil
        return NSRange(location: NSNotFound, length: 0)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/countwords(in:language:)
    open func countWords(in stringToCount: String, language: String?) -> Int { NSSpellChecker._words(in: stringToCount).count }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/guesses(forwordrange:in:language:inspelldocumentwithtag:)
    open func guesses(forWordRange range: NSRange, in string: String, language: String?, inSpellDocumentWithTag tag: Int) -> [String]? {
        let s = string as NSString
        guard range.location != NSNotFound, NSMaxRange(range) <= s.length, range.length > 0 else { return nil }
        if let language, language != _engine.language { _ = setLanguage(language) }
        return _engine.guesses(for: s.substring(with: range))
    }
    /// The first guess when it is a single edit away (a typo), as autocorrection uses it.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/correction(forwordrange:in:language:inspelldocumentwithtag:)
    open func correction(forWordRange range: NSRange, in string: String, language: String, inSpellDocumentWithTag tag: Int) -> String? {
        let s = string as NSString
        guard range.location != NSNotFound, NSMaxRange(range) <= s.length, range.length > 1 else { return nil }
        let word = s.substring(with: range)
        guard _isMisspelled(word, tag: tag), let best = guesses(forWordRange: range, in: string, language: language, inSpellDocumentWithTag: tag)?.first else { return nil }
        return _NSWordListSpellChecker.distance(word.lowercased(), best.lowercased(), limit: 1) <= 1 ? best : nil
    }
    /// Words that complete the partial word: learned words, the document's own words and the
    /// word list, shortest first, in the partial word's capitalisation.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/completions(forpartialwordrange:in:language:inspelldocumentwithtag:)
    open func completions(forPartialWordRange range: NSRange, in string: String, language: String?, inSpellDocumentWithTag tag: Int) -> [String]? {
        let s = string as NSString
        guard range.location != NSNotFound, NSMaxRange(range) <= s.length, range.length > 0 else { return nil }
        let partial = s.substring(with: range)
        let lower = partial.lowercased()
        var seen = Set<String>()
        var out: [String] = []
        func add(_ w: String) {
            let l = w.lowercased()
            guard l.hasPrefix(lower), l != lower, !seen.contains(l) else { return }
            seen.insert(l)
            out.append(w)
        }
        for r in NSSpellChecker._words(in: string) where r.location != range.location { add(s.substring(with: r)) }
        for w in _learned.sorted() { add(w) }
        let list = (_engine as? _NSWordListSpellChecker) ?? NSSpellChecker._completionList
        for w in list.words(withPrefix: lower).prefix(200) { add(w) }
        let capitalized = partial.first?.isUppercase == true
        let sorted = out.sorted { $0.count != $1.count ? $0.count < $1.count : $0.lowercased() < $1.lowercased() }
        return sorted.prefix(50).map { w in
            guard capitalized, w.first?.isLowercase == true else { return w }
            return w.prefix(1).uppercased() + w.dropFirst()
        }
    }
    nonisolated(unsafe) private static var _completionListStorage: _NSWordListSpellChecker?
    private static var _completionList: _NSWordListSpellChecker {
        if let l = _completionListStorage { return l }
        let l = _NSWordListSpellChecker()
        _completionListStorage = l
        return l
    }

    // MARK: Learning and ignoring

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/learnword(_:)
    open func learnWord(_ word: String) {
        _learned.insert(word.lowercased())
        _engine.learn(word)
        UserDefaults.standard.set(_learned.sorted(), forKey: NSSpellChecker._learnedKey)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/unlearnword(_:)
    open func unlearnWord(_ word: String) {
        _learned.remove(word.lowercased())
        UserDefaults.standard.set(_learned.sorted(), forKey: NSSpellChecker._learnedKey)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/haslearnedword(_:)
    open func hasLearnedWord(_ word: String) -> Bool { _learned.contains(word.lowercased()) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/ignoreword(_:inspelldocumentwithtag:)
    open func ignoreWord(_ wordToIgnore: String, inSpellDocumentWithTag tag: Int) { _ignored[tag, default: []].insert(wordToIgnore) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/ignoredwords(inspelldocumentwithtag:)
    open func ignoredWords(inSpellDocumentWithTag tag: Int) -> [String]? { _ignored[tag].map { $0.sorted() } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/setignoredwords(_:inspelldocumentwithtag:)
    open func setIgnoredWords(_ words: [String], inSpellDocumentWithTag tag: Int) { _ignored[tag] = Set(words) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/closespelldocument(withtag:)
    open func closeSpellDocument(withTag tag: Int) { _ignored[tag] = nil }

    // MARK: Autocorrection preferences (the port has no system preference: the user defaults decide)

    private static func _pref(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/isautomaticcapitalizationenabled
    class public var isAutomaticCapitalizationEnabled: Bool { _pref("NSAutomaticCapitalizationEnabled") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/isautomaticdashsubstitutionenabled
    class public var isAutomaticDashSubstitutionEnabled: Bool { _pref("NSAutomaticDashSubstitutionEnabled") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/isautomaticinlinepredictionenabled
    class public var isAutomaticInlinePredictionEnabled: Bool { _pref("NSAutomaticInlinePredictionEnabled") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/isautomaticperiodsubstitutionenabled
    class public var isAutomaticPeriodSubstitutionEnabled: Bool { _pref("NSAutomaticPeriodSubstitutionEnabled") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/isautomaticquotesubstitutionenabled
    class public var isAutomaticQuoteSubstitutionEnabled: Bool { _pref("NSAutomaticQuoteSubstitutionEnabled") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/isautomaticspellingcorrectionenabled
    class public var isAutomaticSpellingCorrectionEnabled: Bool { _pref("NSAutomaticSpellingCorrectionEnabled") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/isautomatictextcompletionenabled
    class public var isAutomaticTextCompletionEnabled: Bool { _pref("NSAutomaticTextCompletionEnabled") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/isautomatictextreplacementenabled
    class public var isAutomaticTextReplacementEnabled: Bool { _pref("NSAutomaticTextReplacementEnabled") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/userreplacementsdictionary
    open var userReplacementsDictionary: [String : String] {
        (UserDefaults.standard.dictionary(forKey: "NSUserReplacementItems") as? [String: String]) ?? [:]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/userquotesarray(forlanguage:)
    open func userQuotesArray(forLanguage language: String) -> [String] {
        language.hasPrefix("de") ? ["\u{201E}", "\u{201C}", "\u{201A}", "\u{2018}"]
            : language.hasPrefix("fr") ? ["\u{00AB}\u{00A0}", "\u{00A0}\u{00BB}", "\u{2039}\u{00A0}", "\u{00A0}\u{203A}"]
            : ["\u{201C}", "\u{201D}", "\u{2018}", "\u{2019}"]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/deletesautospacebetweenstring(_:andstring:language:)
    open func deletesAutospaceBetweenString(_ precedingString: String, andString followingString: String, language: String?) -> Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/preventsautocorrection(before:language:)
    open func preventsAutocorrection(before string: String, language: String?) -> Bool { false }
    /// Responses are not used to adapt corrections.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/record(_:tocorrection:forword:language:inspelldocumentwithtag:)
    open func record(_ response: NSSpellChecker.CorrectionResponse, toCorrection correction: String, forWord word: String, language: String?, inSpellDocumentWithTag tag: Int) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/dismisscorrectionindicator(for:)
    open func dismissCorrectionIndicator(for view: NSView) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/showcorrectionindicator(of:primarystring:alternativestrings:forstringin:view:)
    open func showCorrectionIndicator(of type: NSSpellChecker.CorrectionIndicatorType, primaryString: String, alternativeStrings: [String], forStringIn rectOfTypedString: NSRect, view: NSView) async -> String? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/showinlineprediction(forcandidates:client:)
    open func showInlinePrediction(forCandidates candidates: [NSTextCheckingResult], client: any NSTextInputClient) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/menu(for:string:options:atlocation:in:)
    open func menu(for result: NSTextCheckingResult, string checkedString: String, options: [NSSpellChecker.OptionKey : Any]? = nil, atLocation location: NSPoint, in view: NSView) -> NSMenu? { unimplemented() }

    // MARK: Panels

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/accessoryview
    open var accessoryView: NSView? {
        get { _accessoryView }
        set { _accessoryView = newValue; MainActor.assumeIsolated { _NSSpellingPanel.shared?.setAccessory(newValue) } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/spellingpanel
    open var spellingPanel: NSPanel { MainActor.assumeIsolated { _NSSpellingPanel.panel(accessory: _accessoryView) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/substitutionspanel
    open var substitutionsPanel: NSPanel { MainActor.assumeIsolated { _NSSubstitutionsPanel.panel() } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/substitutionspanelaccessoryviewcontroller
    open var substitutionsPanelAccessoryViewController: NSViewController? {
        get { _substitutionsAccessory }
        set { _substitutionsAccessory = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/updatespellingpanel(withmisspelledword:)
    open func updateSpellingPanel(withMisspelledWord word: String) {
        MainActor.assumeIsolated { _NSSpellingPanel.shared?.show(word: word, guesses: word.isEmpty ? [] : _engine.guesses(for: word)) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/updatespellingpanel(withgrammarstring:detail:)
    open func updateSpellingPanel(withGrammarString string: String, detail: [String : Any]) { updateSpellingPanel(withMisspelledWord: string) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/setwordfieldstringvalue(_:)
    open func setWordFieldStringValue(_ string: String) { MainActor.assumeIsolated { _NSSpellingPanel.shared?.setWord(string) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsspellchecker/updatepanels()
    open func updatePanels() { MainActor.assumeIsolated { _NSSubstitutionsPanel.shared?.refresh() } }
}

// MARK: - The Spelling panel

/// "Spelling and Grammar": the misspelt word, its guesses, and Change / Find Next / Ignore /
/// Learn, sent through the responder chain as AppKit's panel does (changeSpelling:,
/// checkSpelling:, ignoreSpelling:).
@MainActor final class _NSSpellingPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    static var shared: _NSSpellingPanel?
    let panel: NSPanel
    let wordField: NSTextField
    let table: NSTableView
    let accessoryHost = NSView(frame: .zero)
    private(set) var guesses: [String] = []

    static func panel(accessory: NSView?) -> NSPanel {
        let p = shared ?? _NSSpellingPanel()
        shared = p
        p.setAccessory(accessory)
        return p.panel
    }

    private override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 260), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Spelling and Grammar"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        wordField = NSTextField(string: "")
        table = NSTableView(frame: .zero)
        super.init()
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 260))
        let label = NSTextField(labelWithString: "Not in the dictionary:")
        label.frame = NSRect(x: 12, y: 228, width: 220, height: 18)
        wordField.frame = NSRect(x: 12, y: 200, width: 220, height: 24)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("guess"))
        column.width = 200
        table.addTableColumn(column)
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = _NSSpellingPanel.change
        let scroll = NSScrollView(frame: NSRect(x: 12, y: 40, width: 220, height: 150))
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        content.addSubview(label)
        content.addSubview(wordField)
        content.addSubview(scroll)
        var y: CGFloat = 196
        for (title, sel) in [("Change", _NSSpellingPanel.change), ("Find Next", _NSSpellingPanel.findNext), ("Ignore", _NSSpellingPanel.ignore), ("Learn", _NSSpellingPanel.learn)] {
            let b = NSButton(title: title, target: self, action: sel)
            b.frame = NSRect(x: 244, y: y, width: 104, height: 28)
            content.addSubview(b)
            y -= 34
        }
        accessoryHost.frame = NSRect(x: 12, y: 8, width: 336, height: 24)
        content.addSubview(accessoryHost)
        panel.contentView = content
        setActionHandler(for: _NSSpellingPanel.change) { [weak self] _ in self?.sendChange() }
        setActionHandler(for: _NSSpellingPanel.findNext) { [weak self] _ in self?.send("checkSpelling:") }
        setActionHandler(for: _NSSpellingPanel.ignore) { [weak self] _ in self?.send("ignoreSpelling:") }
        setActionHandler(for: _NSSpellingPanel.learn) { [weak self] _ in self?.learn() }
    }

    static let change = Selector(("_spellingPanelChange:"))
    static let findNext = Selector(("_spellingPanelFindNext:"))
    static let ignore = Selector(("_spellingPanelIgnore:"))
    static let learn = Selector(("_spellingPanelLearn:"))

    func setAccessory(_ view: NSView?) {
        accessoryHost.subviews.forEach { $0.removeFromSuperview() }
        if let view { view.frame = accessoryHost.bounds; accessoryHost.addSubview(view) }
    }
    func setWord(_ word: String) { wordField.stringValue = word }
    func show(word: String, guesses: [String]) {
        wordField.stringValue = word
        self.guesses = guesses
        table.reloadData()
        if !guesses.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
    }

    /// The text view the panel works on: the main window's first responder.
    private var target: NSResponder? { NSApplication.shared.mainWindow?.firstResponder ?? NSApplication.shared.keyWindow?.firstResponder }

    private func send(_ action: String) {
        _ = NSApplication.shared.sendAction(Selector((action)), to: nil, from: wordField)
    }
    private func sendChange() {
        let row = table.selectedRow
        if row >= 0, row < guesses.count, wordField.stringValue == (target as? NSTextView).map({ ($0.string as NSString).substring(with: $0.selectedRange) }) {
            wordField.stringValue = guesses[row]
        }
        send("changeSpelling:")
    }
    private func learn() {
        let word = wordField.stringValue
        guard !word.isEmpty else { return }
        NSSpellChecker.shared.learnWord(word)
        (target as? NSTextView)?._spellingDidChange()
        send("checkSpelling:")
    }

    func numberOfRows(in tableView: NSTableView) -> Int { guesses.count }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? { guesses[row] }
}

// MARK: - The Substitutions panel

/// Checkboxes for the key text view's substitutions and checking, as in AppKit's panel.
@MainActor final class _NSSubstitutionsPanel: NSObject {
    static var shared: _NSSubstitutionsPanel?
    let panel: NSPanel
    private var boxes: [(NSButton, String, (NSTextView) -> Bool)] = []

    static func panel() -> NSPanel {
        let p = shared ?? _NSSubstitutionsPanel()
        shared = p
        p.refresh()
        return p.panel
    }

    private override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 200), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Substitutions"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        super.init()
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 200))
        let entries: [(String, String, (NSTextView) -> Bool)] = [
            ("Smart Copy/Paste", "toggleSmartInsertDelete:", { $0.smartInsertDeleteEnabled }),
            ("Smart Quotes", "toggleAutomaticQuoteSubstitution:", { $0.isAutomaticQuoteSubstitutionEnabled }),
            ("Smart Dashes", "toggleAutomaticDashSubstitution:", { $0.isAutomaticDashSubstitutionEnabled }),
            ("Text Replacement", "toggleAutomaticTextReplacement:", { $0.isAutomaticTextReplacementEnabled }),
            ("Correct Spelling Automatically", "toggleAutomaticSpellingCorrection:", { $0.isAutomaticSpellingCorrectionEnabled }),
            ("Check Spelling While Typing", "toggleContinuousSpellChecking:", { $0.isContinuousSpellCheckingEnabled }),
        ]
        var y: CGFloat = 166
        for (title, action, read) in entries {
            let sel = Selector(("_substitution_" + action))
            let box = NSButton(checkboxWithTitle: title, target: self, action: sel)
            box.frame = NSRect(x: 16, y: y, width: 250, height: 20)
            content.addSubview(box)
            boxes.append((box, action, read))
            setActionHandler(for: sel) { [weak self] _ in
                _ = NSApplication.shared.sendAction(Selector((action)), to: nil, from: box)
                self?.refresh()
            }
            y -= 26
        }
        panel.contentView = content
    }

    func refresh() {
        let tv = NSApplication.shared.mainWindow?.firstResponder as? NSTextView
        for (box, _, read) in boxes {
            box.isEnabled = tv != nil
            box.state = tv.map(read) == true ? .on : .off
        }
    }
}
