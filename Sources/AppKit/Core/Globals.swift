import Foundation

/// The shared application object, set when `NSApplication.shared` is first used.
@MainActor public var NSApp: NSApplication! {
    get { NSApplication._shared }
    set { NSApplication._shared = newValue }
}

/// Starts the application: creates the shared application and runs its event loop.
/// Nib loading is not supported; set `NSApp.delegate` before calling this.
@MainActor public func NSApplicationMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32 {
    NSApplication.shared.run()
    return 0
}

extension NSRect {
    /// Area helper used when picking the screen a window mostly lives on.
    internal var area: CGFloat { isNull ? 0 : max(0, width) * max(0, height) }
}
