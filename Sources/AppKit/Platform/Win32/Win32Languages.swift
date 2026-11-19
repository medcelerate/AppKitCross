// The user's UI languages on Windows (ADR-0045): GetUserPreferredUILanguages with
// MUI_LANGUAGE_NAME answers the Settings > Time & language list, most preferred first, as
// BCP 47 names ("de-DE", "en-US").

#if os(Windows)
import WinSDK

func _win32PreferredUILanguages() -> [String] {
    var count: ULONG = 0
    var size: ULONG = 0
    let flags = DWORD(MUI_LANGUAGE_NAME)
    guard GetUserPreferredUILanguages(flags, &count, nil, &size), size > 0 else { return [] }
    var buffer = [WCHAR](repeating: 0, count: Int(size))
    guard GetUserPreferredUILanguages(flags, &count, &buffer, &size) else { return [] }
    // A double-NUL-terminated list of NUL-terminated names.
    return buffer.split(separator: 0).map { String(decoding: $0, as: UTF16.self) }.filter { !$0.isEmpty }
}
#endif
