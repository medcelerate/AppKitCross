// Milestone 7: the Metal module (reference device) and MTKView.

import XCTest
@testable import AppKit
import Metal
import MetalKit

final class MetalReferenceDeviceTests: XCTestCase {
    func testBuffersTexturesBlitsAndCommandBuffers() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        XCTAssertFalse(device.supportsRasterization)
        let queue = try XCTUnwrap(device.makeCommandQueue())
        var floats: [Float] = [1, 2, 3, 4]
        let a = try XCTUnwrap(device.makeBuffer(bytes: &floats, length: 16, options: .storageModeShared))
        let b = try XCTUnwrap(device.makeBuffer(length: 16, options: []))
        let tex = try XCTUnwrap(device.makeTexture(descriptor: MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 4, height: 2, mipmapped: false)))
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        let blit = try XCTUnwrap(cb.makeBlitCommandEncoder())
        blit.copy(from: a, sourceOffset: 0, to: b, destinationOffset: 0, size: 16)
        blit.fill(buffer: a, range: 0..<4, value: 0xFF)
        blit.endEncoding()
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = tex
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(1, 0, 0, 1)
        let enc = try XCTUnwrap(cb.makeRenderCommandEncoder(descriptor: pass))
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        var completed = false
        cb.addCompletedHandler { _ in completed = true }
        cb.commit()
        cb.waitUntilCompleted()
        XCTAssertTrue(completed)
        XCTAssertEqual(cb.status, .completed)
        XCTAssertEqual(b.contents().load(fromByteOffset: 4, as: Float.self), 2)
        XCTAssertEqual(a.contents().load(as: UInt32.self), 0xFFFF_FFFF)
        var px = [UInt8](repeating: 0, count: 4 * 4 * 2)
        tex.getBytes(&px, bytesPerRow: 16, from: MTLRegionMake2D(0, 0, 4, 2), mipmapLevel: 0)
        XCTAssertEqual(Array(px[0..<4]), [0, 0, 255, 255])   // BGRA red
        XCTAssertEqual((cb as? MTLReferenceCommandBuffer)?.drawCallCount, 1)
    }

    func testLibrariesAndPipelines() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let msl = """
        #include <metal_stdlib>
        using namespace metal;
        vertex float4 vertexMain(uint id [[vertex_id]]) { return float4(0); }
        fragment half4 fragmentMain() { return half4(1); }
        """
        let lib = try device.makeLibrary(source: msl, options: nil)
        XCTAssertEqual(Set(lib.functionNames), ["vertexMain", "fragmentMain"])
        let vs = try XCTUnwrap(lib.makeFunction(name: "vertexMain"))
        XCTAssertEqual(vs.functionType, .vertex)
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vs
        desc.fragmentFunction = lib.makeFunction(name: "fragmentMain")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        desc.colorAttachments[0].isBlendingEnabled = true
        let state = try device.makeRenderPipelineState(descriptor: desc)
        XCTAssertTrue(state.device === device)
        desc.colorAttachments[0].pixelFormat = .invalid
        XCTAssertThrowsError(try device.makeRenderPipelineState(descriptor: desc))
        let options = MTLCompileOptions()
        options.shaderLanguage = .hlsl
        let hlsl = "float4 VSMain(uint id : SV_VertexID) : SV_Position { return 0; }\nfloat4 PSMain() : SV_Target { return 1; }"
        let hl = try device.makeLibrary(source: hlsl, options: options)
        XCTAssertEqual(Set(hl.functionNames), ["VSMain", "PSMain"])
        XCTAssertEqual(hl.makeFunction(name: "PSMain")?.functionType, .fragment)
        XCTAssertNil(device.makeDefaultLibrary())
    }
}

@MainActor
final class MTKViewTests: XCTestCase {
    final class Renderer: MTKViewDelegate {
        var frames = 0
        var sizes: [CGSize] = []
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { sizes.append(size) }
        func draw(in view: MTKView) {
            frames += 1
            guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
                  let cb = view.device?.makeCommandQueue()?.makeCommandBuffer() else { return }
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 1, 1)
            cb.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
            cb.present(drawable)
            cb.commit()
        }
    }

    func testMTKViewPresentsClearedDrawable() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        let view = MTKView(frame: NSRect(x: 10, y: 10, width: 50, height: 50), device: nil)
        let renderer = Renderer()
        view.delegate = renderer
        view.enableSetNeedsDisplay = true
        w.contentView!.addSubview(view)
        w.makeKeyAndOrderFront(nil)
        XCTAssertEqual(view.drawableSize, CGSize(width: 100, height: 100))   // 2x backing scale
        let before = renderer.frames   // the first display already drew a frame
        view.draw()
        XCTAssertEqual(renderer.frames, before + 1)
        XCTAssertNotNil(view.presentedTexture)
        w.display()
        let platform = Mirror(reflecting: w).descendant("_platform") as! HostWindow
        let image = platform.lastImage!
        let data = _pixels(image)
        let row = image.height - 1 - 30 * 2
        let i = row * image.bytesPerRow + 30 * 2 * 4
        XCTAssertGreaterThan(data[i], 200)      // blue
        XCTAssertLessThan(data[i + 2], 30)      // red
        w.close()
    }
}
