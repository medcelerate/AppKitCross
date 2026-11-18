// The app bundle on Windows and Linux (ADR-0045): the layout around the executable, the
// Info.plist, resources and asset catalogs, localization (.strings, .stringsdict plurals,
// String Catalogs, the user's languages), the app icon, the registration plan and the
// single-instance hand-off. The fixture app folder is Tests/AppKitTests/Fixtures/SampleApp
// (read from the source tree; copied to a temporary folder with a stand-in executable).

import XCTest
@testable import AppKit
@testable import SwiftUI

final class BundleTests: XCTestCase {
    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/SampleApp", isDirectory: true)
    var folder: URL!
    var exe: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("BundleTests-\(UUID().uuidString)/SampleApp", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Self.fixture, to: folder)
        #if os(Windows)
        exe = folder.appendingPathComponent("SampleApp.exe")
        #else
        exe = folder.appendingPathComponent("SampleApp")
        #endif
        try Data().write(to: exe)
        _PreferredLanguages._override(["de-AT", "en"])
    }
    override func tearDownWithError() throws {
        _PreferredLanguages._override(nil)
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
    }

    func app(_ env: [String: String] = [:]) -> _AppBundle { _AppBundle(layout: _BundleLayout(executableURL: exe, environment: env)) }

    // MARK: Layout and Info.plist

    func testLayoutSearchesResourcesTheModuleBundleThenTheFolder() throws {
        let layout = app().layout
        XCTAssertEqual(layout.bundleURL.standardizedFileURL.path, folder.standardizedFileURL.path)
        XCTAssertEqual(layout.resourceRoots.map(\.lastPathComponent), ["Resources", "Resources", "SampleKit_SampleApp.resources", "SampleApp"])
        XCTAssertEqual(layout.executableName, "SampleApp")
        XCTAssertEqual(layout.infoPlistURL?.lastPathComponent, "Info.plist")
        XCTAssertEqual(app().resourceURL.lastPathComponent, "Resources")
    }

    func testInfoPlistNextToTheExecutableInResourcesOrNamedByTheEnvironment() throws {
        XCTAssertEqual(app().bundleIdentifier, "com.example.sampleapp")
        // Moved into Resources/: still found.
        try FileManager.default.moveItem(at: folder.appendingPathComponent("Info.plist"), to: folder.appendingPathComponent("Resources/Info.plist"))
        XCTAssertEqual(app().bundleIdentifier, "com.example.sampleapp")
        // `<Exe>-Info.plist` in the module bundle (SwiftPM refuses a resource named Info.plist).
        try FileManager.default.moveItem(at: folder.appendingPathComponent("Resources/Info.plist"), to: folder.appendingPathComponent("SampleKit_SampleApp.resources/SampleApp-Info.plist"))
        XCTAssertEqual(app().infoPlistURL()?.lastPathComponent, "SampleApp-Info.plist")
        // APPKITWIN_INFO_PLIST wins.
        let other = folder.deletingLastPathComponent().appendingPathComponent("Other.plist")
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.example.other"], format: .xml, options: 0).write(to: other)
        XCTAssertEqual(app(["APPKITWIN_INFO_PLIST": other.path]).bundleIdentifier, "com.example.other")
    }

    func testBareExecutableGetsNameFallbacksButNoIdentifier() throws {
        try FileManager.default.removeItem(at: folder.appendingPathComponent("Info.plist"))
        for lang in ["en", "de"] { try FileManager.default.removeItem(at: folder.appendingPathComponent("Resources/\(lang).lproj/InfoPlist.strings")) }
        let a = app()
        XCTAssertNil(a.bundleIdentifier)
        XCTAssertEqual(a.infoDictionary["CFBundleName"] as? String, "SampleApp")
        XCTAssertEqual(a.infoDictionary["CFBundleExecutable"] as? String, "SampleApp")
        XCTAssertEqual(a.developmentLocalization, "en")
        XCTAssertEqual(a.platformIdentifier, "AppKitCross.SampleApp")
        XCTAssertEqual(a.displayName, "SampleApp")
    }

    func testInfoPlistStringsLocalizeTheDisplayName() {
        XCTAssertEqual(app().displayName, "Beispiel-App")   // de.lproj/InfoPlist.strings is UTF-16
        XCTAssertEqual(app().localizedInfoDictionary["CFBundleDisplayName"] as? String, "Beispiel-App")
        _PreferredLanguages._override(["fr"])
        XCTAssertEqual(app().displayName, "Sample App")       // fr has none: the development region's
    }

    // MARK: Resources

    func testResourceLookupUnlocalizedFirstThenThePreferredLproj() {
        let a = app()
        XCTAssertEqual(a.url(forResource: "pic", withExtension: "png")?.lastPathComponent, "pic.png")
        XCTAssertEqual(a.url(forResource: "pic.png", withExtension: nil)?.lastPathComponent, "pic.png")
        XCTAssertEqual(a.url(forResource: "Localizable", withExtension: "strings")?.deletingLastPathComponent().lastPathComponent, "de.lproj")
        XCTAssertEqual(a.url(forResource: "Localizable", withExtension: "strings", localization: "fr")?.deletingLastPathComponent().lastPathComponent, "fr.lproj")
        XCTAssertEqual(a.url(forResource: "module-only", withExtension: "txt")?.lastPathComponent, "module-only.txt")
        XCTAssertNil(a.url(forResource: "missing", withExtension: "png"))
        XCTAssertEqual(a.url(forResource: "gear", withExtension: "png", subdirectory: "Assets.xcassets/Icons/gear.imageset")?.lastPathComponent, "gear.png")
        let pngs = a.urls(forResourcesWithExtension: "png").map(\.lastPathComponent)
        XCTAssertTrue(pngs.contains("AppIcon.png") && pngs.contains("pic@2x.png"), "\(pngs)")
    }

    func testNamedImagesFilesWithScaledSiblingsAndAssetCatalogSets() throws {
        let a = app()
        let pic = try XCTUnwrap(NSImage._loadResource("pic", in: a))
        XCTAssertEqual(pic.size, NSSize(width: 4, height: 3))
        XCTAssertEqual(pic.representations.map { $0.pixelsWide }.sorted(), [4, 8])
        let star = try XCTUnwrap(NSImage._loadResource("Star", in: a))
        XCTAssertEqual(star.size, NSSize(width: 10, height: 10))
        XCTAssertEqual(star.representations.count, 2, "the dark variant and the missing 3x are skipped")
        XCTAssertTrue(star.isTemplate)
        XCTAssertNotNil(NSImage._loadResource("Icons/gear", in: a))
        XCTAssertNil(NSImage._loadResource("gear", in: a), "a namespaced asset needs its namespace")
        let icon = try XCTUnwrap(_NSAssetCatalog.image(named: "AppIcon", roots: a.layout.resourceRoots))
        XCTAssertEqual(icon.size, NSSize(width: 32, height: 32))
        XCTAssertEqual(icon.representations.map { $0.pixelsWide }.sorted(), [16, 32, 32, 64])
    }

    func testDataAssetsAndNibLookups() throws {
        let bundle = try XCTUnwrap(Bundle(url: folder))
        let blob = try XCTUnwrap(NSDataAsset(name: "Blob", bundle: bundle))
        XCTAssertEqual(blob.typeIdentifier, "public.json")
        XCTAssertEqual((try JSONSerialization.jsonObject(with: blob.data) as? [String: Int])?["answer"], 42)
        XCTAssertEqual(blob.data, try Data(contentsOf: folder.appendingPathComponent("Resources/Assets.xcassets/Blob.dataset/blob.json")), "the file's bytes, unchanged")
        XCTAssertNil(NSDataAsset(name: "Nope", bundle: bundle))
        XCTAssertEqual((blob.copy() as? NSDataAsset)?.data, blob.data)
        XCTAssertEqual(MainActor.assumeIsolated { NSNib(nibNamed: "Help", bundle: bundle)?._url?.lastPathComponent }, "Help.nib")
        XCTAssertTrue(MainActor.assumeIsolated { NSNib(nibNamed: "Missing", bundle: bundle) == nil })
    }

    @MainActor func testAppIconFromTheInfoPlist() throws {
        let icon = try XCTUnwrap(_AppIcon.load(app()))
        XCTAssertEqual(icon.representations.first?.pixelsWide, 32)
        // CFBundleIconName names the asset catalog's app icon set.
        let plist = folder.appendingPathComponent("Info.plist")
        var info = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as? [String: Any])
        info["CFBundleIconName"] = "AppIcon"
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plist)
        let set = try XCTUnwrap(_AppIcon.load(app()))
        XCTAssertEqual(set.representations.count, 4)
    }

    @MainActor func testApplicationIconImageRoundTrips() {
        let app = NSApplication.shared
        let image = NSImage(size: NSSize(width: 16, height: 16))
        app.applicationIconImage = image
        XCTAssertTrue(app.applicationIconImage === image)
        XCTAssertTrue(app._applicationIconImageIfSet === image)
        app.applicationIconImage = nil
        XCTAssertFalse(app.applicationIconImage === image)
    }

    // MARK: Localization

    func testPreferredLocalizationMatching() {
        let available = ["Base", "de", "en", "fr", "pt-BR", "zh-Hans"]
        XCTAssertEqual(_LocalizationMatching.preferred(from: available, preferences: ["de-AT"], development: "en"), ["de"])
        XCTAssertEqual(_LocalizationMatching.preferred(from: available, preferences: ["ja", "fr-CA"], development: "en"), ["fr"])
        XCTAssertEqual(_LocalizationMatching.preferred(from: available, preferences: ["pt"], development: "en"), ["pt-BR"])
        XCTAssertEqual(_LocalizationMatching.preferred(from: available, preferences: ["zh-Hans-CN"], development: "en"), ["zh-Hans"])
        XCTAssertEqual(_LocalizationMatching.preferred(from: available, preferences: ["ja"], development: "en"), ["en"])
        XCTAssertEqual(_LocalizationMatching.preferred(from: ["English", "German"], preferences: ["de"], development: "English"), ["German"])
        XCTAssertEqual(app().localizations, ["de", "en", "fr"])
        XCTAssertEqual(app().preferredLocalizations, ["de"])
    }

    func testSystemLanguagesFromTheEnvironmentAndTheCommandLine() {
        XCTAssertEqual(_PreferredLanguages.posixLanguages(["LANG": "de_DE.UTF-8"]), ["de-DE"])
        XCTAssertEqual(_PreferredLanguages.posixLanguages(["LANG": "fr_FR.UTF-8", "LANGUAGE": "de:en_GB"]), ["de", "en-GB", "fr-FR"])
        XCTAssertEqual(_PreferredLanguages.posixLanguages(["LANG": "C", "LANGUAGE": "de"]), ["en"], "LANGUAGE is ignored under the C locale")
        XCTAssertEqual(_PreferredLanguages.posixLanguages(["LANG": "C", "LC_MESSAGES": "pt_BR.UTF-8"]), ["pt-BR"])
        XCTAssertEqual(_PreferredLanguages.posixLanguages(["LC_ALL": "sr_RS@latin", "LANG": "en_US"]), ["sr-Latn-RS"])
        XCTAssertEqual(_PreferredLanguages.appleLanguagesArgument(["app", "-AppleLanguages", "(de, \"en-GB\")"]), ["de", "en-GB"])
        XCTAssertEqual(_PreferredLanguages.appleLanguagesArgument(["app", "-AppleLanguages", "fr"]), ["fr"])
        XCTAssertNil(_PreferredLanguages.appleLanguagesArgument(["app"]))
    }

    func testStringsFileFormat() throws {
        let en = try XCTUnwrap(_StringsFile.parse(Data(contentsOf: folder.appendingPathComponent("Resources/en.lproj/Localizable.strings"))))
        XCTAssertEqual(en["greeting"], "Hello")
        XCTAssertEqual(en["plain"], "word")
        XCTAssertEqual(en["only key"], "only key")
        XCTAssertEqual(en["escaped"], "Tab\there \"quoted\" é")
        XCTAssertEqual(_StringsFile.parse("{ \"a\" = \"b\"; }"), ["a": "b"])
        XCTAssertEqual(_StringsFile.parse(Data("\"k\" = \"v\";".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }.reduce(into: Data([0xFF, 0xFE])) { $0.append($1) })), ["k": "v"])
    }

    func testLocalizedStringsFollowThePreferredLanguageWithFallbacks() {
        let a = app()
        XCTAssertEqual(a.localizedString(forKey: "greeting", value: nil, table: nil), "Hallo")
        XCTAssertEqual(a.localizedString(forKey: "plain", value: nil, table: nil), "word", "missing in de: the development region's")
        XCTAssertEqual(a.localizedString(forKey: "nowhere", value: "Default", table: nil), "Default")
        XCTAssertEqual(a.localizedString(forKey: "nowhere", value: "", table: nil), "nowhere")
        XCTAssertEqual(a.localizedString(forKey: "%@ says hi", defaultValue: nil, table: nil, locale: nil, arguments: ["Ada"]), "Ada sagt Hallo")
        _PreferredLanguages._override(["fr-FR"])
        XCTAssertEqual(app().localizedString(forKey: "greeting", value: nil, table: nil), "Bonjour")
        _PreferredLanguages._override(["ja"])
        XCTAssertEqual(app().localizedString(forKey: "greeting", value: nil, table: nil), "Hello")
    }

    func testStringsdictPluralsAndPositions() {
        let a = app()
        func files(_ n: Int) -> String { a.localizedString(forKey: "%lld files", defaultValue: nil, table: nil, locale: nil, arguments: [n]) }
        XCTAssertEqual(files(1), "1 Datei")
        XCTAssertEqual(files(3), "3 Dateien")
        XCTAssertEqual(files(0), "keine Dateien", "zero wins for 0 when the rule has it")
        let mixed = a.localizedString(forKey: "%lld folders in %@ with %lld files", defaultValue: nil, table: nil, locale: nil, arguments: [1, "Home", 5])
        XCTAssertEqual(mixed, "ein Ordner in Home: 5 Dateien", "a variant without a number keeps the later arguments in place")
        // Bundle.localizedString has no arguments: the `other` forms, conversions sequential.
        XCTAssertEqual(a.localizedString(forKey: "%lld files", value: nil, table: nil), "%lld Dateien")
        XCTAssertEqual(a.localizedString(forKey: "%lld folders in %@ with %lld files", value: nil, table: nil), "%lld Ordner in %@: %lld Dateien")
        // A translation that reorders its arguments.
        XCTAssertEqual(_PluralFormat.format(.string("%2$@ von %1$@"), language: "de", locale: nil, arguments: ["A", "B"]), "B von A")
        XCTAssertEqual(String(format: a.localizedString(forKey: "%lld files", value: nil, table: nil), 7), "7 Dateien")
        _PreferredLanguages._override(["en"])
        XCTAssertEqual(app().localizedString(forKey: "%lld files", defaultValue: nil, table: nil, locale: nil, arguments: [1]), "1 file")
    }

    func testPluralRules() {
        XCTAssertEqual([0, 1, 2, 5].map { _PluralRules.category(of: Double($0), language: "en") }, ["other", "one", "other", "other"])
        XCTAssertEqual([0, 1, 2].map { _PluralRules.category(of: Double($0), language: "fr") }, ["one", "one", "other"])
        XCTAssertEqual([1, 2, 5, 11, 21, 22, 25, 112].map { _PluralRules.category(of: Double($0), language: "ru") },
                       ["one", "few", "many", "many", "one", "few", "many", "many"])
        XCTAssertEqual([1, 2, 5, 12, 22].map { _PluralRules.category(of: Double($0), language: "pl") }, ["one", "few", "many", "many", "few"])
        XCTAssertEqual([1, 3, 5].map { _PluralRules.category(of: Double($0), language: "cs") }, ["one", "few", "other"])
        XCTAssertEqual([0, 1, 2, 3, 11, 100].map { _PluralRules.category(of: Double($0), language: "ar") }, ["zero", "one", "two", "few", "many", "other"])
        XCTAssertEqual(_PluralRules.category(of: 7, language: "ja"), "other")
        XCTAssertEqual(_PluralRules.category(of: 1.5, language: "en"), "other")
    }

    func testStringCatalogs() {
        let a = app()
        XCTAssertEqual(a.localizedString(forKey: "Open", value: nil, table: "Catalog"), "Öffnen")
        XCTAssertEqual(a.localizedString(forKey: "%lld items", defaultValue: nil, table: "Catalog", locale: nil, arguments: [1]), "1 Element")
        XCTAssertEqual(a.localizedString(forKey: "%lld items", defaultValue: nil, table: "Catalog", locale: nil, arguments: [4]), "4 Elemente")
        XCTAssertTrue(a.localizations.contains("de"))
        _PreferredLanguages._override(["en"])
        XCTAssertEqual(app().localizedString(forKey: "Open", value: nil, table: "Catalog"), "Open", "the source language's key is its value")
        XCTAssertEqual(app().localizedString(forKey: "%lld items", defaultValue: nil, table: "Catalog", locale: nil, arguments: [2]), "2 items")
    }

    func testLocalizationKeysUseApplesFormatSpecifiers() throws {
        var k = _LocalizationKey("Copied ")
        k.append(3, specifier: _LocalizationKey.specifier(for: 3))
        k.appendLiteral(" files (100%)")
        XCTAssertEqual(k.key, "Copied %lld files (100%%)")
        XCTAssertEqual(k.fallback, "Copied 3 files (100%)")
        XCTAssertEqual(_LocalizationKey.specifier(for: 2.5), "%lf")
        XCTAssertEqual(_LocalizationKey.specifier(for: "x"), "%@")
        let bundle = try XCTUnwrap(Bundle(url: folder))
        var files = _LocalizationKey()
        files.append(1, specifier: "%lld")
        files.appendLiteral(" files")
        XCTAssertEqual(files.resolve(table: nil, bundle: bundle, locale: nil), "1 Datei")
    }

    @MainActor func testSwiftUITextLooksUpItsKey() throws {
        let bundle = try XCTUnwrap(Bundle(url: folder))
        XCTAssertEqual(Text("greeting", bundle: bundle)._string, "Hallo")
        let n = 3
        let key: LocalizedStringKey = "\(n) files"
        XCTAssertEqual(key._raw.key, "%lld files")
        XCTAssertEqual(Text(key, bundle: bundle)._string, "3 Dateien")
        XCTAssertEqual(Text("untranslated \(n)", bundle: bundle)._string, "untranslated 3")
        XCTAssertEqual(Text(verbatim: "greeting")._string, "greeting")
    }

    #if !canImport(Darwin)
    /// corelibs' Bundle answers through the port (the vtable hooks of BundleHooks.swift).
    func testCorelibsBundleIsRouted() throws {
        _AppBundle.installMainBundle()
        XCTAssertTrue(_AppBundle.isMainBundleInstalled, _BundleHooks.installFailure ?? "")
        let bundle = try XCTUnwrap(Bundle(url: folder))
        XCTAssertEqual(bundle.localizedString(forKey: "greeting", value: nil, table: nil), "Hallo")
        XCTAssertEqual(bundle.preferredLocalizations, ["de"])
        XCTAssertEqual(String.localizedStringWithFormat(bundle.localizedString(forKey: "%lld files", value: nil, table: nil), 2), "2 Dateien", "a .stringsdict key no longer crashes corelibs")
        XCTAssertEqual(NSLocalizedString("greeting", bundle: bundle, comment: ""), "Hallo")
        let noPlist = try XCTUnwrap(Bundle(url: folder.appendingPathComponent("SampleKit_SampleApp.resources")))
        XCTAssertEqual(noPlist.developmentLocalization, "en", "corelibs traps without CFBundleDevelopmentRegion")
        // The main bundle's Info.plist and resources come from the app layout.
        XCTAssertEqual(Bundle.main.infoDictionary?["CFBundleName"] as? String, _AppBundle.main.infoDictionary["CFBundleName"] as? String)
        XCTAssertEqual(Bundle.main.resourceURL, _AppBundle.main.resourceURL)
        // Foundation's own API the port adds.
        XCTAssertEqual(String(localized: "greeting", bundle: bundle), "Hallo")
        let n = 1
        XCTAssertEqual(String(localized: "\(n) files", bundle: bundle), "1 Datei")
        XCTAssertEqual(String(localized: "greeting.title", defaultValue: "Hi \(n)", bundle: bundle), "Hi 1")
        XCTAssertEqual(String(localized: LocalizedStringResource("greeting", bundle: .atURL(folder))), "Hallo")
    }
    #endif

    // MARK: Registration

    func testRegistrationPlanForWindows() throws {
        let plan = _AppRegistration(app: app(), executablePath: #"C:\Program Files\Sample\SampleApp.exe"#)
        XCTAssertEqual(plan.identifier, "com.example.sampleapp")
        XCTAssertEqual(plan.documentTypes.map(\.progID), ["com.example.sampleapp.MarkdownDocument", "com.example.sampleapp.SampleDocument"])
        XCTAssertEqual(plan.documentTypes[0].extensions, ["md", "markdown"])
        XCTAssertEqual(plan.documentTypes[0].mimeTypes, ["text/markdown"])
        XCTAssertEqual(plan.documentTypes[1].mimeTypes, ["application/x-com.example.sampleapp-sample-document"])
        XCTAssertEqual(plan.windowsOpenCommand, #""C:\Program Files\Sample\SampleApp.exe" "%1""#)
        let values = plan.windowsRegistryValues
        func value(_ key: String, _ name: String?) -> _AppRegistration.RegistryValue? { values.first { $0.key == key && $0.name == name } }
        XCTAssertEqual(value(#"Software\Classes\com.example.sampleapp.MarkdownDocument\shell\open\command"#, nil)?.value, plan.windowsOpenCommand)
        XCTAssertEqual(value(#"Software\Classes\.md\OpenWithProgids"#, "com.example.sampleapp.MarkdownDocument")?.value, "")
        XCTAssertEqual(value(#"Software\Classes\.md"#, nil)?.condition, .ifAbsent, "the extension's default only when nothing claims it")
        XCTAssertNil(value(#"Software\Classes\.smpl"#, nil), "an Alternate type never becomes the default")
        XCTAssertEqual(value(#"Software\Classes\sample"#, "URL Protocol")?.value, "")
        XCTAssertEqual(value(#"Software\Classes\Applications\SampleApp.exe\SupportedTypes"#, ".smpl")?.value, "")
        XCTAssertEqual(value(#"Software\RegisteredApplications"#, "com.example.sampleapp")?.value, #"Software\AppKitCross\com.example.sampleapp\Capabilities"#)
        XCTAssertEqual(value(#"Software\AppKitCross\com.example.sampleapp\Capabilities\FileAssociations"#, ".markdown")?.value, "com.example.sampleapp.MarkdownDocument")
        XCTAssertEqual(plan.windowsOwnedKeys.count, 4)
    }

    func testRegistrationForLinuxDesktops() throws {
        var plan = _AppRegistration(app: app(), executablePath: "/opt/Sample App/SampleApp")
        plan.iconPath = nil
        let entry = plan.desktopEntry(iconPath: "/home/u/.local/share/icons/hicolor/256x256/apps/com.example.sampleapp.png")
        XCTAssertTrue(entry.contains("Exec=\"/opt/Sample App/SampleApp\" %U\n"), entry)
        XCTAssertTrue(entry.contains("MimeType=text/markdown;application/x-com.example.sampleapp-sample-document;x-scheme-handler/sample;\n"), entry)
        XCTAssertTrue(entry.contains("StartupWMClass=com.example.sampleapp\n"))
        XCTAssertTrue(entry.contains("Name=Beispiel-App\n"))
        XCTAssertTrue(entry.contains("Categories=Office;Utility;\n"))
        XCTAssertEqual(plan.ownedMIMETypes, ["text/markdown", "x-scheme-handler/sample"])
        let xml = try XCTUnwrap(plan.mimePackage)
        XCTAssertTrue(xml.contains("<mime-type type=\"application/x-com.example.sampleapp-sample-document\">"), xml)
        XCTAssertTrue(xml.contains("<glob pattern=\"*.smpl\"/>"))
        XCTAssertTrue(xml.contains("<sub-class-of type=\"text/plain\"/>"), "the imported Markdown UTI conforms to public.plain-text")
        XCTAssertEqual(_AppRegistration.execQuote("/a/$b \"c\""), #""/a/\\$b \\"c\\"""#)

        let home = folder.deletingLastPathComponent().appendingPathComponent("share", isDirectory: true)
        let written = try _XDGRegistrar.write(plan, dataHome: home, iconPNG: Data([1, 2, 3]))
        XCTAssertEqual(written.desktopFile.lastPathComponent, "com.example.sampleapp.desktop")
        XCTAssertEqual(written.iconFile.map { FileManager.default.contents(atPath: $0.path) }, Data([1, 2, 3]))
        XCTAssertTrue(_XDGRegistrar.isRegistered(plan, dataHome: home))
        var moved = plan
        moved.executablePath = "/elsewhere/SampleApp"
        XCTAssertFalse(_XDGRegistrar.isRegistered(moved, dataHome: home), "registered for another executable")
        _XDGRegistrar.remove(plan, dataHome: home)
        XCTAssertFalse(FileManager.default.fileExists(atPath: written.desktopFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: written.mimePackage!.path))
    }

    // MARK: Launch items and the single instance

    @MainActor func testLaunchItemsFromArguments() throws {
        let cwd = folder.path
        let items = _AppInstance.launchItems(["-AppleLanguages", "(de)", "Info.plist", "--verbose", "sample://open?x=1", "file://" + folder.appendingPathComponent("Resources/pic.png").path,
                                              "https://example.com", "missing.md", "-NSDocumentRevisionsDebugMode", "YES", "Resources"],
                                             workingDirectory: cwd, schemes: ["sample"])
        XCTAssertEqual(items.files.map { ($0 as NSString).lastPathComponent }, ["Info.plist", "pic.png", "Resources"])
        XCTAssertEqual(items.urls.map(\.absoluteString), ["sample://open?x=1", "https://example.com"])
        XCTAssertEqual(_AppInstance.launchItems(["sample:ping"], workingDirectory: cwd, schemes: ["sample"]).urls.map(\.absoluteString), ["sample:ping"])
        XCTAssertTrue(_AppInstance.launchItems(["mailto:a@b"], workingDirectory: cwd, schemes: ["sample"]).urls.isEmpty, "an undeclared scheme without // is not ours")
    }

    @MainActor func testAboutPanelContent() {
        let content = NSApplication._aboutPanelContent(options: [:], app: app())
        XCTAssertEqual(content.title, "Beispiel-App")
        XCTAssertEqual(content.text, "Version 1.2 (34)\n\n© 2026 Example")
        let overridden = NSApplication._aboutPanelContent(options: [.applicationName: "X", .applicationVersion: "2.0", .version: "2.0"], app: app())
        XCTAssertEqual(overridden.title, "X")
        XCTAssertTrue(overridden.text.hasPrefix("Version 2.0\n"), overridden.text)
    }

    #if !os(Windows)
    func testInstanceChannelHandsOverAndRecoversFromAStaleSocket() throws {
        let dir = "/tmp"   // sun_path holds ~100 bytes; the test's temporary folder can be longer
        let id = "com.example.channel-\(UUID().uuidString.prefix(8))"
        let first = POSIXInstanceChannel(identifier: id, directory: dir)
        let received = expectation(description: "message")
        final class Box: @unchecked Sendable { let lock = NSLock(); var got: [Data] = [] }
        let box = Box()
        XCTAssertTrue(first.listen { data in box.lock.lock(); box.got.append(data); box.lock.unlock(); received.fulfill() })
        let second = POSIXInstanceChannel(identifier: id, directory: dir)
        XCTAssertFalse(second.listen { _ in }, "only one listener")
        XCTAssertTrue(second.send(Data("hello".utf8)))
        wait(for: [received], timeout: 5)
        box.lock.lock(); XCTAssertEqual(box.got, [Data("hello".utf8)]); box.lock.unlock()
        first.close()
        XCTAssertFalse(second.send(Data("nobody".utf8)))
        // A socket file left by a process that died: the next listener takes over.
        let stale = POSIXInstanceChannel(identifier: id + "-stale", directory: dir)
        FileManager.default.createFile(atPath: stale.path, contents: Data())
        let next = POSIXInstanceChannel(identifier: id + "-stale", directory: dir)
        XCTAssertTrue(next.listen { _ in })
        next.close()
    }
    #endif

    @MainActor func testHandOffMessageRoundTrips() throws {
        let m = _AppInstance.Message(arguments: ["a.md", "-x"], workingDirectory: "/tmp")
        XCTAssertEqual(try JSONDecoder().decode(_AppInstance.Message.self, from: JSONEncoder().encode(m)), m)
    }
}

extension _AppBundle {
    func infoPlistURL() -> URL? { layout.infoPlistURL }
}
