// `swift package bundle`: builds an executable product and lays it out as a folder that runs
// on a machine without Swift (ADR-0046, docs/DEVELOPMENT.md "Shipping an app").
//
//   swift package --allow-writing-to-package-directory bundle --product MyApp -c release [--zip] [--appimage]
//
// Options: --product <name> (required unless the package has exactly one executable),
// -c/--configuration debug|release (default release), --output <dir> (default
// .build/bundle), --version <v> (default: CFBundleShortVersionString, else 0.0.0),
// --info-plist <path>, --resources <dir>, --icon <path> (repeatable), --include <path>
// (repeatable: a file or directory copied beside the executable, for libraries the app
// loads at run time and anything else a user should find in the folder), --zip (also
// writes <zip>.sha256), --appimage,
// --no-build (bundle what the last build produced), --no-debug-info (Windows release: skip
// the PDB that `-g -debug-info-format=codeview` / `-Xlinker -debug` add for crash reports),
// --console (Windows release: keep the console subsystem; by default the bundled executable
// is linked as a GUI application so no terminal window opens beside it; a redirected stderr
// still reaches its file).

import Foundation
import PackagePlugin

@main
struct AppBundlePlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        var args = arguments
        func take(_ names: String...) -> String? {
            guard let i = args.firstIndex(where: { names.contains($0) }) else { return nil }
            guard i + 1 < args.count else { Diagnostics.error("\(args[i]) needs a value"); return nil }
            let v = args[i + 1]
            args.removeSubrange(i...(i + 1))
            return v
        }
        func takeAll(_ name: String) -> [String] {
            var r: [String] = []
            while let v = take(name) { r.append(v) }
            return r
        }
        func has(_ name: String) -> Bool {
            guard let i = args.firstIndex(of: name) else { return false }
            args.remove(at: i)
            return true
        }

        let executables = context.package.products.compactMap { $0 as? ExecutableProduct }
        let productName = take("--product") ?? (executables.count == 1 ? executables[0].name : nil)
        guard let productName else {
            throw BundlePluginError("--product <name> is required; executable products: \(executables.map(\.name).joined(separator: ", "))")
        }
        let configuration = (take("-c", "--configuration") ?? "release").lowercased()
        guard configuration == "release" || configuration == "debug" else { throw BundlePluginError("-c must be debug or release") }
        let noBuild = has("--no-build")
        let noDebugInfo = has("--no-debug-info")
        let console = has("--console")
        var forwarded: [String] = []
        if let v = take("--output") { forwarded += ["--output", v] } else {
            forwarded += ["--output", context.package.directoryURL.appendingPathComponent(".build/bundle").path]
        }
        if let v = take("--version") { forwarded += ["--version", v] }
        if let v = take("--info-plist") { forwarded += ["--info-plist", v] }
        if let v = take("--resources") { forwarded += ["--resources", v] }
        for v in takeAll("--icon") { forwarded += ["--icon", v] }
        for v in takeAll("--include") { forwarded += ["--include", v] }
        if has("--zip") { forwarded.append("--zip") }
        if has("--appimage") { forwarded.append("--appimage") }
        if !args.isEmpty { throw BundlePluginError("unknown arguments: \(args.joined(separator: " "))") }

        // The product and the targets whose resource bundles it carries.
        let product = context.package.products.first { $0.name == productName }
        var targets: [String] = []
        var appRoots: [URL] = []
        if let product {
            for target in product.targets {
                targets.append(target.name)
                for dependency in target.recursiveTargetDependencies { targets.append(dependency.name) }
            }
            // Info.plist / Resources / icons: the main target's directory and its parents,
            // nearest first, stopping below the package root. The root is shared by every
            // product (and Windows SwiftPM has left resource-bundle plists there), so it is
            // searched as a candidate only for a target that lives there; for any other the
            // bundler falls back to it only for the app's own `Resources/Info.plist`,
            // `Resources/<Name>-Info.plist` or `<Name>-Info.plist` (`--info-plist` names others).
            if let main = ((product as? ExecutableProduct)?.mainTarget ?? product.targets.first) as? SwiftSourceModuleTarget {
                var dir = main.directoryURL.standardizedFileURL
                let root = context.package.directoryURL.standardizedFileURL
                if dir.path == root.path { appRoots.append(dir) }
                while dir.path != root.path && dir.path.hasPrefix(root.path) {
                    appRoots.append(dir)
                    let parent = dir.deletingLastPathComponent()
                    if parent.path == dir.path { break }
                    dir = parent
                }
            }
        }

        let executableURL: URL
        if noBuild {
            executableURL = try findBuiltExecutable(named: productName, configuration: configuration, packageDirectory: context.package.directoryURL)
        } else {
            print("Building \(productName) (\(configuration))…")
            var parameters = PackageManager.BuildParameters(configuration: configuration == "release" ? .release : .debug, logging: .concise, echoLogs: true)
            #if os(Windows)
            // A release build writes no PDB by default; crash reports need one to name
            // functions (the bundler copies it beside the executable). A debug build has one.
            if configuration == "release" && !noDebugInfo {
                parameters.otherSwiftcFlags += ["-g", "-debug-info-format=codeview"]
                parameters.otherLinkerFlags += ["-debug"]
            }
            // swift-build links a console application: a double-click opens a terminal
            // window beside the app (ADR-0055, the first Sibyl tester run). A release
            // bundle is a GUI application; Swift's `main` keeps the C entry point. The
            // developer's own `swift build` is unchanged, and --console keeps it here too.
            if configuration == "release" && !console {
                parameters.otherLinkerFlags += ["/SUBSYSTEM:WINDOWS", "/ENTRY:mainCRTStartup"]
            }
            #else
            _ = noDebugInfo
            _ = console
            #endif
            let result = try packageManager.build(.product(productName), parameters: parameters)
            guard result.succeeded else { throw BundlePluginError("the build failed:\n\(result.logText)") }
            guard let artifact = result.builtArtifacts.first(where: { $0.kind == .executable }) else {
                throw BundlePluginError("the build produced no executable for \(productName)")
            }
            executableURL = artifact.url
        }

        let tool = try context.tool(named: "AppKitCrossBundle")
        var toolArgs = ["--executable", executableURL.path, "--name", productName, "--package-dir", context.package.directoryURL.path]
        for t in Array(NSOrderedSet(array: targets)) as! [String] { toolArgs += ["--target", t] }
        for r in appRoots { toolArgs += ["--app-root", r.path] }
        toolArgs += forwarded

        let process = Process()
        process.executableURL = tool.url
        process.arguments = toolArgs
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 2 {
            Diagnostics.warning("some libraries were not found; the folder will not start on another machine until they are added")
        } else if process.terminationStatus != 0 {
            throw BundlePluginError("bundling failed (status \(process.terminationStatus))")
        }
    }

    /// `.build/<triple>/<configuration>/<name>[.exe]`, or `.build/<configuration>/...`.
    private func findBuiltExecutable(named name: String, configuration: String, packageDirectory: URL) throws -> URL {
        let fm = FileManager.default
        let build = packageDirectory.appendingPathComponent(".build")
        var candidates = [build.appendingPathComponent(configuration)]
        for item in (try? fm.contentsOfDirectory(atPath: build.path)) ?? [] where item.contains("-") {
            candidates.append(build.appendingPathComponent(item).appendingPathComponent(configuration))
        }
        for dir in candidates {
            for file in [name + ".exe", name] {
                let url = dir.appendingPathComponent(file)
                var isDirectory: ObjCBool = false
                if fm.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue { return url }
            }
        }
        throw BundlePluginError("--no-build: no built \(name) under \(build.path)/…/\(configuration)")
    }
}

struct BundlePluginError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
