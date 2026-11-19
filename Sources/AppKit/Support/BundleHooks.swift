// Routes swift-corelibs-foundation's Bundle through the port (ADR-0045), Windows and Linux only.
//
// Apps call `NSLocalizedString`, `Bundle.main.url(forResource:withExtension:)` and
// `Bundle.main.infoDictionary` on corelibs' Bundle object; corelibs answers them in English
// only, crashes on `.stringsdict` keys and finds only what sits flat next to the executable.
// Bundle cannot be subclassed from outside Foundation (its vtable names implementation-only
// CoreFoundation types, so the compiler refuses), and a second `NSLocalizedString` in another
// module is ambiguous rather than shadowing. So the port replaces the implementations in
// Bundle's own vtable: for each member below it looks up corelibs' implementation by its
// mangled name, finds the one vtable slot of `Bundle`'s class metadata that points at it,
// keeps that pointer, and stores a trampoline from `CBundleHooks` (a C function in the Swift
// calling convention, the receiver in the self register) that calls back into Swift here.
// Nothing is installed unless every member's slot is found exactly once; after installing,
// a call through the vtable must reach the port (a self-test), else the originals go back.
// Localization members answer for every bundle (module bundles included); resource and
// Info.plist members answer for the main bundle and call corelibs' original for the others.
// `APPKITWIN_CORELIBS_BUNDLE=1` turns all of it off.

import Foundation
#if os(Windows) || os(Linux)
internal import CBundleHooks

enum _BundleHooks {
    /// corelibs' implementation symbols (swift-corelibs-foundation 6.x mangling).
    static let symbols: [(Int32, String)] = [
        (Int32(AKC_HOOK_LOCALIZED_STRING), "$s10Foundation6BundleC15localizedString6forKey5value5tableS2S_SSSgAHtF"),
        (Int32(AKC_HOOK_PREFERRED_LOCALIZATIONS), "$s10Foundation6BundleC22preferredLocalizationsSaySSGvg"),
        (Int32(AKC_HOOK_LOCALIZATIONS), "$s10Foundation6BundleC13localizationsSaySSGvg"),
        (Int32(AKC_HOOK_DEVELOPMENT_LOCALIZATION), "$s10Foundation6BundleC23developmentLocalizationSSSgvg"),
        (Int32(AKC_HOOK_INFO_DICTIONARY), "$s10Foundation6BundleC14infoDictionarySDySSypGSgvg"),
        (Int32(AKC_HOOK_BUNDLE_IDENTIFIER), "$s10Foundation6BundleC16bundleIdentifierSSSgvg"),
        (Int32(AKC_HOOK_OBJECT_FOR_INFO_KEY), "$s10Foundation6BundleC6object20forInfoDictionaryKeyypSgSS_tF"),
        (Int32(AKC_HOOK_RESOURCE_URL), "$s10Foundation6BundleC11resourceURL0A10Essentials0D0VSgvg"),
        (Int32(AKC_HOOK_RESOURCE_PATH), "$s10Foundation6BundleC12resourcePathSSSgvg"),
        (Int32(AKC_HOOK_URL_FOR_RESOURCE), "$s10Foundation6BundleC3url11forResource13withExtension0A10Essentials3URLVSgSSSg_AKtF"),
        (Int32(AKC_HOOK_URL_FOR_RESOURCE_SUBDIR), "$s10Foundation6BundleC3url11forResource13withExtension12subdirectory0A10Essentials3URLVSgSSSg_A2LtF"),
        (Int32(AKC_HOOK_PATH_FOR_RESOURCE), "$s10Foundation6BundleC4path11forResource6ofTypeSSSgAG_AGtF"),
        (Int32(AKC_HOOK_PATH_FOR_RESOURCE_DIR), "$s10Foundation6BundleC4path11forResource6ofType11inDirectorySSSgAH_A2HtF"),
    ]

    nonisolated(unsafe) static var originals = [UnsafeRawPointer?](repeating: nil, count: Int(AKC_HOOK_COUNT))
    nonisolated(unsafe) private(set) static var isInstalled = false
    nonisolated(unsafe) private static var calls = 0
    nonisolated(unsafe) private static var failure: String? = nil

    /// Why the hooks are not installed (nil when they are, or before the first try).
    static var installFailure: String? { failure }

    /// Installs the hooks once; false (with `installFailure`) when anything does not match.
    @discardableResult
    static func install() -> Bool {
        #if canImport(Darwin)
        failure = "macOS uses Apple's Bundle"
        return false
        #else
        if isInstalled { return true }
        if ProcessInfo.processInfo.environment["APPKITWIN_CORELIBS_BUNDLE"] == "1" { failure = "APPKITWIN_CORELIBS_BUNDLE=1"; return false }
        setDispatchers()
        let metadata = unsafeBitCast(Bundle.self as AnyClass, to: UnsafeMutableRawPointer.self)
        var plan: [(Int32, UnsafeMutableRawPointer, UnsafeRawPointer)] = []
        for (hook, symbol) in symbols {
            guard let original = _platformFoundationSymbol(symbol) else { failure = "corelibs has no \(symbol)"; return false }
            var slots: [Int] = []
            // The class metadata: header, then NSObject's and Bundle's vtable entries.
            for offset in stride(from: 0, to: 8192, by: MemoryLayout<UnsafeRawPointer>.stride)
            where metadata.load(fromByteOffset: offset, as: UnsafeRawPointer?.self) == original {
                slots.append(offset)
            }
            guard slots.count == 1 else { failure = "\(slots.count) vtable slots for \(symbol)"; return false }
            plan.append((hook, metadata.advanced(by: slots[0]), original))
        }
        for (hook, slot, original) in plan {
            originals[Int(hook)] = original
            guard let trampoline = akc_bundle_hook(hook), _platformStorePointer(trampoline, at: slot) else {
                failure = "could not write the vtable"
                restore(plan)
                return false
            }
        }
        // Self-test: a call through the vtable must arrive here.
        let before = calls
        _ = Bundle.main.developmentLocalization
        guard calls > before else { failure = "the vtable call did not reach the hook"; restore(plan); return false }
        isInstalled = true
        failure = nil
        return true
        #endif
    }

    private static func restore(_ plan: [(Int32, UnsafeMutableRawPointer, UnsafeRawPointer)]) {
        for (_, slot, original) in plan { _ = _platformStorePointer(original, at: slot) }
    }

    // MARK: Values in the Swift convention's words

    /// A borrowed argument (the caller keeps ownership): a copy.
    static func borrow<T>(_ words: akc_words2, as: T.Type) -> T { withUnsafeBytes(of: words) { $0.load(as: T.self) } }
    /// An owned result: its +1 moves into the words.
    static func give2<T>(_ value: T) -> akc_words2 {
        precondition(MemoryLayout<T>.size <= MemoryLayout<akc_words2>.size)
        let p = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<akc_words2>.size, alignment: 16)
        defer { p.deallocate() }
        p.storeBytes(of: akc_words2(w0: nil, w1: nil), as: akc_words2.self)
        p.initializeMemory(as: T.self, to: value)
        return p.load(as: akc_words2.self)
    }
    static func give4<T>(_ value: T) -> akc_words4 {
        precondition(MemoryLayout<T>.size <= MemoryLayout<akc_words4>.size)
        let p = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<akc_words4>.size, alignment: 16)
        defer { p.deallocate() }
        p.storeBytes(of: akc_words4(w0: nil, w1: nil, w2: nil, w3: nil), as: akc_words4.self)
        p.initializeMemory(as: T.self, to: value)
        return p.load(as: akc_words4.self)
    }
    static func give1<T>(_ value: T) -> UnsafeMutableRawPointer? {
        precondition(MemoryLayout<T>.size == MemoryLayout<UnsafeRawPointer>.size)
        let p = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<UnsafeRawPointer>.size, alignment: 16)
        defer { p.deallocate() }
        p.initializeMemory(as: T.self, to: value)
        return p.load(as: UnsafeMutableRawPointer?.self)
    }

    private static func bundle(_ selfPointer: UnsafeMutableRawPointer?) -> Bundle {
        Unmanaged<Bundle>.fromOpaque(selfPointer!).takeUnretainedValue()
    }
    private static func app(_ b: Bundle) -> _AppBundle { _AppBundle.forBundle(b) }
    private static func isMain(_ b: Bundle) -> Bool { b === Bundle.main }

    // MARK: Dispatch

    private static func setDispatchers() {
        akc_dispatch_w2_w2w2w2 = { hook, selfPointer, a, b, c in
            _BundleHooks.calls += 1
            let bundle = _BundleHooks.bundle(selfPointer)
            switch hook {
            case Int32(AKC_HOOK_LOCALIZED_STRING):
                let key = _BundleHooks.borrow(a, as: String.self)
                let value = _BundleHooks.borrow(b, as: String?.self)
                let table = _BundleHooks.borrow(c, as: String?.self)
                return _BundleHooks.give2(_BundleHooks.app(bundle).localizedString(forKey: key, value: value, table: table))
            case Int32(AKC_HOOK_URL_FOR_RESOURCE_SUBDIR), Int32(AKC_HOOK_PATH_FOR_RESOURCE_DIR):
                guard _BundleHooks.isMain(bundle) else { return akc_call_w2_w2w2w2(_BundleHooks.originals[Int(hook)], selfPointer, a, b, c) }
                let url = _AppBundle.main.url(forResource: _BundleHooks.borrow(a, as: String?.self), withExtension: _BundleHooks.borrow(b, as: String?.self),
                                              subdirectory: _BundleHooks.borrow(c, as: String?.self))
                return hook == Int32(AKC_HOOK_URL_FOR_RESOURCE_SUBDIR) ? _BundleHooks.give2(url) : _BundleHooks.give2(url?.path)
            default:
                return akc_call_w2_w2w2w2(_BundleHooks.originals[Int(hook)], selfPointer, a, b, c)
            }
        }
        akc_dispatch_w2_w2w2 = { hook, selfPointer, a, b in
            _BundleHooks.calls += 1
            let bundle = _BundleHooks.bundle(selfPointer)
            guard _BundleHooks.isMain(bundle) else { return akc_call_w2_w2w2(_BundleHooks.originals[Int(hook)], selfPointer, a, b) }
            let url = _AppBundle.main.url(forResource: _BundleHooks.borrow(a, as: String?.self), withExtension: _BundleHooks.borrow(b, as: String?.self))
            return hook == Int32(AKC_HOOK_URL_FOR_RESOURCE) ? _BundleHooks.give2(url) : _BundleHooks.give2(url?.path)
        }
        akc_dispatch_w4_w2 = { hook, selfPointer, a in
            _BundleHooks.calls += 1
            let bundle = _BundleHooks.bundle(selfPointer)
            guard _BundleHooks.isMain(bundle) else { return akc_call_w4_w2(_BundleHooks.originals[Int(hook)], selfPointer, a) }
            let key = _BundleHooks.borrow(a, as: String.self)
            return _BundleHooks.give4(_AppBundle.main.object(forInfoDictionaryKey: key) as Any?)
        }
        akc_dispatch_w1 = { hook, selfPointer in
            _BundleHooks.calls += 1
            let bundle = _BundleHooks.bundle(selfPointer)
            switch hook {
            case Int32(AKC_HOOK_PREFERRED_LOCALIZATIONS):
                return _BundleHooks.give1(_BundleHooks.app(bundle).preferredLocalizations)
            case Int32(AKC_HOOK_LOCALIZATIONS) where _BundleHooks.isMain(bundle):
                return _BundleHooks.give1(_AppBundle.main.localizations)
            case Int32(AKC_HOOK_INFO_DICTIONARY) where _BundleHooks.isMain(bundle):
                return _BundleHooks.give1(Optional(_AppBundle.main.infoDictionary))
            default:
                return akc_call_w1(_BundleHooks.originals[Int(hook)], selfPointer)
            }
        }
        akc_dispatch_w2 = { hook, selfPointer in
            _BundleHooks.calls += 1
            let bundle = _BundleHooks.bundle(selfPointer)
            switch hook {
            case Int32(AKC_HOOK_DEVELOPMENT_LOCALIZATION):
                return _BundleHooks.give2(Optional(_BundleHooks.app(bundle).developmentLocalization))
            case Int32(AKC_HOOK_BUNDLE_IDENTIFIER) where _BundleHooks.isMain(bundle):
                return _BundleHooks.give2(_AppBundle.main.bundleIdentifier)
            case Int32(AKC_HOOK_RESOURCE_URL) where _BundleHooks.isMain(bundle):
                return _BundleHooks.give2(Optional(_AppBundle.main.resourceURL))
            case Int32(AKC_HOOK_RESOURCE_PATH) where _BundleHooks.isMain(bundle):
                return _BundleHooks.give2(Optional(_AppBundle.main.resourceURL.path))
            default:
                return akc_call_w2(_BundleHooks.originals[Int(hook)], selfPointer)
            }
        }
    }
}
#endif
