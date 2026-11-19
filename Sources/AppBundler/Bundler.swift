// Lays out a runnable application folder from a built executable (ADR-0046):
//
//   <Name>/
//     <Name>(.exe)              the executable
//     <Name>.pdb                Windows: its debug symbols, when the build wrote them, so
//                               crash reports name functions
//     *.dll | *.so*             every shared library it loads that the target system lacks:
//                               the Swift runtime, Foundation and ICU, libdispatch, the
//                               Visual C++ runtime on Windows, Cairo/Pango and friends on Linux
//     <Package>_<Target>.resources/   SwiftPM resource bundles of the product's targets
//     Info.plist                the app's Info.plist, when it has one
//     Resources/                the app's Resources directory, when it has one
//     *.ico, *.png              icons found beside the Info.plist
//
// Everything sits beside the executable: Windows looks for DLLs in the executable's
// directory first, SwiftPM links Linux executables with RUNPATH $ORIGIN, the Swift
// runtime's own libraries carry $ORIGIN, and a resource bundle's accessor looks next to the
// executable (Bundle.main) first.

import Foundation

public enum BundlePlatform: String, Sendable {
    case windows, linux, macos

    public static var current: BundlePlatform {
        #if os(Windows)
        return .windows
        #elseif os(Linux)
        return .linux
        #else
        return .macos
        #endif
    }
}

public struct BundleOptions: Sendable {
    public var executable: URL
    public var name: String
    public var packageDirectory: URL
    /// Directories to look in for Info.plist / Resources / icons, nearest first (the
    /// executable target's directory and its parents below the package root).
    public var appRootCandidates: [URL]
    /// Target names whose SwiftPM resource bundles belong to the product.
    public var targets: [String]
    public var outputDirectory: URL
    public var version: String?
    public var infoPlist: URL?
    public var resources: URL?
    public var icons: [URL]
    public var zip: Bool
    public var appImage: Bool
    public var platform: BundlePlatform
    public var architecture: String

    public init(executable: URL, name: String, packageDirectory: URL, appRootCandidates: [URL] = [], targets: [String] = [],
                outputDirectory: URL, version: String? = nil, infoPlist: URL? = nil, resources: URL? = nil, icons: [URL] = [],
                zip: Bool = false, appImage: Bool = false, platform: BundlePlatform = .current, architecture: String = Bundler.hostArchitecture) {
        self.executable = executable
        self.name = name
        self.packageDirectory = packageDirectory
        self.appRootCandidates = appRootCandidates
        self.targets = targets
        self.outputDirectory = outputDirectory
        self.version = version
        self.infoPlist = infoPlist
        self.resources = resources
        self.icons = icons
        self.zip = zip
        self.appImage = appImage
        self.platform = platform
        self.architecture = architecture
    }
}

public struct BundleReport: Sendable {
    public var folder: URL
    public var bundledLibraries: [String] = []
    public var systemLibraries: [String] = []
    public var missingLibraries: [String] = []
    public var resourceBundles: [String] = []
    public var copiedFiles: [String] = []
    public var notes: [String] = []
    public var archive: URL?
    public var appImage: URL?
}

public enum BundleError: Error, CustomStringConvertible {
    case message(String)
    public var description: String { if case .message(let m) = self { return m }; return "" }
}

public final class Bundler {
    public let options: BundleOptions
    public private(set) var report: BundleReport
    private let fm = FileManager.default
    private let log: (String) -> Void

    public static var hostArchitecture: String {
        #if arch(x86_64)
        return "x86_64"
        #elseif arch(arm64)
        return "arm64"
        #else
        return "unknown"
        #endif
    }

    public init(options: BundleOptions, log: @escaping (String) -> Void = { print($0) }) {
        self.options = options
        self.report = BundleReport(folder: options.outputDirectory.appendingPathComponent(options.name, isDirectory: true))
        self.log = log
    }

    public var folder: URL { report.folder }

    @discardableResult
    public func run() throws -> BundleReport {
        guard fm.fileExists(atPath: options.executable.path) else { throw BundleError.message("no executable at \(options.executable.path)") }
        if fm.fileExists(atPath: folder.path) { try fm.removeItem(at: folder) }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let exeName = options.executable.lastPathComponent
        try copy(options.executable, to: folder.appendingPathComponent(exeName))
        report.copiedFiles.append(exeName)
        if options.platform == .windows { try copyProgramDatabase() }

        switch options.platform {
        case .windows: try collectWindowsLibraries()
        case .linux: try collectLinuxLibraries()
        case .macos:
            report.notes.append("macOS: the Swift runtime is part of the system; this folder is the host build's layout check, ship a Mac app with Xcode")
        }
        try copyResourceBundles()
        let plist = try copyAppFiles()

        let version = options.version ?? (plist?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
        if options.zip { report.archive = try makeZip(version: version) }
        if options.appImage {
            if options.platform == .linux { report.appImage = try makeAppImage(version: version, plist: plist) }
            else { report.notes.append("--appimage applies to Linux only; skipped") }
        }
        return report
    }

    // MARK: Copying

    private func copy(_ source: URL, to destination: URL) throws {
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        // Resolve symlinks: the folder holds real files (a zip of symlinks breaks on Windows).
        try fm.copyItem(at: source.resolvingSymlinksInPath(), to: destination)
    }

    // MARK: Windows

    private var windowsSearchPath: [URL] {
        let env = ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? env["Path"] ?? ""
        return path.split(separator: ";").map { URL(fileURLWithPath: String($0), isDirectory: true) }
    }

    private var systemRoot: String {
        let env = ProcessInfo.processInfo.environment
        return env["SystemRoot"] ?? env["SYSTEMROOT"] ?? env["windir"] ?? "C:\\Windows"
    }

    /// The Visual C++ redistributable directory: VCToolsRedistDir (a developer prompt), else
    /// the newest Visual Studio installation's VC\Redist\MSVC\<version>\<arch>\Microsoft.VC14x.CRT.
    private func visualCRedistDirectories() -> [URL] {
        let arch = options.architecture == "arm64" ? "arm64" : "x64"
        var roots: [URL] = []
        if let dir = ProcessInfo.processInfo.environment["VCToolsRedistDir"] { roots.append(URL(fileURLWithPath: dir, isDirectory: true)) }
        for programFiles in ["C:\\Program Files\\Microsoft Visual Studio", "C:\\Program Files (x86)\\Microsoft Visual Studio"] {
            let base = URL(fileURLWithPath: programFiles, isDirectory: true)
            for year in (try? fm.contentsOfDirectory(atPath: base.path))?.sorted(by: >) ?? [] {
                for edition in (try? fm.contentsOfDirectory(atPath: base.appendingPathComponent(year).path)) ?? [] {
                    let msvc = base.appendingPathComponent(year).appendingPathComponent(edition).appendingPathComponent("VC\\Redist\\MSVC")
                    for version in (try? fm.contentsOfDirectory(atPath: msvc.path))?.sorted(by: >) ?? [] where version.first?.isNumber == true {
                        roots.append(msvc.appendingPathComponent(version, isDirectory: true))
                    }
                }
            }
        }
        var result: [URL] = []
        for root in roots {
            let archDir = root.appendingPathComponent(arch, isDirectory: true)
            for crt in (try? fm.contentsOfDirectory(atPath: archDir.path))?.sorted(by: >) ?? [] where crt.hasPrefix("Microsoft.VC") && crt.hasSuffix(".CRT") {
                result.append(archDir.appendingPathComponent(crt, isDirectory: true))
            }
        }
        return result
    }

    private func findFile(_ name: String, in directories: [URL]) -> URL? {
        for dir in directories {
            let candidate = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: candidate.path) { return candidate }
            // NTFS is case-insensitive; FileManager on Windows honours that already.
        }
        return nil
    }

    private func collectWindowsLibraries() throws {
        let exeDir = options.executable.deletingLastPathComponent()
        let system32 = URL(fileURLWithPath: systemRoot, isDirectory: true).appendingPathComponent("System32", isDirectory: true)
        let redist = visualCRedistDirectories()
        var seen = Set<String>()
        var queue: [URL] = [options.executable]
        while !queue.isEmpty {
            let image = queue.removeFirst()
            let imports: [String]
            do { imports = try peImportedLibraries(try Data(contentsOf: image), name: image.lastPathComponent) }
            catch { report.notes.append("could not read the imports of \(image.lastPathComponent): \(error)"); continue }
            for dll in imports {
                let key = dll.lowercased()
                guard !LibraryPolicy.isWindowsAPISet(dll), seen.insert(key).inserted else { continue }
                if LibraryPolicy.isDebugCRuntime(dll) {
                    report.notes.append("\(dll) is the debug C runtime, which may not be redistributed: bundle a release build (-c release)")
                    report.missingLibraries.append(dll)
                    continue
                }
                if LibraryPolicy.isVisualCRuntime(dll) {
                    if let source = findFile(dll, in: redist) ?? findFile(dll, in: [system32]) {
                        try copy(source, to: folder.appendingPathComponent(source.lastPathComponent))
                        report.bundledLibraries.append("\(dll) (Visual C++ runtime, from \(source.deletingLastPathComponent().path))")
                    } else {
                        report.missingLibraries.append(dll)
                    }
                    continue
                }
                // The loader's order: the executable's directory, System32, the Windows
                // directory, then PATH (where the Swift runtime is on a developer machine).
                if let local = findFile(dll, in: [exeDir]) {
                    try copy(local, to: folder.appendingPathComponent(local.lastPathComponent))
                    report.bundledLibraries.append(dll)
                    queue.append(local)
                } else if findFile(dll, in: [system32, URL(fileURLWithPath: systemRoot, isDirectory: true)]) != nil {
                    report.systemLibraries.append(dll)
                } else if let found = findFile(dll, in: windowsSearchPath) {
                    if LibraryPolicy.isUnderWindowsDirectory(found.path, systemRoot: systemRoot) {
                        report.systemLibraries.append(dll)
                    } else {
                        try copy(found, to: folder.appendingPathComponent(found.lastPathComponent))
                        report.bundledLibraries.append(dll)
                        queue.append(found)
                    }
                } else {
                    report.missingLibraries.append(dll)
                }
            }
        }
    }

    // MARK: Linux

    @discardableResult
    static func runTool(_ executable: String, _ arguments: [String], environment: [String: String]? = nil) -> (status: Int32, output: String) {
        let process = Process()
        if executable.contains("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments
        }
        if let environment { process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 } }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// The first executable called `name` on PATH.
    public static func which(_ name: String) -> URL? {
        let env = ProcessInfo.processInfo.environment
        #if os(Windows)
        let separator: Character = ";"
        let names = [name + ".exe", name]
        #else
        let separator: Character = ":"
        let names = [name]
        #endif
        for dir in (env["PATH"] ?? env["Path"] ?? "").split(separator: separator) {
            for n in names {
                let candidate = URL(fileURLWithPath: String(dir), isDirectory: true).appendingPathComponent(n)
                if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }

    private func collectLinuxLibraries() throws {
        let ldd = Bundler.runTool("ldd", [options.executable.path])
        guard ldd.status == 0 else { throw BundleError.message("ldd \(options.executable.path) failed: \(ldd.output)") }
        var resolved: [String: String] = [:]
        for (soname, path) in LibraryPolicy.parseLdd(ldd.output) {
            if let path { resolved[soname] = path } else if !LibraryPolicy.isLinuxSystemLibrary(soname) { report.missingLibraries.append(soname) }
        }
        // Walk DT_NEEDED from the executable and stop at system libraries, so nothing that
        // only a system library needs (systemd under D-Bus, say) comes along.
        let exeInfo = try elfDynamicInfo(try Data(contentsOf: options.executable), name: options.executable.lastPathComponent)
        if !(exeInfo.runpath ?? "").contains("$ORIGIN") {
            report.notes.append("the executable has no $ORIGIN in its RUNPATH (\(exeInfo.runpath ?? "none")); it will not find the libraries beside it. Do not build with --disable-local-rpath.")
        }
        var seen = Set<String>()
        var queue = exeInfo.needed
        var needsOrigin: [URL] = []
        while !queue.isEmpty {
            let soname = queue.removeFirst()
            guard seen.insert(soname).inserted else { continue }
            if LibraryPolicy.isLinuxSystemLibrary(soname) { report.systemLibraries.append(soname); continue }
            guard let path = resolved[soname] else { continue }
            let source = URL(fileURLWithPath: path)
            let destination = folder.appendingPathComponent(soname)
            try copy(source, to: destination)
            report.bundledLibraries.append(soname)
            if let info = try? elfDynamicInfo(try Data(contentsOf: source), name: soname) {
                queue.append(contentsOf: info.needed)
                let bundledDependency = info.needed.contains { !LibraryPolicy.isLinuxSystemLibrary($0) }
                if bundledDependency, !(info.runpath ?? "").contains("$ORIGIN") { needsOrigin.append(destination) }
            }
        }
        // A library's own dependencies are looked up through its RUNPATH, not the
        // executable's: give the bundled ones without $ORIGIN one, so libcairo finds the
        // libpixman beside it instead of needing the system's.
        if !needsOrigin.isEmpty {
            if let patchelf = Bundler.which("patchelf") {
                for lib in needsOrigin {
                    let r = Bundler.runTool(patchelf.path, ["--set-rpath", "$ORIGIN", lib.path])
                    if r.status != 0 { report.notes.append("patchelf \(lib.lastPathComponent): \(r.output)") }
                }
                report.notes.append("set RUNPATH $ORIGIN on \(needsOrigin.count) bundled libraries with patchelf")
            } else {
                report.notes.append("patchelf not found: \(needsOrigin.count) bundled libraries (\(needsOrigin.map(\.lastPathComponent).prefix(4).joined(separator: ", "))…) find their own dependencies on the system rather than beside them; install patchelf for a fully self-contained folder")
            }
        }
    }

    // MARK: Resources

    private func copyResourceBundles() throws {
        let buildDir = options.executable.deletingLastPathComponent()
        guard let items = try? fm.contentsOfDirectory(atPath: buildDir.path) else { return }
        for item in items.sorted() where item.hasSuffix(".resources") || item.hasSuffix(".bundle") {
            let stem = (item as NSString).deletingPathExtension
            guard options.targets.contains(where: { stem.hasSuffix("_" + $0) }) else { continue }
            try copy(buildDir.appendingPathComponent(item), to: folder.appendingPathComponent(item))
            report.resourceBundles.append(item)
        }
    }

    /// The executable's PDB (`<name>.pdb` beside it, which the linker writes with `-debug`),
    /// copied so DbgHelp names functions in crash reports on the user's machine.
    private func copyProgramDatabase() throws {
        let pdb = options.executable.deletingPathExtension().appendingPathExtension("pdb")
        if fm.fileExists(atPath: pdb.path) {
            try copy(pdb, to: folder.appendingPathComponent(pdb.lastPathComponent))
            report.copiedFiles.append(pdb.lastPathComponent)
        } else {
            report.notes.append("no \(pdb.lastPathComponent) beside the executable: crash reports will give module offsets without function names (build with -Xswiftc -g -Xswiftc -debug-info-format=codeview -Xlinker -debug, as the plugin does)")
        }
    }

    /// The app's plist inside the executable target's own SwiftPM bundle, as the port finds
    /// it there (`Resources/` first, then the bundle; ADR-0045).
    private func ownBundlePlist(executableName name: String) -> URL? {
        let items = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        for item in items where item.hasSuffix("_\(name).resources") || item == "\(name).resources" || item.hasSuffix("_\(name).bundle") {
            if let url = Bundler.infoPlist(in: folder.appendingPathComponent(item, isDirectory: true), executableName: name) { return url }
        }
        return nil
    }

    /// Whether `url` is an application's Info.plist: it parses, and it is not a bundle's
    /// (`CFBundlePackageType` BNDL, or the `<id>.resources` identifier SwiftPM gives a
    /// resource bundle's plist).
    public static func isApplicationInfoPlist(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return false }
        if (plist["CFBundlePackageType"] as? String) == "BNDL" { return false }
        if let id = plist["CFBundleIdentifier"] as? String, id.hasSuffix(".resources") { return false }
        return true
    }

    /// The Info.plist an app root provides, in the names the port reads (ADR-0045):
    /// `Info.plist` or `<exe>-Info.plist` (SwiftPM refuses a resource named Info.plist), in
    /// `Resources/` first as the port searches it, when it is an application's.
    static func infoPlist(in dir: URL, executableName: String? = nil) -> URL? {
        let names = ["Info.plist"] + (executableName.map { ["\($0)-Info.plist"] } ?? [])
        for folder in [dir.appendingPathComponent("Resources", isDirectory: true), dir] {
            for name in names {
                let candidate = folder.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidate.path) && isApplicationInfoPlist(candidate) { return candidate }
            }
        }
        return nil
    }

    /// The directory that holds the app's Info.plist and Resources: the first candidate with
    /// an application `Info.plist` (or `Resources/Info.plist`) or a `Resources` directory.
    public static func appRoot(in candidates: [URL], executableName: String? = nil) -> URL? {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        for dir in candidates {
            if infoPlist(in: dir, executableName: executableName) != nil { return dir }
            if fm.fileExists(atPath: dir.appendingPathComponent("Resources").path, isDirectory: &isDirectory), isDirectory.boolValue { return dir }
        }
        return nil
    }

    private func copyAppFiles() throws -> [String: Any]? {
        let exeStem = options.executable.deletingPathExtension().lastPathComponent
        let root = Bundler.appRoot(in: options.appRootCandidates, executableName: exeStem)
        var plistURL = options.infoPlist
        if plistURL == nil, let root { plistURL = Bundler.infoPlist(in: root, executableName: exeStem) }
        var plist: [String: Any]?
        if let plistURL {
            try copy(plistURL, to: folder.appendingPathComponent("Info.plist"))
            report.copiedFiles.append("Info.plist (from \(plistURL.path))")
            if let data = try? Data(contentsOf: plistURL) {
                plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
            }
        }
        if plist == nil, let url = ownBundlePlist(executableName: exeStem), let data = try? Data(contentsOf: url) {
            plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
            report.notes.append("Info.plist read from \(url.path) (the port finds it in the executable's bundle)")
        }
        var resources = options.resources
        if resources == nil, let root {
            let r = root.appendingPathComponent("Resources", isDirectory: true)
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: r.path, isDirectory: &isDirectory), isDirectory.boolValue { resources = r }
        }
        if let resources {
            try copy(resources, to: folder.appendingPathComponent("Resources", isDirectory: true))
            report.copiedFiles.append("Resources/ (from \(resources.path))")
        }
        var icons = options.icons
        if icons.isEmpty, let root {
            let items = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
            icons = items.sorted().filter { $0.lowercased().hasSuffix(".ico") || $0.lowercased().hasSuffix(".png") }.map { root.appendingPathComponent($0) }
        }
        for icon in icons {
            try copy(icon, to: folder.appendingPathComponent(icon.lastPathComponent))
            report.copiedFiles.append(icon.lastPathComponent)
        }
        return plist
    }

    // MARK: Archives

    public static func archiveName(name: String, version: String, platform: BundlePlatform, architecture: String, ext: String) -> String {
        let safeVersion = version.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "/", with: "_")
        return "\(name)-\(safeVersion)-\(platform.rawValue)-\(architecture).\(ext)"
    }

    private func makeZip(version: String) throws -> URL {
        let zipURL = options.outputDirectory.appendingPathComponent(Bundler.archiveName(name: options.name, version: version, platform: options.platform, architecture: options.architecture, ext: "zip"))
        if fm.fileExists(atPath: zipURL.path) { try fm.removeItem(at: zipURL) }
        let parent = options.outputDirectory.path
        if options.platform == .windows, let tar = Bundler.which("tar") {
            // bsdtar (Windows 10 and later) writes a deflated ZIP when the name ends in .zip.
            let r = Bundler.runTool(tar.path, ["-a", "-c", "-f", zipURL.path, "-C", parent, options.name])
            if r.status == 0 { return zipURL }
            report.notes.append("tar -a failed (\(r.output.trimmingCharacters(in: .whitespacesAndNewlines))); writing an uncompressed zip")
        } else if options.platform != .windows, let zip = Bundler.which("zip") {
            let process = Process()
            process.executableURL = zip
            process.arguments = ["-q", "-r", zipURL.path, options.name]
            process.currentDirectoryURL = options.outputDirectory
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 { return zipURL }
            report.notes.append("zip failed with status \(process.terminationStatus); writing an uncompressed zip")
        } else {
            report.notes.append("no zip tool on PATH (zip, or tar on Windows); the archive is uncompressed")
        }
        try ZipWriter.write(try ZipWriter.entries(of: folder, prefix: options.name), to: zipURL)
        return zipURL
    }

    /// A 1×1 transparent PNG: appimagetool insists on an icon.
    static let placeholderPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!

    private func makeAppImage(version: String, plist: [String: Any]?) throws -> URL? {
        guard let tool = Bundler.which("appimagetool") ?? Bundler.which("appimagetool-x86_64.AppImage") ?? Bundler.which("appimagetool-aarch64.AppImage") else {
            report.notes.append("appimagetool is not on PATH; skipped the AppImage (the folder and zip are complete without it)")
            return nil
        }
        let appDir = options.outputDirectory.appendingPathComponent("\(options.name).AppDir", isDirectory: true)
        if fm.fileExists(atPath: appDir.path) { try fm.removeItem(at: appDir) }
        try fm.copyItem(at: folder, to: appDir)
        let exe = options.executable.lastPathComponent
        let appRun = appDir.appendingPathComponent("AppRun")
        try Data("#!/bin/sh\nHERE=\"$(dirname \"$(readlink -f \"$0\")\")\"\nexec \"$HERE/\(exe)\" \"$@\"\n".utf8).write(to: appRun)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appRun.path)
        let iconName = options.name.lowercased()
        let displayName = (plist?["CFBundleDisplayName"] as? String) ?? (plist?["CFBundleName"] as? String) ?? options.name
        let desktop = """
        [Desktop Entry]
        Type=Application
        Name=\(displayName)
        Exec=\(exe)
        Icon=\(iconName)
        Categories=Utility;
        X-AppImage-Version=\(version)

        """
        try Data(desktop.utf8).write(to: appDir.appendingPathComponent("\(iconName).desktop"))
        let png = (try? fm.contentsOfDirectory(atPath: folder.path))?.sorted().first { $0.lowercased().hasSuffix(".png") }
        if let png { try copy(folder.appendingPathComponent(png), to: appDir.appendingPathComponent("\(iconName).png")) }
        else { try Bundler.placeholderPNG.write(to: appDir.appendingPathComponent("\(iconName).png")) }
        let out = options.outputDirectory.appendingPathComponent(Bundler.archiveName(name: options.name, version: version, platform: .linux, architecture: options.architecture, ext: "AppImage"))
        if fm.fileExists(atPath: out.path) { try fm.removeItem(at: out) }
        // appimagetool is itself an AppImage; extract-and-run spares it FUSE (containers, CI).
        let arch = options.architecture == "arm64" ? "aarch64" : options.architecture
        let r = Bundler.runTool(tool.path, [appDir.path, out.path], environment: ["ARCH": arch, "APPIMAGE_EXTRACT_AND_RUN": "1"])
        try? fm.removeItem(at: appDir)
        guard r.status == 0 else {
            report.notes.append("appimagetool failed: \(r.output.split(separator: "\n").suffix(5).joined(separator: " | "))")
            return nil
        }
        return out
    }

    // MARK: Summary

    public func summary() -> String {
        var lines: [String] = []
        lines.append("Bundled \(options.name) into \(folder.path)")
        if !report.bundledLibraries.isEmpty { lines.append("  libraries (\(report.bundledLibraries.count)): \(report.bundledLibraries.joined(separator: ", "))") }
        if !report.systemLibraries.isEmpty { lines.append("  left to the system (\(report.systemLibraries.count)): \(report.systemLibraries.joined(separator: ", "))") }
        if !report.resourceBundles.isEmpty { lines.append("  resource bundles: \(report.resourceBundles.joined(separator: ", "))") }
        if report.copiedFiles.count > 1 { lines.append("  files: \(report.copiedFiles.joined(separator: ", "))") }
        if !report.missingLibraries.isEmpty { lines.append("  WARNING: not found, the app will not start without them: \(report.missingLibraries.joined(separator: ", "))") }
        for note in report.notes { lines.append("  note: \(note)") }
        if let a = report.archive { lines.append("Archive: \(a.path)") }
        if let a = report.appImage { lines.append("AppImage: \(a.path)") }
        return lines.joined(separator: "\n")
    }
}
