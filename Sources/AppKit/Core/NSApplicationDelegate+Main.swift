import Foundation

extension NSApplicationDelegate where Self: NSObject {
    /// Entry point for `@main` application delegates: instantiates the delegate, installs it
    /// on the shared application and runs the event loop.
    @MainActor public static func main() {
        let delegate = Self.init()
        let app = NSApplication.shared
        app.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}
