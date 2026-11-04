// The Direct3D 12 backend of the Metal module (ADR-0004) on Windows: every shader the
// translator tests and HelloWindow use compiles through the shim's HLSL compiler (dxc, or
// d3dcompiler at shader model 5.1), render pipelines from HLSL and from translated MSL
// draw, blits respect regions and encoder order, and the DXGI composition swap chain that
// MTKView presents through hands out, flips, keeps and resizes its buffers. The tests skip
// where the backend is absent (macOS, Linux); on Windows CI the device is WARP.

import XCTest
@testable import AppKit
@testable import Metal
import MetalKit

final class MetalD3D12DeviceTests: XCTestCase, @unchecked Sendable {
    /// The Direct3D 12 device, or a skip naming why there is none.
    static func d3d12Device() throws -> any MTLDevice {
        #if os(Windows)
        guard let d = MTLD3D12Device() else { throw XCTSkip("no Direct3D 12 device, not even WARP") }
        return d
        #else
        throw XCTSkip("the Direct3D 12 backend is Windows-only")
        #endif
    }

    struct Vertex { var x: Float, y: Float, r: Float, g: Float, b: Float, a: Float }

    static func pixel(_ texture: any MTLTexture, _ x: Int, _ y: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 4)
        texture.getBytes(&out, bytesPerRow: 4, from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
        return out
    }

    func testDeviceIsTheSystemDefaultOnWindows() throws {
        let device = try Self.d3d12Device()
        XCTAssertTrue(device.supportsRasterization)
        XCTAssertFalse(device.name.isEmpty)
        #if os(Windows)
        if ProcessInfo.processInfo.environment["APPKITWIN_METAL_REFERENCE"] != "1" {
            XCTAssertTrue(MTLCreateSystemDefaultDevice() is MTLD3D12Device, "the registry prefers the Direct3D 12 device")
        }
        #endif
    }

    /// Every sample translates (or is HLSL already) and each entry point compiles for its
    /// stage; a rejection prints the compiler's diagnostics and the HLSL it saw.
    func testEveryShaderCompilesThroughTheHLSLCompiler() throws {
        let device = try Self.d3d12Device()
        #if os(Windows)
        var compiled = 0
        for sample in MSLSamples.all {
            let library: any MTLLibrary
            do { library = try device.makeLibrary(source: sample.source, options: nil) } catch { XCTFail("\(sample.name): \(error)"); continue }
            XCTAssertEqual(Set(library.functionNames), Set(sample.functions.map(\.name)), sample.name)
            for f in sample.functions {
                guard let function = library.makeFunction(name: f.name) as? MTLD3D12Function else { XCTFail("\(sample.name): no function \(f.name)"); continue }
                XCTAssertEqual(function.functionType, f.type, "\(sample.name).\(f.name)")
                let profile = f.type == .vertex ? "vs_6_0" : f.type == .fragment ? "ps_6_0" : "cs_6_0"
                do {
                    _ = try function.compiled(profile: profile)
                    compiled += 1
                } catch {
                    XCTFail("\(sample.name).\(f.name) (\(profile)) rejected:\n\(error)\n--- HLSL ---\n\((library as? MTLD3D12Library)?.hlslSource ?? "")")
                }
            }
        }
        XCTAssertEqual(compiled, MSLSamples.all.reduce(0) { $0 + $1.functions.count })
        #endif
    }

    /// The self-test triangle from HLSL and from MSL: the centre pixel is the vertex colour
    /// (tinted through the constant buffer), the corners the clear colour.
    func testTrianglePipelinesDrawFromHLSLAndMSL() throws {
        let device = try Self.d3d12Device()
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let vd = MTLVertexDescriptor()
        vd.attributes[0].format = .float2
        vd.attributes[0].bufferIndex = 1
        vd.attributes[1].format = .float4
        vd.attributes[1].offset = 8
        vd.attributes[1].bufferIndex = 1
        vd.layouts[1].stride = MemoryLayout<Vertex>.stride
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        let target = try XCTUnwrap(device.makeTexture(descriptor: td))
        let triangle = [Vertex(x: 0, y: 0.9, r: 0, g: 1, b: 0, a: 1), Vertex(x: 0.9, y: -0.9, r: 0, g: 1, b: 0, a: 1), Vertex(x: -0.9, y: -0.9, r: 0, g: 1, b: 0, a: 1)]
        let vertices = try XCTUnwrap(triangle.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: []) })
        for (source, names, tint, centre) in [(MSLSamples.selfTestHLSL, ("triangleVertex", "triangleFragment"), [Float](arrayLiteral: 1, 1, 1, 1), [[UInt8]](arrayLiteral: [0, 255, 0, 255])),
                                              (MSLSamples.selfTestMSL, ("mslVertex", "mslFragment"), [1, 0.5, 1, 1], [[0, 128, 0, 255], [0, 127, 0, 255]])] {
            let library = try device.makeLibrary(source: source, options: nil)
            let pd = MTLRenderPipelineDescriptor()
            pd.vertexFunction = library.makeFunction(name: names.0)
            pd.fragmentFunction = library.makeFunction(name: names.1)
            pd.colorAttachments[0].pixelFormat = .bgra8Unorm
            pd.vertexDescriptor = vd
            let pipeline = try device.makeRenderPipelineState(descriptor: pd)
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColorMake(1, 0, 0, 1)
            let cb = try XCTUnwrap(queue.makeCommandBuffer())
            let encoder = try XCTUnwrap(cb.makeRenderCommandEncoder(descriptor: pass))
            encoder.setRenderPipelineState(pipeline)
            var constants = tint
            encoder.setVertexBytes(&constants, length: 16, index: 0)
            encoder.setVertexBuffer(vertices, offset: 0, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
            XCTAssertEqual(cb.status, .completed, names.0)
            XCTAssertTrue(centre.contains(Self.pixel(target, 32, 32)), "\(names.0): centre \(Self.pixel(target, 32, 32)) not in \(centre)")
            XCTAssertEqual(Self.pixel(target, 1, 1), [0, 0, 255, 255], "\(names.0): corner keeps the clear colour")
            XCTAssertEqual(Self.pixel(target, 62, 1), [0, 0, 255, 255], "\(names.0): corner keeps the clear colour")
        }
    }

    /// A blit encoder's commands take effect in order: a readback recorded after a GPU copy
    /// sees the copy, and region copies land where Metal says (the parity scene relies on both).
    func testBlitsRespectRegionsAndOrder() throws {
        let device = try Self.d3d12Device()
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 8, height: 8, mipmapped: false)
        desc.usage = [.shaderRead, .renderTarget]
        let source = try XCTUnwrap(device.makeTexture(descriptor: desc))
        let destination = try XCTUnwrap(device.makeTexture(descriptor: desc))
        var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
        for i in 0..<64 { pixels[i * 4] = UInt8(i); pixels[i * 4 + 1] = UInt8(255 - i); pixels[i * 4 + 2] = 7; pixels[i * 4 + 3] = 255 }
        source.replace(region: MTLRegionMake2D(0, 0, 8, 8), mipmapLevel: 0, withBytes: pixels, bytesPerRow: 32)
        let zero = [UInt8](repeating: 0, count: pixels.count)
        destination.replace(region: MTLRegionMake2D(0, 0, 8, 8), mipmapLevel: 0, withBytes: zero, bytesPerRow: 32)
        let readback = try XCTUnwrap(device.makeBuffer(length: 2 * 2 * 4, options: []))
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        let blit = try XCTUnwrap(cb.makeBlitCommandEncoder())
        // (2,3)-(3,4) of the source → (5,1) of the destination, then that region → a buffer.
        blit.copy(from: source, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 2, y: 3, z: 0), sourceSize: MTLSize(width: 2, height: 2, depth: 1),
                  to: destination, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 5, y: 1, z: 0))
        blit.copy(from: destination, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 5, y: 1, z: 0), sourceSize: MTLSize(width: 2, height: 2, depth: 1),
                  to: readback, destinationOffset: 0, destinationBytesPerRow: 8, destinationBytesPerImage: 16)
        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        XCTAssertEqual(cb.status, .completed)
        XCTAssertEqual(Self.pixel(destination, 5, 1), [UInt8(3 * 8 + 2), UInt8(255 - 26), 7, 255])
        XCTAssertEqual(Self.pixel(destination, 6, 2), [UInt8(4 * 8 + 3), UInt8(255 - 35), 7, 255])
        XCTAssertEqual(Self.pixel(destination, 4, 1), [0, 0, 0, 0], "outside the region the destination is untouched")
        XCTAssertEqual(Self.pixel(destination, 5, 3), [0, 0, 0, 0])
        let bytes = Array(UnsafeBufferPointer(start: readback.contents().assumingMemoryBound(to: UInt8.self), count: 16))
        XCTAssertEqual(Array(bytes[0..<4]), [UInt8(26), UInt8(255 - 26), 7, 255], "the readback follows the GPU copy")
        XCTAssertEqual(Array(bytes[12..<16]), [UInt8(35), UInt8(255 - 35), 7, 255])
    }

    /// The composition swap chain MTKView presents through on a hosted window: buffers come
    /// out as drawables, a presented buffer keeps its pixels (FLIP_SEQUENTIAL), the next
    /// drawable is another buffer, and a resize re-sizes them.
    func testCompositionSwapChainPresentsAndResizes() throws {
        #if os(Windows)
        guard let device = try Self.d3d12Device() as? MTLD3D12Device else { return XCTFail("not the Direct3D 12 device") }
        guard let swapChain = MTLD3D12SwapChain(device: device, width: 32, height: 16, pixelFormat: .bgra8Unorm) else {
            return XCTFail("composition swap chain creation failed on \(device.name)")
        }
        XCTAssertNotNil(swapChain.nativeHandle)
        XCTAssertFalse(device.isDeviceRemoved, "creating the swap chain removed the device")
        let queue = try XCTUnwrap(device.makeCommandQueue())
        // An empty command buffer, then a clear of an ordinary texture: the device survives
        // work that does not touch a back buffer.
        let empty = try XCTUnwrap(queue.makeCommandBuffer())
        empty.commit()
        empty.waitUntilCompleted()
        XCTAssertFalse(device.isDeviceRemoved, "an empty command buffer removed the device")
        let plain = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 32, height: 16, mipmapped: false)
        plain.usage = [.renderTarget, .shaderRead]
        let plainTexture = try XCTUnwrap(device.makeTexture(descriptor: plain))
        let plainPass = MTLRenderPassDescriptor()
        plainPass.colorAttachments[0].texture = plainTexture
        plainPass.colorAttachments[0].loadAction = .clear
        plainPass.colorAttachments[0].clearColor = MTLClearColorMake(1, 0, 0, 1)
        let plainClear = try XCTUnwrap(queue.makeCommandBuffer())
        try XCTUnwrap(plainClear.makeRenderCommandEncoder(descriptor: plainPass)).endEncoding()
        plainClear.commit()
        plainClear.waitUntilCompleted()
        XCTAssertEqual(Self.pixel(plainTexture, 1, 1), [0, 0, 255, 255], "a plain texture clears while the swap chain exists")
        XCTAssertFalse(device.isDeviceRemoved, "clearing a plain texture removed the device")
        func clearAndPresent(_ colour: MTLClearColor, expecting pixel: [UInt8]) throws -> (any MTLTexture, OpaquePointer) {
            let drawable = try XCTUnwrap(swapChain.nextDrawable(), "nextDrawable: \(swapChain.lastError)")
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = drawable.texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = colour
            // First the clear alone: a back buffer renders and reads back like any texture.
            let clear = try XCTUnwrap(queue.makeCommandBuffer())
            try XCTUnwrap(clear.makeRenderCommandEncoder(descriptor: pass)).endEncoding()
            clear.commit()
            clear.waitUntilCompleted()
            XCTAssertEqual(clear.status, .completed)
            XCTAssertFalse(device.isDeviceRemoved, "clearing the back buffer removed the device")
            XCTAssertEqual(Self.pixel(drawable.texture, 1, 1), pixel, "the clear landed in the back buffer before presenting")
            // Then an empty command buffer that presents it.
            let cb = try XCTUnwrap(queue.makeCommandBuffer())
            cb.present(drawable)
            cb.commit()
            cb.waitUntilCompleted()
            XCTAssertEqual(cb.status, .completed)
            XCTAssertGreaterThan(drawable.presentedTime, 0)
            return (drawable.texture, (drawable.texture as! MTLD3D12Texture).handle)
        }
        let (first, firstHandle) = try clearAndPresent(MTLClearColorMake(0.25, 0.5, 1, 1), expecting: [255, 128, 64, 255])
        XCTAssertEqual(first.width, 32)
        XCTAssertEqual(first.height, 16)
        XCTAssertEqual(swapChain.presentCount, 1, "Present succeeded: \(swapChain.lastError)")
        XCTAssertEqual(Self.pixel(first, 3, 2), [255, 128, 64, 255], "a presented buffer keeps its pixels")
        let (second, secondHandle) = try clearAndPresent(MTLClearColorMake(0, 1, 0, 1), expecting: [0, 255, 0, 255])
        XCTAssertNotEqual(firstHandle, secondHandle, "the chain flipped to its other buffer")
        XCTAssertEqual(Self.pixel(second, 0, 0), [0, 255, 0, 255])
        XCTAssertEqual(Self.pixel(first, 3, 2), [255, 128, 64, 255], "the earlier buffer is untouched")
        XCTAssertTrue(swapChain.resize(width: 48, height: 24), "resize: \(swapChain.lastError)")
        XCTAssertEqual(swapChain.width, 48)
        let (third, _) = try clearAndPresent(MTLClearColorMake(1, 1, 1, 1), expecting: [255, 255, 255, 255])
        XCTAssertEqual(third.width, 48)
        XCTAssertEqual(third.height, 24)
        XCTAssertEqual(Self.pixel(third, 47, 23), [255, 255, 255, 255])
        XCTAssertEqual(swapChain.presentCount, 3)
        #else
        throw XCTSkip("the Direct3D 12 backend is Windows-only")
        #endif
    }
}
