import XCTest
import Foundation
@testable import AppBundler

/// ADR-0046: the logic behind `swift package bundle`, on hand-built PE and ELF images so it
/// runs on every host.
final class BinaryImportsTests: XCTestCase {
    private func put16(_ d: inout Data, _ at: Int, _ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.replaceSubrange(at..<at + 2, with: $0) } }
    private func put32(_ d: inout Data, _ at: Int, _ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.replaceSubrange(at..<at + 4, with: $0) } }
    private func put64(_ d: inout Data, _ at: Int, _ v: UInt64) { withUnsafeBytes(of: v.littleEndian) { d.replaceSubrange(at..<at + 8, with: $0) } }
    private func putString(_ d: inout Data, _ at: Int, _ s: String) { let b = Array(s.utf8) + [0]; d.replaceSubrange(at..<at + b.count, with: b) }

    /// A PE32+ image with one section (RVA 0x1000 at file offset 0x200) holding an import
    /// table (swiftCore.dll, KERNEL32.dll) and a delay-load table (dbghelp.dll).
    private func makePE(delayUsesVA: Bool = false) -> Data {
        var d = Data(count: 0x400)
        putString(&d, 0, "MZ")
        put32(&d, 0x3C, 0x40)
        putString(&d, 0x40, "PE")
        put16(&d, 0x44, 0x8664)        // machine
        put16(&d, 0x46, 1)             // sections
        put16(&d, 0x54, 240)           // optional header size
        let opt = 0x58
        put16(&d, opt, 0x20B)
        let imageBase: UInt64 = 0x1_4000_0000
        put64(&d, opt + 24, imageBase)
        put32(&d, opt + 108, 16)
        put32(&d, opt + 112 + 8 * 1, 0x1000)      // import directory
        put32(&d, opt + 112 + 8 * 13, 0x1100)     // delay import directory
        let section = opt + 240
        put32(&d, section + 8, 0x200)    // virtual size
        put32(&d, section + 12, 0x1000)  // virtual address
        put32(&d, section + 16, 0x200)   // raw size
        put32(&d, section + 20, 0x200)   // raw pointer
        // Import descriptors at RVA 0x1000 (file 0x200), names at 0x1080 / 0x1090.
        put32(&d, 0x200 + 12, 0x1080); put32(&d, 0x200 + 16, 0x10C0)
        put32(&d, 0x214 + 12, 0x1090); put32(&d, 0x214 + 16, 0x10C8)
        putString(&d, 0x280, "swiftCore.dll")
        putString(&d, 0x290, "KERNEL32.dll")
        // Delay descriptor at RVA 0x1100 (file 0x300), name at RVA 0x1180 (file 0x380).
        if delayUsesVA {
            put32(&d, 0x300, 0)
            put32(&d, 0x304, UInt32(truncatingIfNeeded: imageBase + 0x1180))
        } else {
            put32(&d, 0x300, 1)
            put32(&d, 0x304, 0x1180)
        }
        putString(&d, 0x380, "dbghelp.dll")
        return d
    }

    func testPEImportsAndDelayImports() throws {
        XCTAssertEqual(try peImportedLibraries(makePE()), ["swiftCore.dll", "KERNEL32.dll", "dbghelp.dll"])
    }

    func testPEDelayImportsAddressedByVA() throws {
        // Old-style delay descriptors hold virtual addresses (the image base is subtracted);
        // the 32-bit truncation of the base keeps this case small.
        let names = try peImportedLibraries(makePE(delayUsesVA: true))
        XCTAssertEqual(names, ["swiftCore.dll", "KERNEL32.dll", "dbghelp.dll"])
    }

    func testNotPE() {
        XCTAssertThrowsError(try peImportedLibraries(Data("hello, world, this is not a PE file at all......................................".utf8)))
    }

    /// A minimal ELF64 shared object: one PT_LOAD at 0x400000 and a PT_DYNAMIC with two
    /// DT_NEEDED, a DT_RUNPATH and a DT_SONAME.
    private func makeELF(runpath: String?) -> Data {
        var d = Data(count: 0x400)
        d.replaceSubrange(0..<4, with: [0x7F, 0x45, 0x4C, 0x46])
        d[4] = 2; d[5] = 1; d[6] = 1
        put64(&d, 0x20, 64)       // e_phoff
        put16(&d, 0x36, 56)       // e_phentsize
        put16(&d, 0x38, 2)        // e_phnum
        // PT_LOAD
        put32(&d, 64, 1); put64(&d, 64 + 8, 0); put64(&d, 64 + 16, 0x400000); put64(&d, 64 + 32, 0x1000)
        // PT_DYNAMIC at file 0x200
        put32(&d, 120, 2); put64(&d, 120 + 8, 0x200); put64(&d, 120 + 32, 0x80)
        var strtab = "\0"
        func add(_ s: String) -> UInt64 { let o = UInt64(strtab.utf8.count); strtab += s + "\0"; return o }
        let a = add("libswiftCore.so"), b = add("libc.so.6"), so = add("libFoo.so.1")
        var entries: [(UInt64, UInt64)] = [(1, a), (1, b), (14, so)]
        if let runpath { entries.append((29, add(runpath))) }
        entries.append((5, 0x400300))
        entries.append((0, 0))
        for (i, e) in entries.enumerated() { put64(&d, 0x200 + i * 16, e.0); put64(&d, 0x200 + i * 16 + 8, e.1) }
        putString(&d, 0x300, "")
        d.replaceSubrange(0x300..<0x300 + strtab.utf8.count, with: Array(strtab.utf8))
        return d
    }

    func testELFDynamicSection() throws {
        let info = try elfDynamicInfo(makeELF(runpath: "$ORIGIN:/usr/lib/swift/linux"))
        XCTAssertEqual(info.needed, ["libswiftCore.so", "libc.so.6"])
        XCTAssertEqual(info.runpath, "$ORIGIN:/usr/lib/swift/linux")
        XCTAssertEqual(info.soname, "libFoo.so.1")
        XCTAssertNil(try elfDynamicInfo(makeELF(runpath: nil)).runpath)
    }

    func testNotELF() {
        XCTAssertThrowsError(try elfDynamicInfo(makePE()))
    }
}

final class LibraryPolicyTests: XCTestCase {
    func testWindowsClassification() {
        XCTAssertTrue(LibraryPolicy.isWindowsAPISet("api-ms-win-crt-runtime-l1-1-0.dll"))
        XCTAssertTrue(LibraryPolicy.isWindowsAPISet("EXT-MS-win-foo.dll"))
        XCTAssertFalse(LibraryPolicy.isWindowsAPISet("swiftCore.dll"))
        XCTAssertTrue(LibraryPolicy.isVisualCRuntime("VCRUNTIME140.dll"))
        XCTAssertTrue(LibraryPolicy.isVisualCRuntime("msvcp140_1.dll"))
        XCTAssertFalse(LibraryPolicy.isVisualCRuntime("ucrtbase.dll"))
        XCTAssertTrue(LibraryPolicy.isDebugCRuntime("ucrtbased.dll"))
        XCTAssertTrue(LibraryPolicy.isUnderWindowsDirectory("C:\\Windows\\System32\\kernel32.dll", systemRoot: "C:\\Windows"))
        XCTAssertTrue(LibraryPolicy.isUnderWindowsDirectory("c:/windows/system32/USER32.dll", systemRoot: "C:\\WINDOWS\\"))
        XCTAssertFalse(LibraryPolicy.isUnderWindowsDirectory("C:\\WindowsApps\\x.dll", systemRoot: "C:\\Windows"))
        XCTAssertFalse(LibraryPolicy.isUnderWindowsDirectory("C:\\Users\\me\\AppData\\Local\\Programs\\Swift\\Runtimes\\6.2.0\\usr\\bin\\swiftCore.dll", systemRoot: "C:\\Windows"))
    }

    func testLinuxClassification() {
        for system in ["libc.so.6", "libm.so.6", "ld-linux-x86-64.so.2", "ld-linux-aarch64.so.1", "libstdc++.so.6", "libgcc_s.so.1",
                       "libX11.so.6", "libxcb.so.1", "libxcb-shm.so.0", "libwayland-client.so.0", "libxkbcommon.so.0",
                       "libfontconfig.so.1", "libfreetype.so.6", "libharfbuzz.so.0", "libdbus-1.so.3", "libGL.so.1", "libnss_files.so.2"] {
            XCTAssertTrue(LibraryPolicy.isLinuxSystemLibrary(system), system)
        }
        for bundled in ["libswiftCore.so", "libFoundation.so", "libFoundationEssentials.so", "lib_FoundationICU.so", "libdispatch.so",
                        "libBlocksRuntime.so", "libswift_Concurrency.so", "libcairo.so.2", "libpango-1.0.so.0", "libpangocairo-1.0.so.0",
                        "libglib-2.0.so.0", "libpixman-1.so.0", "libXext.so.6"] {
            XCTAssertFalse(LibraryPolicy.isLinuxSystemLibrary(bundled), bundled)
        }
    }

    func testParseLdd() {
        let output = """
        \tlinux-vdso.so.1 (0x00007ffd5b9f0000)
        \tlibswiftCore.so => /usr/lib/swift/linux/libswiftCore.so (0x00007f1c2a200000)
        \tlibcairo.so.2 => /lib/x86_64-linux-gnu/libcairo.so.2 (0x00007f1c2a000000)
        \tlibmissing.so.1 => not found
        \t/lib64/ld-linux-x86-64.so.2 (0x00007f1c2b000000)
        """
        let parsed = LibraryPolicy.parseLdd(output)
        XCTAssertEqual(parsed.map(\.soname), ["libswiftCore.so", "libcairo.so.2", "libmissing.so.1"])
        XCTAssertEqual(parsed[0].path, "/usr/lib/swift/linux/libswiftCore.so")
        XCTAssertEqual(parsed[1].path, "/lib/x86_64-linux-gnu/libcairo.so.2")
        XCTAssertNil(parsed[2].path)
    }
}

final class BundlerTests: XCTestCase {
    private var temp: URL!

    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("appbundler-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temp)
    }

    func testArchiveName() {
        XCTAssertEqual(Bundler.archiveName(name: "MDVault", version: "1.2", platform: .windows, architecture: "x86_64", ext: "zip"), "MDVault-1.2-windows-x86_64.zip")
        XCTAssertEqual(Bundler.archiveName(name: "App", version: "1.0 beta/2", platform: .linux, architecture: "arm64", ext: "AppImage"), "App-1.0_beta_2-linux-arm64.AppImage")
    }

    func testZipWriterRoundTrip() throws {
        let entries = [ZipWriter.Entry(path: "App/", data: Data(), mode: 0o755),
                       ZipWriter.Entry(path: "App/App", data: Data("binary".utf8), mode: 0o755),
                       ZipWriter.Entry(path: "App/Info.plist", data: Data("<plist/>".utf8), mode: 0o644)]
        let url = temp.appendingPathComponent("a.zip")
        try ZipWriter.write(entries, to: url)
        let data = try Data(contentsOf: url)
        XCTAssertEqual(ZipWriter.listNames(data), ["App/", "App/App", "App/Info.plist"])
        XCTAssertEqual(ZipWriter.crc32(Data("123456789".utf8)), 0xCBF4_3926)
        #if !os(Windows)
        // The system's unzip agrees, when there is one.
        if let unzip = Bundler.which("unzip") {
            let r = Bundler.runTool(unzip.path, ["-t", url.path])
            XCTAssertEqual(r.status, 0, r.output)
        }
        #endif
    }

    func testAppRootFindsTheNearestInfoPlistOrResources() throws {
        let fm = FileManager.default
        let pkg = temp.appendingPathComponent("pkg", isDirectory: true)
        let app = pkg.appendingPathComponent("Examples/App", isDirectory: true)
        let sources = app.appendingPathComponent("Sources/App", isDirectory: true)
        try fm.createDirectory(at: sources, withIntermediateDirectories: true)
        try fm.createDirectory(at: app.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        let chain = [sources, sources.deletingLastPathComponent(), app, app.deletingLastPathComponent(), pkg]
        XCTAssertEqual(Bundler.appRoot(in: chain)?.standardizedFileURL.path, app.standardizedFileURL.path)
        XCTAssertNil(Bundler.appRoot(in: [sources]))
    }

    /// A bundle of a fake executable: the folder holds it, the app's Info.plist, Resources
    /// and icon, and the product's resource bundle (not another target's); --zip names the
    /// archive from CFBundleShortVersionString. The library walk is skipped (not a real
    /// binary), so this runs as the macOS layout on every host.
    func testLayoutResourcesAndZip() throws {
        let fm = FileManager.default
        let build = temp.appendingPathComponent("build", isDirectory: true)
        try fm.createDirectory(at: build.appendingPathComponent("Pkg_App.resources"), withIntermediateDirectories: true)
        try Data("r".utf8).write(to: build.appendingPathComponent("Pkg_App.resources/data.txt"))
        try fm.createDirectory(at: build.appendingPathComponent("Pkg_Other.resources"), withIntermediateDirectories: true)
        let exe = build.appendingPathComponent("App")
        try Data("not really an executable".utf8).write(to: exe)
        let root = temp.appendingPathComponent("app", isDirectory: true)
        try fm.createDirectory(at: root.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.example.App", "CFBundleShortVersionString": "2.5", "CFBundleName": "App"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: root.appendingPathComponent("Resources/Info.plist"))
        try Data("doc".utf8).write(to: root.appendingPathComponent("Resources/Welcome.md"))
        try Bundler.placeholderPNG.write(to: root.appendingPathComponent("AppIcon.png"))

        let out = temp.appendingPathComponent("out", isDirectory: true)
        let options = BundleOptions(executable: exe, name: "App", packageDirectory: temp, appRootCandidates: [root], targets: ["App"],
                                    outputDirectory: out, zip: true, platform: .macos, architecture: "arm64")
        let bundler = Bundler(options: options, log: { _ in })
        let report = try bundler.run()
        let folder = out.appendingPathComponent("App")
        for item in ["App", "Info.plist", "Resources/Welcome.md", "AppIcon.png", "Pkg_App.resources/data.txt"] {
            XCTAssertTrue(fm.fileExists(atPath: folder.appendingPathComponent(item).path), item)
        }
        XCTAssertFalse(fm.fileExists(atPath: folder.appendingPathComponent("Pkg_Other.resources").path))
        XCTAssertEqual(report.resourceBundles, ["Pkg_App.resources"])
        let archive = try XCTUnwrap(report.archive)
        XCTAssertEqual(archive.lastPathComponent, "App-2.5-macos-arm64.zip")
        XCTAssertTrue(fm.fileExists(atPath: archive.path))
        // Running again replaces the folder rather than nesting into it.
        _ = try Bundler(options: options, log: { _ in }).run()
        XCTAssertFalse(fm.fileExists(atPath: folder.appendingPathComponent("App/App").path))
    }

    #if os(Linux)
    /// The real thing on Linux: this test runner's own closure. The Swift runtime comes
    /// along, glibc does not.
    func testLinuxClosureOfTheTestRunner() throws {
        let exe = URL(fileURLWithPath: "/proc/self/exe").resolvingSymlinksInPath()
        let out = temp.appendingPathComponent("out", isDirectory: true)
        let options = BundleOptions(executable: exe, name: "Runner", packageDirectory: temp, outputDirectory: out, platform: .linux)
        let report = try Bundler(options: options, log: { _ in }).run()
        XCTAssertTrue(report.bundledLibraries.contains("libswiftCore.so"), "\(report.bundledLibraries)")
        XCTAssertTrue(report.systemLibraries.contains("libc.so.6"), "\(report.systemLibraries)")
        XCTAssertFalse(report.bundledLibraries.contains { LibraryPolicy.isLinuxSystemLibrary($0) })
    }
    #endif
}
