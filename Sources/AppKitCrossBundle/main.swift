// appkitcross-bundle: the worker behind `swift package bundle` (Plugins/AppBundle). The
// plugin builds the product and hands this tool the executable; it can also be run on its
// own against an executable that is already built:
//
//   AppKitCrossBundle --executable .build/release/MyApp --name MyApp --package-dir . \
//       --output .build/bundle [--target MyApp]... [--app-root dir]... [--version 1.2] \
//       [--info-plist path] [--resources dir] [--icon path]... [--include path]... [--zip] [--appimage]

import AppBundler
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

var args = Array(CommandLine.arguments.dropFirst())
func value(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag) else { return nil }
    guard i + 1 < args.count else { fail("\(flag) needs a value") }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}
func values(_ flag: String) -> [String] {
    var result: [String] = []
    while let v = value(flag) { result.append(v) }
    return result
}
func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}

guard let executable = value("--executable") else { fail("--executable <path> is required") }
let exeURL = URL(fileURLWithPath: executable)
var name = value("--name") ?? exeURL.deletingPathExtension().lastPathComponent
let packageDir = URL(fileURLWithPath: value("--package-dir") ?? FileManager.default.currentDirectoryPath, isDirectory: true)
let output = URL(fileURLWithPath: value("--output") ?? packageDir.appendingPathComponent(".build/bundle").path, isDirectory: true)
let targets = values("--target")
let appRoots = values("--app-root").map { URL(fileURLWithPath: $0, isDirectory: true) }
let version = value("--version")
let infoPlist = value("--info-plist").map { URL(fileURLWithPath: $0) }
let resources = value("--resources").map { URL(fileURLWithPath: $0, isDirectory: true) }
let icons = values("--icon").map { URL(fileURLWithPath: $0) }
let includes = values("--include").map { URL(fileURLWithPath: $0) }
let zip = flag("--zip")
let appImage = flag("--appimage")
if !args.isEmpty { fail("unknown arguments: \(args.joined(separator: " "))") }

let options = BundleOptions(executable: exeURL, name: name, packageDirectory: packageDir,
                            appRootCandidates: appRoots.isEmpty ? [packageDir] : appRoots,
                            targets: targets.isEmpty ? [name] : targets, outputDirectory: output, version: version,
                            infoPlist: infoPlist, resources: resources, icons: icons, include: includes, zip: zip, appImage: appImage)
let bundler = Bundler(options: options)
do {
    let report = try bundler.run()
    print(bundler.summary())
    if !report.missingLibraries.isEmpty { exit(2) }
} catch {
    fail("\(error)")
}
