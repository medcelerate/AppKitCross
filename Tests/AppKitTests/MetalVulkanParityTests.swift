// Stage 4 of the Vulkan backend (ADR-0012): the reference device is the oracle. The same
// scene runs on both devices and every readback is compared within a tolerance. The
// reference device does not rasterize or run compute, so the shared scene is clears in
// several formats, uploads, texture and buffer copies, fills, and a presented MTKView
// frame; rasterization is covered by MetalVulkanRenderTests against known pixels.

import XCTest
@testable import AppKit
import Metal
import MetalKit

final class MetalVulkanParityTests: XCTestCase, @unchecked Sendable {
    /// Everything the scene reads back, keyed by a label, so mismatches name their step.
    typealias Readbacks = [(label: String, bytes: [UInt8], tolerance: Int)]

    /// Clears, uploads, blits and fills on `device`; order and sizes are identical on both.
    static func runScene(on device: any MTLDevice) throws -> Readbacks {
        let queue = try XCTUnwrap(device.makeCommandQueue())
        var out: Readbacks = []

        func texture(_ format: MTLPixelFormat, _ w: Int, _ h: Int, usage: MTLTextureUsage = [.renderTarget, .shaderRead]) throws -> any MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w, height: h, mipmapped: false)
            d.usage = usage
            return try XCTUnwrap(device.makeTexture(descriptor: d), "\(format) \(w)x\(h) on \(device.name)")
        }
        func read(_ t: any MTLTexture, _ label: String, tolerance: Int) {
            let bpr = t.width * t.pixelFormat.bytesPerPixel
            var px = [UInt8](repeating: 0, count: bpr * t.height)
            t.getBytes(&px, bytesPerRow: bpr, from: MTLRegionMake2D(0, 0, t.width, t.height), mipmapLevel: 0)
            out.append((label, px, tolerance))
        }
        func clear(_ t: any MTLTexture, _ c: MTLClearColor, depth: Double? = nil) throws {
            let pass = MTLRenderPassDescriptor()
            if let depth {
                pass.depthAttachment.texture = t
                pass.depthAttachment.loadAction = .clear
                pass.depthAttachment.storeAction = .store
                pass.depthAttachment.clearDepth = depth
            } else {
                pass.colorAttachments[0].texture = t
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].storeAction = .store
                pass.colorAttachments[0].clearColor = c
            }
            let cb = try XCTUnwrap(queue.makeCommandBuffer())
            try XCTUnwrap(cb.makeRenderCommandEncoder(descriptor: pass)).endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
            XCTAssertEqual(cb.status, .completed, "clear on \(device.name)")
        }

        // 1. Clears in unorm, float and depth formats (unorm rounding may differ by one).
        let bgra = try texture(.bgra8Unorm, 16, 8)
        try clear(bgra, MTLClearColorMake(0.25, 0.5, 1, 1))
        read(bgra, "bgra8 clear", tolerance: 1)
        let rgba = try texture(.rgba8Unorm, 12, 6)
        try clear(rgba, MTLClearColorMake(1, 0.5, 0.25, 0.5))
        read(rgba, "rgba8 clear", tolerance: 1)
        let r8 = try texture(.r8Unorm, 8, 8)
        try clear(r8, MTLClearColorMake(0.6, 0, 0, 1))
        read(r8, "r8 clear", tolerance: 1)
        let rg8 = try texture(.rg8Unorm, 8, 4)
        try clear(rg8, MTLClearColorMake(0.1, 0.9, 0, 1))
        read(rg8, "rg8 clear", tolerance: 1)
        let rgbaF = try texture(.rgba32Float, 6, 6)
        try clear(rgbaF, MTLClearColorMake(0.125, -2, 1000, 0.5))
        read(rgbaF, "rgba32Float clear", tolerance: 0)
        let rF = try texture(.r32Float, 5, 3)
        try clear(rF, MTLClearColorMake(3.5, 0, 0, 0))
        read(rF, "r32Float clear", tolerance: 0)
        let depth = try texture(.depth32Float, 8, 8, usage: .renderTarget)
        try clear(depth, MTLClearColor(), depth: 0.75)
        read(depth, "depth32Float clear", tolerance: 0)

        // 2. An upload, then texture → texture, buffer → texture and texture → buffer copies
        //    and a fill, all in one command buffer.
        let gradient = try texture(.bgra8Unorm, 8, 8, usage: .shaderRead)
        var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
        for y in 0..<8 { for x in 0..<8 { let i = (y * 8 + x) * 4; pixels[i] = UInt8(x * 32); pixels[i + 1] = UInt8(y * 32); pixels[i + 2] = UInt8(255 - x * 16 - y * 16); pixels[i + 3] = 255 } }
        gradient.replace(region: MTLRegionMake2D(0, 0, 8, 8), mipmapLevel: 0, withBytes: pixels, bytesPerRow: 32)
        read(gradient, "gradient upload", tolerance: 0)
        let patch: [UInt8] = (0..<(4 * 2 * 4)).map { UInt8(($0 * 37) & 0xFF) }
        let upload = try XCTUnwrap(device.makeBuffer(bytes: patch, length: patch.count, options: []))
        let readback = try XCTUnwrap(device.makeBuffer(length: 4 * 4 * 4 + 64, options: []))
        let filled = try XCTUnwrap(device.makeBuffer(length: 64, options: []))
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        let blit = try XCTUnwrap(cb.makeBlitCommandEncoder())
        blit.copy(from: gradient, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 2, y: 2, z: 0), sourceSize: MTLSize(width: 4, height: 4, depth: 1),
                  to: bgra, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 10, y: 3, z: 0))
        blit.copy(from: upload, sourceOffset: 0, sourceBytesPerRow: 16, sourceBytesPerImage: 32, sourceSize: MTLSize(width: 4, height: 2, depth: 1),
                  to: bgra, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 1, y: 5, z: 0))
        blit.copy(from: gradient, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 4, y: 0, z: 0), sourceSize: MTLSize(width: 4, height: 4, depth: 1),
                  to: readback, destinationOffset: 64, destinationBytesPerRow: 16, destinationBytesPerImage: 64)
        blit.fill(buffer: filled, range: 3..<41, value: 0x5A)
        blit.copy(from: upload, sourceOffset: 8, to: filled, destinationOffset: 48, size: 8)
        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        XCTAssertEqual(cb.status, .completed, "blits on \(device.name)")
        read(bgra, "bgra8 after copies", tolerance: 1)
        out.append(("texture → buffer", Array(UnsafeBufferPointer(start: readback.contents().assumingMemoryBound(to: UInt8.self), count: readback.length)), 0))
        out.append(("fill and buffer copy", Array(UnsafeBufferPointer(start: filled.contents().assumingMemoryBound(to: UInt8.self), count: filled.length)), 0))
        return out
    }

    static func compare(_ reference: Readbacks, _ vulkan: Readbacks) {
        XCTAssertEqual(reference.count, vulkan.count)
        for (r, v) in zip(reference, vulkan) {
            XCTAssertEqual(r.label, v.label)
            XCTAssertEqual(r.bytes.count, v.bytes.count, "\(r.label): byte counts")
            var worst = 0, firstBad = -1, bad = 0
            for i in 0..<min(r.bytes.count, v.bytes.count) {
                let d = abs(Int(r.bytes[i]) - Int(v.bytes[i]))
                if d > r.tolerance { bad += 1; if firstBad < 0 { firstBad = i } }
                worst = max(worst, d)
            }
            XCTAssertEqual(bad, 0, "\(r.label): \(bad) bytes differ by more than \(r.tolerance) (worst \(worst), first at byte \(firstBad): reference \(firstBad >= 0 ? Int(r.bytes[firstBad]) : -1) vs Vulkan \(firstBad >= 0 ? Int(v.bytes[firstBad]) : -1))")
        }
    }

    func testSceneMatchesReferenceDevice() throws {
        let vulkan = try MetalVulkanDeviceTests.vulkanDevice()
        let reference = try Self.runScene(on: MTLReferenceDevice())
        let onVulkan = try Self.runScene(on: vulkan)
        Self.compare(reference, onVulkan)
        XCTAssertGreaterThanOrEqual(reference.count, 10)
    }

    func testReferenceSceneIsSelfConsistent() throws {
        // The oracle itself, on every platform: the scene's expectations hold by construction.
        let r = try Self.runScene(on: MTLReferenceDevice())
        let bgra = try XCTUnwrap(r.first { $0.label == "bgra8 after copies" }).bytes
        XCTAssertEqual(Array(bgra[0..<4]), [255, 128, 64, 255], "clear colour outside the copies")
        let copied = (3 * 16 + 10) * 4   // (10, 3) ← gradient (2, 2)
        XCTAssertEqual(Array(bgra[copied..<copied + 4]), [64, 64, 191, 255])
        let fill = try XCTUnwrap(r.first { $0.label == "fill and buffer copy" }).bytes
        XCTAssertEqual(fill[2], 0); XCTAssertEqual(fill[3], 0x5A); XCTAssertEqual(fill[40], 0x5A); XCTAssertEqual(fill[41], 0)
    }

    func testMTKViewFrameMatchesReferenceDevice() throws {
        let vulkan = try MetalVulkanDeviceTests.vulkanDevice()
        var images: [Data] = []
        let devices: [any MTLDevice] = [MTLReferenceDevice(), vulkan]
        try MainActor.assumeIsolated {
            for device in devices {
                let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 64, height: 48), styleMask: [.titled], backing: .buffered, defer: false)
                let view = MTKView(frame: NSRect(x: 0, y: 0, width: 64, height: 48), device: device)
                final class Renderer: MTKViewDelegate {
                    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
                    func draw(in view: MTKView) {
                        view.clearColor = MTLClearColorMake(0.2, 0.6, 0.9, 1)
                        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable, let cb = view.device?.makeCommandQueue()?.makeCommandBuffer() else { return }
                        cb.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
                        cb.present(drawable)
                        cb.commit()
                    }
                }
                let renderer = Renderer()
                view.delegate = renderer
                view.enableSetNeedsDisplay = true
                w.contentView!.addSubview(view)
                w.makeKeyAndOrderFront(nil)
                view.draw()
                w.display()
                let platform = Mirror(reflecting: w).descendant("_platform") as! HostWindow
                images.append(_pixels(try XCTUnwrap(platform.lastImage)))
                w.close()
            }
        }
        XCTAssertEqual(images[0].count, images[1].count)
        var worst = 0
        for (a, b) in zip(images[0], images[1]) { worst = max(worst, abs(Int(a) - Int(b))) }
        XCTAssertLessThanOrEqual(worst, 1, "the presented frame differs from the reference device's by at most one level per channel")
    }
}
