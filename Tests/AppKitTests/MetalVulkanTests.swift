// The Vulkan backend of the Metal module (ADR-0012): resources, blits and compute on the
// Vulkan device, with the reference device as the oracle. The tests skip when no Vulkan
// device exists (macOS, or a Linux container without a loader or ICD).

import XCTest
@testable import AppKit
import Metal
import MetalKit

final class MetalVulkanDeviceTests: XCTestCase, @unchecked Sendable {
    /// The Vulkan device, or a skip naming why there is none.
    static func vulkanDevice() throws -> any MTLDevice {
        #if os(Linux)
        guard let d = MTLVulkanDevice() else { throw XCTSkip("no Vulkan device: \(MTLVulkanDevice.unavailabilityReason)") }
        return d
        #else
        throw XCTSkip("the Vulkan backend is Linux-only")
        #endif
    }

    /// `doubleValues` from `kernelHLSL`, compiled with glslang 15 (`-D -V --target-env vulkan1.3
    /// -S comp --shift-uav-binding 24 0 0 1`): `RWStructuredBuffer<float> data : register(u0, space1)`
    /// is descriptor set 1, binding 0 (ADR-0012).
    static let doubleValuesSPIRV: [UInt32] = [
        0x07230203,0x00010600,0x0008000b,0x00000030,0x00000000,0x00020011,0x00000001,0x0006000b,
        0x00000001,0x4c534c47,0x6474732e,0x3035342e,0x00000000,0x0003000e,0x00000000,0x00000001,
        0x0009000f,0x00000005,0x00000004,0x62756f64,0x6156656c,0x7365756c,0x00000000,0x00000011,
        0x00000022,0x00060010,0x00000004,0x00000011,0x00000040,0x00000001,0x00000001,0x00030003,
        0x00000005,0x000001f4,0x00060005,0x00000004,0x62756f64,0x6156656c,0x7365756c,0x00000000,
        0x00040005,0x0000000f,0x61746164,0x00000000,0x00050006,0x0000000f,0x00000000,0x74616440,
        0x00000061,0x00040005,0x00000011,0x61746164,0x00000000,0x00030005,0x00000022,0x00006469,
        0x00040047,0x0000000e,0x00000006,0x00000004,0x00030047,0x0000000f,0x00000002,0x00050048,
        0x0000000f,0x00000000,0x00000023,0x00000000,0x00040047,0x00000011,0x00000021,0x00000000,
        0x00040047,0x00000011,0x00000022,0x00000001,0x00040047,0x00000022,0x0000000b,0x0000001c,
        0x00020013,0x00000002,0x00030021,0x00000003,0x00000002,0x00040015,0x00000006,0x00000020,
        0x00000000,0x00040017,0x00000007,0x00000006,0x00000003,0x00030016,0x0000000d,0x00000020,
        0x0003001d,0x0000000e,0x0000000d,0x0003001e,0x0000000f,0x0000000e,0x00040020,0x00000010,
        0x0000000c,0x0000000f,0x0004003b,0x00000010,0x00000011,0x0000000c,0x00040015,0x00000012,
        0x00000020,0x00000001,0x0004002b,0x00000012,0x00000013,0x00000000,0x00040020,0x0000001a,
        0x0000000c,0x0000000d,0x0004002b,0x0000000d,0x0000001d,0x40000000,0x00040020,0x00000021,
        0x00000001,0x00000007,0x0004003b,0x00000021,0x00000022,0x00000001,0x00050036,0x00000002,
        0x00000004,0x00000000,0x00000003,0x000200f8,0x00000005,0x0004003d,0x00000007,0x00000023,
        0x00000022,0x00050051,0x00000006,0x00000029,0x00000023,0x00000000,0x00050051,0x00000006,
        0x0000002b,0x00000023,0x00000000,0x00060041,0x0000001a,0x0000002c,0x00000011,0x00000013,
        0x0000002b,0x0004003d,0x0000000d,0x0000002d,0x0000002c,0x00050085,0x0000000d,0x0000002e,
        0x0000002d,0x0000001d,0x00060041,0x0000001a,0x0000002f,0x00000011,0x00000013,0x00000029,
        0x0003003e,0x0000002f,0x0000002e,0x000100fd,0x00010038,
    ]

    static let kernelHLSL = """
    RWStructuredBuffer<float> data : register(u0, space1);
    [numthreads(64, 1, 1)]
    void doubleValues(uint3 id : SV_DispatchThreadID) { data[id.x] = data[id.x] * 2; }
    """

    static let kernelMSL = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void tripleValues(device float* data [[buffer(0)]], uint id [[thread_position_in_grid]]) { data[id] = data[id] * 3; }
    """

    func testDeviceIsTheSystemDefaultOnLinux() throws {
        let device = try Self.vulkanDevice()
        XCTAssertTrue(device.supportsRasterization)
        XCTAssertFalse(device.name.isEmpty)
        #if os(Linux)
        if ProcessInfo.processInfo.environment["APPKITWIN_METAL_REFERENCE"] != "1" {
            XCTAssertTrue(MTLCreateSystemDefaultDevice() is MTLVulkanDevice, "the registry prefers the Vulkan device")
        }
        #endif
    }

    func testBuffersBlitsAndFills() throws {
        let device = try Self.vulkanDevice()
        let queue = try XCTUnwrap(device.makeCommandQueue())
        var floats: [Float] = [1, 2, 3, 4, 5, 6, 7, 8]
        let a = try XCTUnwrap(device.makeBuffer(bytes: &floats, length: 32, options: .storageModeShared))
        let b = try XCTUnwrap(device.makeBuffer(length: 32, options: []))
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        let blit = try XCTUnwrap(cb.makeBlitCommandEncoder())
        blit.copy(from: a, sourceOffset: 4, to: b, destinationOffset: 0, size: 12)
        blit.fill(buffer: b, range: 13..<31, value: 0xAB)   // ragged ends on both sides
        blit.endEncoding()
        var completed = false
        cb.addCompletedHandler { _ in completed = true }
        cb.commit()
        cb.waitUntilCompleted()
        XCTAssertTrue(completed)
        XCTAssertEqual(cb.status, .completed)
        XCTAssertEqual(b.contents().load(as: Float.self), 2)
        XCTAssertEqual(b.contents().load(fromByteOffset: 8, as: Float.self), 4)
        let bytes = Array(UnsafeBufferPointer(start: b.contents().assumingMemoryBound(to: UInt8.self), count: 32))
        XCTAssertEqual(bytes[12], 0)
        XCTAssertEqual(Array(bytes[13..<31]), [UInt8](repeating: 0xAB, count: 18))
        XCTAssertEqual(bytes[31], 0)
    }

    func testTextureUploadReadbackAndCopies() throws {
        let device = try Self.vulkanDevice()
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 8, height: 4, mipmapped: false)
        desc.usage = [.shaderRead, .renderTarget]
        let tex = try XCTUnwrap(device.makeTexture(descriptor: desc))
        var pixels = [UInt8](repeating: 0, count: 8 * 4 * 4)
        for i in 0..<32 { pixels[i * 4] = UInt8(i); pixels[i * 4 + 1] = 100; pixels[i * 4 + 2] = 200; pixels[i * 4 + 3] = 255 }
        tex.replace(region: MTLRegionMake2D(0, 0, 8, 4), mipmapLevel: 0, withBytes: pixels, bytesPerRow: 32)
        var back = [UInt8](repeating: 0, count: pixels.count)
        tex.getBytes(&back, bytesPerRow: 32, from: MTLRegionMake2D(0, 0, 8, 4), mipmapLevel: 0)
        XCTAssertEqual(back, pixels)
        var one = [UInt8](repeating: 0, count: 4)
        tex.getBytes(&one, bytesPerRow: 4, from: MTLRegionMake2D(3, 1, 1, 1), mipmapLevel: 0)
        XCTAssertEqual(one, [11, 100, 200, 255])
        // A partial upload lands only in its region.
        let patch: [UInt8] = [9, 9, 9, 9, 8, 8, 8, 8]
        tex.replace(region: MTLRegionMake2D(6, 3, 2, 1), mipmapLevel: 0, withBytes: patch, bytesPerRow: 8)
        tex.getBytes(&back, bytesPerRow: 32, from: MTLRegionMake2D(0, 0, 8, 4), mipmapLevel: 0)
        XCTAssertEqual(Array(back[(3 * 32 + 24)..<(3 * 32 + 32)]), patch)
        XCTAssertEqual(Array(back[0..<4]), [0, 100, 200, 255])

        // Texture → texture, buffer → texture and texture → buffer through the blit encoder.
        let copy = try XCTUnwrap(device.makeTexture(descriptor: desc))
        let upload = try XCTUnwrap(device.makeBuffer(bytes: pixels.reversed(), length: pixels.count, options: []))
        let readback = try XCTUnwrap(device.makeBuffer(length: pixels.count, options: []))
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        let blit = try XCTUnwrap(cb.makeBlitCommandEncoder())
        blit.copy(from: tex, to: copy)
        blit.copy(from: upload, sourceOffset: 0, sourceBytesPerRow: 32, sourceBytesPerImage: 128, sourceSize: MTLSize(width: 8, height: 2, depth: 1), to: copy, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 2, z: 0))
        blit.copy(from: copy, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: 8, height: 4, depth: 1), to: readback, destinationOffset: 0, destinationBytesPerRow: 32, destinationBytesPerImage: 128)
        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        XCTAssertEqual(cb.status, .completed)
        let out = Array(UnsafeBufferPointer(start: readback.contents().assumingMemoryBound(to: UInt8.self), count: pixels.count))
        XCTAssertEqual(Array(out[0..<64]), Array(back[0..<64]), "rows 0-1 come from the texture copy")
        XCTAssertEqual(Array(out[64..<128]), Array(pixels.reversed()[0..<64]), "rows 2-3 come from the buffer upload")
    }

    func testComputeFromSPIRVPassThrough() throws {
        let device = try Self.vulkanDevice()
        guard !Self.doubleValuesSPIRV.isEmpty else { throw XCTSkip("the embedded SPIR-V kernel is absent") }
        let data = Self.doubleValuesSPIRV.withUnsafeBufferPointer { Data(buffer: $0) }
        let library = try device.makeLibrary(data: data)
        XCTAssertEqual(library.functionNames, ["doubleValues"])
        let kernel = try XCTUnwrap(library.makeFunction(name: "doubleValues"))
        XCTAssertEqual(kernel.functionType, .kernel)
        try Self.runKernel(device, kernel, factor: 2)
    }

    func testComputeFromHLSLAndMSLSource() throws {
        let device = try Self.vulkanDevice()
        let options = MTLCompileOptions()
        options.shaderLanguage = .hlsl
        let hlsl = try device.makeLibrary(source: Self.kernelHLSL, options: options)
        let doubling = try XCTUnwrap(hlsl.makeFunction(name: "doubleValues"))
        do {
            try Self.runKernel(device, doubling, factor: 2)
        } catch let error as MTLLibraryError where error.code == .unsupported {
            throw XCTSkip("no SPIR-V compiler on PATH: \(error.message)")
        }
        // MSL goes through the translator (ADR-0006): `device float*` is a space1 storage buffer.
        let msl = try device.makeLibrary(source: Self.kernelMSL, options: nil)
        let tripling = try XCTUnwrap(msl.makeFunction(name: "tripleValues"))
        try Self.runKernel(device, tripling, factor: 3)
    }

    /// Runs `kernel` over 256 floats at buffer slot 0 and checks each is multiplied by `factor`.
    static func runKernel(_ device: any MTLDevice, _ kernel: any MTLFunction, factor: Float) throws {
        let pipeline = try device.makeComputePipelineState(function: kernel)
        XCTAssertGreaterThanOrEqual(pipeline.maxTotalThreadsPerThreadgroup, 64)
        let values = (0..<256).map { Float($0) }
        let buffer = try XCTUnwrap(values.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: []) })
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let cb = try XCTUnwrap(queue.makeCommandBuffer())
        let enc = try XCTUnwrap(cb.makeComputeCommandEncoder())
        enc.setComputePipelineState(pipeline)
        enc.setBuffer(buffer, offset: 0, index: 0)
        enc.dispatchThreads(MTLSize(width: 256, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1))
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        XCTAssertEqual(cb.status, .completed)
        let out = Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: Float.self), count: 256))
        XCTAssertEqual(out, values.map { $0 * factor }, "\(kernel.name) ran over the whole grid")
    }

    func testRenderPassClearMatchesReferenceDevice() throws {
        let vulkan = try Self.vulkanDevice()
        let reference = MTLReferenceDevice()
        var results: [[UInt8]] = []
        for device in [reference, vulkan] as [any MTLDevice] {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 16, height: 8, mipmapped: false)
            desc.usage = [.renderTarget, .shaderRead]
            let tex = try XCTUnwrap(device.makeTexture(descriptor: desc))
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = tex
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0.25, 0.5, 1, 1)
            let queue = try XCTUnwrap(device.makeCommandQueue())
            let cb = try XCTUnwrap(queue.makeCommandBuffer())
            try XCTUnwrap(cb.makeRenderCommandEncoder(descriptor: pass)).endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
            var px = [UInt8](repeating: 0, count: 16 * 8 * 4)
            tex.getBytes(&px, bytesPerRow: 64, from: MTLRegionMake2D(0, 0, 16, 8), mipmapLevel: 0)
            results.append(px)
        }
        XCTAssertEqual(results[0], results[1], "a cleared bgra8 target reads back identically on both devices")
        XCTAssertEqual(Array(results[1][0..<4]), [255, 128, 64, 255])
    }
}
