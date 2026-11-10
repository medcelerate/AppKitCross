// Swap-chain presentation of the Vulkan backend (ADR-0012): on the X11 and Wayland
// backends MTKView renders into a VkSwapchainKHR on the native surface the window places
// under it (a child X window, a Wayland subsurface), the way the Direct3D 12 device
// presents through a DirectComposition swap chain on Windows. A cleared frame is
// presented, the window's own pixels are read back from the X server and checked at the
// view's centre (Wayland has no readback; there the path and the counts are checked), and
// a resize re-creates the chain at the new size, with a frame drawn at once. A format
// the surface cannot present falls back to the readback path and names the reason.
// Skipped on the host backend (no native surfaces) and without a presentable device;
// tools/linux/run.sh runs these under Xvfb, run-wayland.sh under a headless sway.

#if os(Linux)
import XCTest
import Glibc
@testable import AppKit
@testable import Metal
import MetalKit

final class MetalVulkanPresentationTests: XCTestCase, @unchecked Sendable {
    /// The clear colour of every frame, and what it reads back as in BGRA.
    static let clearColor = MTLClearColorMake(0.2, 0.6, 0.9, 1)
    static let clearBGRA: [UInt8] = [230, 153, 51, 255]

    final class Renderer: MTKViewDelegate {
        var frames = 0
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        func draw(in view: MTKView) {
            frames += 1
            view.clearColor = MetalVulkanPresentationTests.clearColor
            guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable, let cb = view.device?.makeCommandQueue()?.makeCommandBuffer() else { return }
            cb.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
            cb.present(drawable)
            cb.commit()
        }
    }

    /// Skips unless a window system backend is running (DISPLAY or WAYLAND_DISPLAY set,
    /// APPKITWIN_HOST_BACKEND unset) and the Vulkan device can present.
    @MainActor
    private func presentableDevice() throws -> MTLVulkanDevice {
        guard Platform.backend is LinuxBackend || Platform.backend is WaylandBackend else {
            throw XCTSkip("needs the X11 or Wayland backend (DISPLAY or WAYLAND_DISPLAY set, APPKITWIN_HOST_BACKEND unset)")
        }
        guard let device = try MetalVulkanDeviceTests.vulkanDevice() as? MTLVulkanDevice else { throw XCTSkip("no Vulkan device") }
        guard !device.isHeadless else { throw XCTSkip("the Vulkan device \(device.name) has no presentation support") }
        return device
    }

    /// Runs the backend's event loop without blocking until `condition` or `timeout`.
    @MainActor
    private func pump(until condition: () -> Bool = { false }, timeout: TimeInterval) {
        let deadline = Date(timeIntervalSinceNow: timeout)
        repeat {
            if let b = Platform.backend as? LinuxBackend { b.pump(blocking: false) } else if let b = Platform.backend as? WaylandBackend { b.pump(blocking: false) }
            usleep(5000)
        } while !condition() && Date() < deadline
    }

    /// A window with an MTKView at `viewFrame` (content coordinates), shown and painted.
    @MainActor
    private func makeWindow(device: MTLVulkanDevice, viewFrame: NSRect) -> (NSWindow, MTKView, Renderer) {
        let w = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 200, height: 150), styleMask: [.titled], backing: .buffered, defer: false)
        w.title = "Metal presentation"
        let view = MTKView(frame: viewFrame, device: device)
        let renderer = Renderer()
        view.delegate = renderer
        view.enableSetNeedsDisplay = true
        w.contentView!.addSubview(view)
        w.makeKeyAndOrderFront(nil)
        // Wayland maps the window after the compositor's configure; the parent surface must
        // have committed a buffer before a subsurface's frames can be shown.
        pump(timeout: 0.5)
        w.display()
        return (w, view, renderer)
    }

    /// BGRA of the window's pixel `x`, `y` (from its top-left), from the window system.
    @MainActor
    private func windowPixel(_ w: NSWindow, _ x: Int, _ y: Int) -> [UInt8]? {
        guard let image = w._captureContent() else { return nil }
        let bytes = _pixels(image)
        let stride = image.bytesPerRow
        guard x >= 0, y >= 0, x < image.width, y < image.height else { return nil }
        let i = y * stride + x * 4
        return Array(bytes[i..<i + 4])
    }

    private func assertClose(_ actual: [UInt8]?, _ expected: [UInt8], _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let actual else { return XCTFail("\(message): no pixel", file: file, line: line) }
        let close = actual.count == expected.count && zip(actual, expected).allSatisfy { abs(Int($0) - Int($1)) <= 2 }
        XCTAssertTrue(close, "\(message): \(actual) is not within 2 of \(expected)", file: file, line: line)
    }

    func testPresentsThroughTheSwapChainIntoTheWindow() throws {
        try MainActor.assumeIsolated {
            let device = try presentableDevice()
            let (w, view, renderer) = makeWindow(device: device, viewFrame: NSRect(x: 20, y: 30, width: 120, height: 80))
            defer { withExtendedLifetime(renderer) { w.close() } }   // the view's delegate is weak
            // The window's own paints draw frames too (`enableSetNeedsDisplay`), so counts are relative.
            let presented = view._swapChainPresentCount, frames = renderer.frames
            view.draw()
            XCTAssertEqual(renderer.frames, frames + 1)
            XCTAssertTrue(view._presentsThroughSwapChain, "no swap chain on \(type(of: Platform.backend)): \(view._presentationError)")
            XCTAssertEqual(view._swapChainPresentCount, presented + 1)
            XCTAssertEqual(view._presentationError, "")
            let scale = w.backingScaleFactor
            XCTAssertEqual(view.drawableSize, CGSize(width: 120 * scale, height: 80 * scale))
            for _ in 0..<3 { view.draw() }
            XCTAssertEqual(view._swapChainPresentCount, presented + 4, "every frame presents: \(view._presentationError)")
            // The X server has the frame once it processed the present; the window's own
            // background is around the view.
            pump(timeout: 0.3)
            guard w._captureContent() != nil else {
                print("MetalVulkanPresentationTests: \(type(of: Platform.backend)) cannot read the window back; the swap-chain path was checked, the pixels were not")
                return
            }
            let centre = (x: Int((20 + 60) * scale), y: Int((150 - (30 + 40)) * scale))
            assertClose(windowPixel(w, centre.x, centre.y), Self.clearBGRA, "the view's centre shows the presented clear")
            assertClose(windowPixel(w, Int(21 * scale), Int((150 - 109) * scale)), Self.clearBGRA, "the view's top-left corner")
            assertClose(windowPixel(w, Int(139 * scale), Int((150 - 31) * scale)), Self.clearBGRA, "the view's bottom-right corner")
            let outside = windowPixel(w, Int(5 * scale), Int(5 * scale))
            XCTAssertNotNil(outside)
            if let outside {
                XCTAssertTrue(zip(outside, Self.clearBGRA).contains { abs(Int($0) - Int($1)) > 8 }, "outside the view the window draws itself: \(outside)")
            }
        }
    }

    func testResizeRecreatesTheChainAndDrawsAtOnce() throws {
        try MainActor.assumeIsolated {
            let device = try presentableDevice()
            let (w, view, renderer) = makeWindow(device: device, viewFrame: NSRect(x: 20, y: 30, width: 120, height: 80))
            defer { withExtendedLifetime(renderer) { w.close() } }   // the view's delegate is weak
            view.draw()
            XCTAssertTrue(view._presentsThroughSwapChain, view._presentationError)
            let scale = w.backingScaleFactor
            let presented = view._swapChainPresentCount, frames = renderer.frames
            // A resize changes the drawable size and renders a frame at the new size at once,
            // so the chain never shows a stretched frame.
            view.setFrameSize(NSSize(width: 160, height: 100))
            XCTAssertEqual(view.drawableSize, CGSize(width: 160 * scale, height: 100 * scale))
            XCTAssertEqual(renderer.frames, frames + 1, "the resize drew a frame")
            XCTAssertEqual(view._swapChainPresentCount, presented + 1, view._presentationError)
            XCTAssertTrue(view._presentsThroughSwapChain, view._presentationError)
            view.draw()
            XCTAssertEqual(view._swapChainPresentCount, presented + 2)
            pump(timeout: 0.3)
            if w._captureContent() != nil {
                // The newly covered strip (x 140...180, y 110...130 in content points) is presented.
                assertClose(windowPixel(w, Int(170 * scale), Int((150 - 120) * scale)), Self.clearBGRA, "the area the resize added")
                assertClose(windowPixel(w, Int(100 * scale), Int((150 - 80) * scale)), Self.clearBGRA, "the view's centre after the resize")
            }
            // A smaller size too, then the same size is a no-op for the chain.
            let before = view._swapChainPresentCount
            view.setFrameSize(NSSize(width: 60, height: 40))
            XCTAssertEqual(view.drawableSize, CGSize(width: 60 * scale, height: 40 * scale))
            XCTAssertEqual(view._swapChainPresentCount, before + 1, view._presentationError)
            view.setFrameSize(NSSize(width: 60, height: 40))
            XCTAssertEqual(view._swapChainPresentCount, before + 1)
        }
    }

    func testUnsupportedFormatFallsBackToReadbackAndRecovers() throws {
        try MainActor.assumeIsolated {
            let device = try presentableDevice()
            let (w, view, renderer) = makeWindow(device: device, viewFrame: NSRect(x: 20, y: 30, width: 120, height: 80))
            defer { withExtendedLifetime(renderer) { w.close() } }   // the view's delegate is weak
            view.draw()
            XCTAssertTrue(view._presentsThroughSwapChain, view._presentationError)
            // rgba16Float is a CAMetalLayer format; a surface that cannot show it (lavapipe
            // on X11 and Wayland) sends the view to the readback path, with the reason.
            view.colorPixelFormat = .rgba16Float
            view.draw()
            if view._presentsThroughSwapChain {
                XCTAssertEqual(view._presentationError, "")
                print("MetalVulkanPresentationTests: \(device.name) presents rgba16Float")
            } else {
                XCTAssertFalse(view._presentationError.isEmpty, "the fallback names its reason")
                XCTAssertNotNil(view.presentedTexture, "the readback path presented the frame")
                XCTAssertEqual(view.presentedTexture?.pixelFormat, .rgba16Float)
            }
            // A format the surface takes brings the chain back.
            view.colorPixelFormat = .bgra8Unorm
            view.draw()
            XCTAssertTrue(view._presentsThroughSwapChain, view._presentationError)
            XCTAssertEqual(view._presentationError, "")
            // Leaving the window drops the chain and its surface; coming back makes new ones.
            view.removeFromSuperview()
            XCTAssertFalse(view._presentsThroughSwapChain)
            w.contentView!.addSubview(view)
            let frames = renderer.frames
            view.draw()
            XCTAssertEqual(renderer.frames, frames + 1)
            XCTAssertTrue(view._presentsThroughSwapChain, "after re-adding: \(view._presentationError)")
        }
    }

    /// The formats a chain can be made in are the layer's, on any device.
    func testPresentableFormats() {
        XCTAssertTrue(MTLVulkanSwapChain.isSupported(.bgra8Unorm))
        XCTAssertTrue(MTLVulkanSwapChain.isSupported(.bgra8Unorm_srgb))
        XCTAssertTrue(MTLVulkanSwapChain.isSupported(.rgba16Float))
        XCTAssertFalse(MTLVulkanSwapChain.isSupported(.rgba8Unorm))
        XCTAssertFalse(MTLVulkanSwapChain.isSupported(.depth32Float))
    }
}
#endif
