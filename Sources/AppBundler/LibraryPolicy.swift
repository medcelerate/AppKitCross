// Which shared libraries travel with the app and which the target machine provides
// (ADR-0046).
//
// Windows: everything the executable imports that is not part of Windows itself: the Swift
// runtime (swiftCore, swift_Concurrency, Foundation, FoundationEssentials, _FoundationICU,
// dispatch, BlocksRuntime, swiftWinSDK, swiftCRT, ...) and any DLL the build produced. The
// Visual C++ runtime (vcruntime140*, msvcp140*) is copied too, app-locally, as Microsoft
// allows for the redistributable files; the Universal CRT ships with Windows 10 and later.
//
// Linux: everything in the executable's dependency closure except the libraries every
// desktop distribution has and that must match the running system: glibc and the loader,
// libgcc_s and libstdc++, the GPU and display stack (GL, Vulkan loader, X11/xcb, Wayland,
// xkbcommon), fonts (fontconfig, FreeType, HarfBuzz, FriBidi), D-Bus and ALSA. The list
// follows the AppImage project's excludelist for the same reasons.

import Foundation

public enum LibraryPolicy {
    // MARK: Windows

    /// API sets resolve inside the loader, never to a file.
    public static func isWindowsAPISet(_ dll: String) -> Bool {
        let n = dll.lowercased()
        return n.hasPrefix("api-ms-win-") || n.hasPrefix("ext-ms-")
    }

    /// The Visual C++ runtime DLLs the app carries itself (app-local deployment).
    public static func isVisualCRuntime(_ dll: String) -> Bool {
        let n = dll.lowercased()
        let names = ["vcruntime140.dll", "vcruntime140_1.dll", "vcruntime140_threads.dll",
                     "msvcp140.dll", "msvcp140_1.dll", "msvcp140_2.dll", "msvcp140_atomic_wait.dll",
                     "msvcp140_codecvt_ids.dll", "concrt140.dll", "vccorlib140.dll"]
        return names.contains(n)
    }

    /// The debug C runtime, which may not be redistributed: a debug build pulls it in.
    public static func isDebugCRuntime(_ dll: String) -> Bool {
        let n = dll.lowercased()
        return ["ucrtbased.dll", "vcruntime140d.dll", "vcruntime140_1d.dll", "msvcp140d.dll"].contains(n)
    }

    /// Whether `path` lies under the Windows directory (case-insensitive, either slash).
    public static func isUnderWindowsDirectory(_ path: String, systemRoot: String) -> Bool {
        func norm(_ s: String) -> String {
            var t = s.replacingOccurrences(of: "/", with: "\\").lowercased()
            while t.hasSuffix("\\") { t.removeLast() }
            return t
        }
        let root = norm(systemRoot)
        guard !root.isEmpty else { return false }
        let p = norm(path)
        return p == root || p.hasPrefix(root + "\\")
    }

    // MARK: Linux

    /// Library base names (the soname up to ".so") the target system provides.
    public static let linuxSystemLibraries: Set<String> = [
        // glibc and the loader
        "libc", "libm", "libmvec", "libdl", "libpthread", "librt", "libresolv", "libutil", "libanl",
        "libnsl", "libthread_db", "libBrokenLocale", "libcidn", "libcrypt", "libgcc_s", "libstdc++",
        // GPU and display
        "libGL", "libEGL", "libGLX", "libGLdispatch", "libOpenGL", "libGLESv2", "libglapi", "libdrm",
        "libgbm", "libvulkan", "libX11", "libX11-xcb", "libxcb", "libICE", "libSM",
        "libwayland-client", "libwayland-cursor", "libwayland-egl", "libwayland-server", "libxkbcommon",
        // fonts and text shaping (configured per system)
        "libfontconfig", "libfreetype", "libharfbuzz", "libfribidi", "libexpat", "libz",
        // the session: D-Bus (and systemd under it), sound
        "libdbus-1", "libsystemd", "libasound", "libjack", "libpipewire-0.3",
        // misc system libraries
        "libuuid", "libcom_err", "libgpg-error", "libgcrypt", "libp11-kit", "libusb-1.0", "libgmp",
    ]

    /// "libX11.so.6" → "libX11"; "ld-linux-x86-64.so.2" → "ld-linux-x86-64".
    public static func baseName(ofSoname soname: String) -> String {
        if let r = soname.range(of: ".so") { return String(soname[..<r.lowerBound]) }
        return soname
    }

    public static func isLinuxSystemLibrary(_ soname: String) -> Bool {
        let base = baseName(ofSoname: soname)
        if base.hasPrefix("ld-linux") || base.hasPrefix("ld64") || base == "linux-vdso" || base == "linux-gate" { return true }
        if base.hasPrefix("libnss_") { return true }
        if base.hasPrefix("libxcb-") { return true }
        return linuxSystemLibraries.contains(base)
    }

    /// `ldd` output → soname: resolved path (nil for "not found"). The vDSO and the loader's
    /// own line (no "=>") are left out.
    public static func parseLdd(_ output: String) -> [(soname: String, path: String?)] {
        var result: [(String, String?)] = []
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let arrow = line.range(of: " => ") else { continue }
            let soname = String(line[..<arrow.lowerBound]).trimmingCharacters(in: .whitespaces)
            var rest = String(line[arrow.upperBound...]).trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix("not found") { result.append((soname, nil)); continue }
            if let paren = rest.range(of: " (", options: .backwards) { rest = String(rest[..<paren.lowerBound]) }
            result.append((soname, rest.isEmpty ? nil : rest))
        }
        return result
    }
}
