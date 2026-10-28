import Foundation

#if canImport(ObjectiveC)
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
#else
/// On platforms without the Objective-C runtime `NSObject.init()` is not `required`, so a
/// `@main` delegate must promise an initializer explicitly:
///
///     @main final class AppDelegate: NSObject, NSApplicationDelegate, NSMainInstantiable { ... }
public protocol NSMainInstantiable {
    init()
}

extension NSApplicationDelegate where Self: NSObject & NSMainInstantiable {
    /// Entry point for `@main` application delegates: instantiates the delegate, installs it
    /// on the shared application and runs the event loop.
    @MainActor public static func main() {
        let delegate = Self.init()
        let app = NSApplication.shared
        app.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}
#endif
