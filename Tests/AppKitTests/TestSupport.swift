// Pixel access for the host window's rendered image on every platform.
import Foundation
@testable import AppKit

func _pixels(_ image: CGImage) -> Data {
    #if os(Windows) || os(Linux)
    return image.data
    #else
    return image.dataProvider!.data! as Data
    #endif
}

/// Runs `body` with the standard window buttons pinned to `style` (ADR-0022), whatever the
/// backend draws: the traffic-light and caption layouts are Core logic, checked on every
/// backend (the Win32 backend draws caption buttons, the host backend traffic lights).
@MainActor
func withWindowButtonStyle<T>(_ style: PlatformWindowButtonStyle, _ body: () throws -> T) rethrows -> T {
    let saved = Platform.windowButtonStyleOverride
    Platform.windowButtonStyleOverride = style
    defer { Platform.windowButtonStyleOverride = saved }
    return try body()
}

/// The centre of `view` in its window's coordinates (what `platformWindowHitTest` and
/// mouse events take): a standard button wherever the backend's style put it.
@MainActor
func windowCenter(of view: NSView) -> NSPoint {
    view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
}
