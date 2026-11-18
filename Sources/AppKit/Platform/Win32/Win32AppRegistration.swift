// The registration of ADR-0045 on Windows: the values `_AppRegistration.windowsRegistryValues`
// lists, written under HKEY_CURRENT_USER (no elevation), then SHChangeNotify so Explorer
// re-reads the associations. A value marked `ifAbsent` is written only when HKEY_CLASSES_ROOT
// (the user's and the machine's classes merged) has none; a URL scheme another executable owns
// is left alone. Unregistering removes the keys the registration owns, its OpenWithProgids
// entries, the extension defaults that still name its ProgIDs, its RegisteredApplications value
// and the scheme keys whose command is this executable.

#if os(Windows)
import Foundation
import WinSDK

private let hkcu = HKEY(bitPattern: Int(Int32(bitPattern: 0x8000_0001)))
private let hkcr = HKEY(bitPattern: Int(Int32(bitPattern: 0x8000_0000)))
private let classesPrefix = "Software\\Classes\\"

/// A string value, nil when the key or value does not exist.
private func readString(_ root: HKEY?, _ key: String, _ name: String?) -> String? {
    var size: DWORD = 0
    let flags = DWORD(RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ | RRF_NOEXPAND)
    let probe = key.withCString(encodedAs: UTF16.self) { k in
        name.map { n in n.withCString(encodedAs: UTF16.self) { RegGetValueW(root, k, $0, flags, nil, nil, &size) } }
            ?? RegGetValueW(root, k, nil, flags, nil, nil, &size)
    }
    guard probe == ERROR_SUCCESS, size > 0 else { return nil }
    var buffer = [WCHAR](repeating: 0, count: Int(size) / 2 + 1)
    let status = key.withCString(encodedAs: UTF16.self) { k in
        name.map { n in n.withCString(encodedAs: UTF16.self) { RegGetValueW(root, k, $0, flags, nil, &buffer, &size) } }
            ?? RegGetValueW(root, k, nil, flags, nil, &buffer, &size)
    }
    guard status == ERROR_SUCCESS else { return nil }
    return String(decoding: buffer.prefix { $0 != 0 }, as: UTF16.self)
}

/// Sets a REG_SZ value, creating the key.
private func writeString(_ key: String, _ name: String?, _ value: String) -> Bool {
    let data = Array(value.utf16) + [0]
    let status = key.withCString(encodedAs: UTF16.self) { k in
        data.withUnsafeBytes { bytes in
            name.map { n in n.withCString(encodedAs: UTF16.self) { RegSetKeyValueW(hkcu, k, $0, DWORD(REG_SZ), bytes.baseAddress, DWORD(bytes.count)) } }
                ?? RegSetKeyValueW(hkcu, k, nil, DWORD(REG_SZ), bytes.baseAddress, DWORD(bytes.count))
        }
    }
    return status == ERROR_SUCCESS
}

private func deleteTree(_ key: String) {
    _ = key.withCString(encodedAs: UTF16.self) { RegDeleteTreeW(hkcu, $0) }
}
private func deleteValue(_ key: String, _ name: String?) {
    _ = key.withCString(encodedAs: UTF16.self) { k in
        name.map { n in n.withCString(encodedAs: UTF16.self) { RegDeleteKeyValueW(hkcu, k, $0) } } ?? RegDeleteKeyValueW(hkcu, k, nil)
    }
}

private func notifyShell() {
    SHChangeNotify(LONG(SHCNE_ASSOCCHANGED), UINT(SHCNF_IDLIST), nil, nil)
}

/// Whether a scheme key is free or already this executable's.
private func schemeIsOurs(_ schemeKey: String, _ plan: _AppRegistration) -> Bool {
    let classKey = String(schemeKey.dropFirst(classesPrefix.count))
    guard let command = readString(hkcr, classKey + "\\shell\\open\\command", nil) else { return true }
    return command.lowercased().contains(plan.executablePath.lowercased())
}

func _platformRegisterApplication(_ plan: _AppRegistration, iconPNG: Data?) throws {
    let foreignSchemes = Set(plan.windowsSchemeKeys.filter { !schemeIsOurs($0, plan) })
    var failed: [String] = []
    for v in plan.windowsRegistryValues {
        if foreignSchemes.contains(where: { v.key == $0 || v.key.hasPrefix($0 + "\\") }) { continue }
        if v.condition == .ifAbsent {
            let classKey = v.key.hasPrefix(classesPrefix) ? String(v.key.dropFirst(classesPrefix.count)) : v.key
            let existing = v.key.hasPrefix(classesPrefix) ? readString(hkcr, classKey, v.name) : readString(hkcu, v.key, v.name)
            if let existing, !existing.isEmpty { continue }
        }
        if !writeString(v.key, v.name, v.value) { failed.append(v.key + (v.name.map { "\\" + $0 } ?? "")) }
    }
    notifyShell()
    if !failed.isEmpty { throw PlatformWorkspaceError.fileOperationFailed("could not write \(failed.joined(separator: ", "))") }
}

func _platformUnregisterApplication(_ plan: _AppRegistration) throws {
    for t in plan.documentTypes {
        for ext in t.extensions {
            let extKey = classesPrefix + "." + ext
            deleteValue(extKey + "\\OpenWithProgids", t.progID)
            if readString(hkcu, extKey, nil) == t.progID { deleteValue(extKey, nil) }
        }
    }
    for key in plan.windowsSchemeKeys where schemeIsOurs(key, plan) && readString(hkcu, key + "\\shell\\open\\command", nil) != nil { deleteTree(key) }
    for key in plan.windowsOwnedKeys { deleteTree(key) }
    deleteValue("Software\\RegisteredApplications", plan.identifier)
    notifyShell()
}

func _platformIsApplicationRegistered(_ plan: _AppRegistration) -> Bool {
    let command = readString(hkcu, classesPrefix + "Applications\\" + plan.windowsExecutableName + "\\shell\\open\\command", nil)
    return command?.lowercased() == plan.windowsOpenCommand.lowercased()
}
#endif
