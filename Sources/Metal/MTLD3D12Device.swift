// Direct3D 12 device for the Metal module (Windows), over the CMetalD3D12 C interface.
// Command buffers record closures and replay them into a D3D12 command list on commit;
// drawables are D3D12 textures read back on present (swap-chain presentation arrives
// with DirectComposition hosting). See ADR-0004.

#if os(Windows)
import Foundation
import CMetalD3D12

public final class MTLD3D12Device: MTLDevice, @unchecked Sendable {
    let handle: OpaquePointer
    public let name: String
    public let registryID: UInt64 = 2
    public let isLowPower: Bool
    public let isHeadless = false
    public let isRemovable = false
    public let hasUnifiedMemory = false
    public let recommendedMaxWorkingSetSize: UInt64
    public let maxThreadsPerThreadgroup = MTLSize(width: 1024, height: 1024, depth: 64)
    public let maxBufferLength = 1 << 31
    public private(set) var currentAllocatedSize = 0
    public let argumentBuffersSupport: MTLArgumentBuffersTier = .tier2
    public let supportsRasterization = true
    /// A queue used for synchronous uploads and readbacks.
    let utilityQueue: OpaquePointer

    /// Nil when D3D12 is unavailable (or the backend is still the placeholder).
    public init?() {
        let debug = ProcessInfo.processInfo.environment["APPKITWIN_D3D12_DEBUG"] == "1"
        guard let h = cm_device_create(debug) else { return nil }
        var info = CMDeviceInfo()
        cm_device_info(h, &info)
        guard let q = cm_queue_create(h) else { cm_device_release(h); return nil }
        handle = h
        utilityQueue = q
        name = withUnsafePointer(to: &info.name) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 128) { String(cString: $0) }
        }
        isLowPower = info.isLowPower || info.isSoftware
        recommendedMaxWorkingSetSize = info.dedicatedVideoMemory
    }

    deinit {
        cm_queue_release(utilityQueue)
        cm_device_release(handle)
    }

    func allocated(_ delta: Int) { currentAllocatedSize += delta }

    public func supportsFamily(_ gpuFamily: MTLGPUFamily) -> Bool { gpuFamily != .metal3 }

    public func makeCommandQueue(maxCommandBufferCount: Int) -> (any MTLCommandQueue)? { MTLD3D12CommandQueue(device: self) }

    public func makeBuffer(length: Int, options: MTLResourceOptions) -> (any MTLBuffer)? {
        guard length > 0, let b = cm_buffer_create(handle, UInt64(length)) else { return nil }
        return MTLD3D12Buffer(device: self, handle: b, length: length, options: options)
    }

    public func makeBuffer(bytes pointer: UnsafeRawPointer, length: Int, options: MTLResourceOptions) -> (any MTLBuffer)? {
        guard let b = makeBuffer(length: length, options: options) else { return nil }
        b.contents().copyMemory(from: pointer, byteCount: length)
        return b
    }

    public func makeTexture(descriptor: MTLTextureDescriptor) -> (any MTLTexture)? {
        guard let format = MTLD3D12.dxgiFormat(descriptor.pixelFormat), descriptor.width > 0, descriptor.height > 0 else { return nil }
        let renderTarget = descriptor.usage.contains(.renderTarget)
        let shaderRead = descriptor.usage.contains(.shaderRead) || descriptor.usage.isEmpty
        guard let t = cm_texture_create(handle, UInt32(descriptor.width), UInt32(descriptor.height), UInt32(max(1, descriptor.mipmapLevelCount)), format, renderTarget, shaderRead) else { return nil }
        return MTLD3D12Texture(device: self, handle: t, descriptor: descriptor)
    }

    public func makeSamplerState(descriptor: MTLSamplerDescriptor) -> (any MTLSamplerState)? { MTLD3D12SamplerState(device: self, descriptor: descriptor) }
    public func makeDepthStencilState(descriptor: MTLDepthStencilDescriptor) -> (any MTLDepthStencilState)? { MTLD3D12DepthStencilState(device: self, descriptor: descriptor) }
    public func makeDefaultLibrary() -> (any MTLLibrary)? { nil }

    /// HLSL source: functions are compiled lazily per entry point when a pipeline uses them.
    public func makeLibrary(source: String, options: MTLCompileOptions?) throws -> any MTLLibrary {
        let language = options?.shaderLanguage ?? .metal
        guard language == .hlsl else {
            throw MTLLibraryError(code: .unsupported, message: "Metal Shading Language is not compiled on Windows yet; pass HLSL with MTLCompileOptions.shaderLanguage = .hlsl (ADR-0004)")
        }
        let functions = MTLReferenceLibrary.scanFunctions(in: source, language: .hlsl)
        return MTLD3D12Library(device: self, source: source, functions: functions)
    }

    public func makeLibrary(data: Data) throws -> any MTLLibrary {
        throw MTLLibraryError(code: .unsupported, message: "compiled library archives are not supported; use HLSL source or DXIL blobs through MTLD3D12Library(blobs:)")
    }

    public func makeRenderPipelineState(descriptor: MTLRenderPipelineDescriptor) throws -> any MTLRenderPipelineState {
        guard let vf = descriptor.vertexFunction as? MTLD3D12Function else { throw MTLLibraryError(code: .functionNotFound, message: "render pipeline needs a D3D12 vertex function") }
        let vs = try vf.compiled(profile: "vs_6_0")
        var ps: OpaquePointer? = nil
        if let ff = descriptor.fragmentFunction as? MTLD3D12Function { ps = try ff.compiled(profile: "ps_6_0") }
        var desc = CMPipelineDesc()
        desc.vertex = vs
        desc.fragment = ps
        var formats = [UInt32](repeating: 0, count: 8)
        var blends = [CMBlend](repeating: CMBlend(), count: 8)
        for i in descriptor.colorAttachments.indices where i < 8 {
            let a = descriptor.colorAttachments[i]!
            formats[i] = MTLD3D12.dxgiFormat(a.pixelFormat) ?? 0
            blends[i] = CMBlend(enabled: a.isBlendingEnabled,
                                srcRGB: MTLD3D12.blend(a.sourceRGBBlendFactor), dstRGB: MTLD3D12.blend(a.destinationRGBBlendFactor), opRGB: MTLD3D12.blendOp(a.rgbBlendOperation),
                                srcAlpha: MTLD3D12.blend(a.sourceAlphaBlendFactor), dstAlpha: MTLD3D12.blend(a.destinationAlphaBlendFactor), opAlpha: MTLD3D12.blendOp(a.alphaBlendOperation),
                                writeMask: MTLD3D12.writeMask(a.writeMask))
        }
        withUnsafeMutableBytes(of: &desc.colorFormats) { $0.copyBytes(from: formats.withUnsafeBytes { Array($0) }) }
        withUnsafeMutableBytes(of: &desc.blends) { $0.copyBytes(from: blends.withUnsafeBytes { Array($0) }) }
        desc.depthFormat = MTLD3D12.dxgiFormat(descriptor.depthAttachmentPixelFormat) ?? 0
        desc.depthWrite = false
        desc.depthCompare = 8
        desc.cullMode = 1
        desc.frontCounterClockwise = false
        desc.wireframe = false
        desc.topologyType = descriptor.inputPrimitiveTopology == .point ? 1 : descriptor.inputPrimitiveTopology == .line ? 2 : 3
        desc.sampleCount = UInt32(max(1, descriptor.rasterSampleCount))
        var attributes: [CMVertexAttribute] = []
        var layouts: [CMVertexLayout] = []
        if let vd = descriptor.vertexDescriptor {
            for i in vd.attributes.indices {
                let a = vd.attributes[i]!
                attributes.append(CMVertexAttribute(semanticIndex: UInt32(i), dxgiFormat: MTLD3D12.vertexFormat(a.format), bufferIndex: UInt32(a.bufferIndex), offset: UInt32(a.offset)))
            }
            let maxLayout = vd.layouts.indices.max() ?? -1
            for i in 0...max(maxLayout, 0) where maxLayout >= 0 {
                let l = vd.layouts[i]!
                layouts.append(CMVertexLayout(stride: UInt32(l.stride), perInstance: l.stepFunction == .perInstance))
            }
        }
        var error = [CChar](repeating: 0, count: 2048)
        let pipeline: OpaquePointer? = attributes.withUnsafeBufferPointer { ab in
            layouts.withUnsafeBufferPointer { lb in
                desc.attributes = ab.baseAddress
                desc.attributeCount = UInt32(ab.count)
                desc.layouts = lb.baseAddress
                desc.layoutCount = UInt32(lb.count)
                return cm_pipeline_create(handle, &desc, &error, 2048)
            }
        }
        guard let pipeline else { throw MTLLibraryError(code: .internal, message: String(cString: error)) }
        return MTLD3D12RenderPipelineState(device: self, handle: pipeline, descriptor: descriptor)
    }

    public func makeComputePipelineState(function: any MTLFunction) throws -> any MTLComputePipelineState {
        throw MTLLibraryError(code: .unsupported, message: "compute pipelines are not implemented on the D3D12 backend yet")
    }

    public func minimumLinearTextureAlignment(for format: MTLPixelFormat) -> Int { 256 }
    public func minimumTextureBufferAlignment(for format: MTLPixelFormat) -> Int { 256 }
    public func makeEvent() -> (any MTLEvent)? { MTLReferenceEvent(device: self) }
    public func makeSharedEvent() -> (any MTLSharedEvent)? { MTLReferenceEvent(device: self) }
}

// MARK: Enum mapping

enum MTLD3D12 {
    static func dxgiFormat(_ f: MTLPixelFormat) -> UInt32? {
        switch f {
        case .invalid: return nil
        case .a8Unorm: return 65
        case .r8Unorm, .r8Unorm_srgb: return 61
        case .r8Snorm: return 63
        case .r8Uint: return 62
        case .r8Sint: return 64
        case .r16Unorm: return 56
        case .r16Snorm: return 58
        case .r16Uint: return 57
        case .r16Sint: return 59
        case .r16Float: return 54
        case .rg8Unorm, .rg8Unorm_srgb: return 49
        case .rg8Snorm: return 51
        case .rg8Uint: return 50
        case .rg8Sint: return 52
        case .r32Uint: return 42
        case .r32Sint: return 43
        case .r32Float: return 41
        case .rg16Unorm: return 35
        case .rg16Snorm: return 37
        case .rg16Uint: return 36
        case .rg16Sint: return 38
        case .rg16Float: return 34
        case .rgba8Unorm: return 28
        case .rgba8Unorm_srgb: return 29
        case .rgba8Snorm: return 31
        case .rgba8Uint: return 30
        case .rgba8Sint: return 32
        case .bgra8Unorm: return 87
        case .bgra8Unorm_srgb: return 91
        case .rgb10a2Unorm: return 24
        case .rgb10a2Uint: return 25
        case .rg11b10Float: return 26
        case .rgb9e5Float: return 67
        case .rg32Uint: return 17
        case .rg32Sint: return 18
        case .rg32Float: return 16
        case .rgba16Unorm: return 11
        case .rgba16Snorm: return 13
        case .rgba16Uint: return 12
        case .rgba16Sint: return 14
        case .rgba16Float: return 10
        case .rgba32Uint: return 3
        case .rgba32Sint: return 4
        case .rgba32Float: return 2
        case .depth16Unorm: return 55
        case .depth32Float: return 40
        case .stencil8: return 45
        case .depth24Unorm_stencil8: return 45
        case .depth32Float_stencil8: return 20
        }
    }

    static func vertexFormat(_ f: MTLVertexFormat) -> UInt32 {
        switch f {
        case .float: return 41
        case .float2: return 16
        case .float3: return 6
        case .float4: return 2
        case .half: return 54
        case .half2: return 34
        case .half4: return 10
        case .int: return 43
        case .int2: return 18
        case .int3: return 8
        case .int4: return 4
        case .uint: return 42
        case .uint2: return 17
        case .uint3: return 7
        case .uint4: return 3
        case .short2: return 38
        case .short4: return 14
        case .ushort2: return 36
        case .ushort4: return 12
        case .short2Normalized: return 37
        case .short4Normalized: return 13
        case .ushort2Normalized: return 35
        case .ushort4Normalized: return 11
        case .uchar4: return 30
        case .char4: return 32
        case .uchar4Normalized: return 28
        case .char4Normalized: return 31
        case .uchar2Normalized: return 49
        case .char2Normalized: return 51
        case .uchar4Normalized_bgra: return 87
        case .uint1010102Normalized, .int1010102Normalized: return 24
        case .floatRG11B10: return 26
        case .floatRGB9E5: return 67
        default: return 0
        }
    }

    static func blend(_ f: MTLBlendFactor) -> UInt32 {
        switch f {
        case .zero: return 1
        case .one: return 2
        case .sourceColor: return 3
        case .oneMinusSourceColor: return 4
        case .sourceAlpha: return 5
        case .oneMinusSourceAlpha: return 6
        case .destinationAlpha: return 7
        case .oneMinusDestinationAlpha: return 8
        case .destinationColor: return 9
        case .oneMinusDestinationColor: return 10
        case .sourceAlphaSaturated: return 11
        case .blendColor, .blendAlpha: return 14
        case .oneMinusBlendColor, .oneMinusBlendAlpha: return 15
        case .source1Color: return 16
        case .oneMinusSource1Color: return 17
        case .source1Alpha: return 18
        case .oneMinusSource1Alpha: return 19
        }
    }

    static func blendOp(_ o: MTLBlendOperation) -> UInt32 { UInt32(o.rawValue) + 1 }
    static func compare(_ c: MTLCompareFunction) -> UInt32 { UInt32(c.rawValue) + 1 }
    static func cull(_ c: MTLCullMode) -> UInt32 { UInt32(c.rawValue) + 1 }
    static func writeMask(_ m: MTLColorWriteMask) -> UInt8 {
        var out: UInt8 = 0
        if m.contains(.red) { out |= 1 }
        if m.contains(.green) { out |= 2 }
        if m.contains(.blue) { out |= 4 }
        if m.contains(.alpha) { out |= 8 }
        return out
    }
    static func topology(_ t: MTLPrimitiveType) -> UInt32 {
        switch t {
        case .point: return 1
        case .line: return 2
        case .lineStrip: return 3
        case .triangle: return 4
        case .triangleStrip: return 5
        }
    }
    static func filter(_ min: MTLSamplerMinMagFilter, _ mag: MTLSamplerMinMagFilter, _ mip: MTLSamplerMipFilter) -> UInt32 {
        if min == .nearest && mag == .nearest { return 0 }
        return mip == .linear ? 0x15 : 0x14
    }
    static func address(_ a: MTLSamplerAddressMode) -> UInt32 {
        switch a {
        case .repeat: return 1
        case .mirrorRepeat: return 2
        case .clampToEdge, .clampToZero: return 3
        case .clampToBorderColor: return 4
        case .mirrorClampToEdge: return 5
        }
    }
}

// MARK: Resources

final class MTLD3D12Buffer: MTLBuffer, @unchecked Sendable {
    var label: String?
    let device: any MTLDevice
    let handle: OpaquePointer
    let length: Int
    let resourceOptions: MTLResourceOptions
    var cpuCacheMode: MTLCPUCacheMode { .defaultCache }
    var storageMode: MTLStorageMode { .shared }
    var hazardTrackingMode: MTLHazardTrackingMode { .tracked }
    var allocatedSize: Int { length }
    let gpuAddress: UInt64
    private let mapped: UnsafeMutableRawPointer

    init(device: MTLD3D12Device, handle: OpaquePointer, length: Int, options: MTLResourceOptions) {
        self.device = device
        self.handle = handle
        self.length = length
        resourceOptions = options
        mapped = cm_buffer_map(handle) ?? UnsafeMutableRawPointer.allocate(byteCount: length, alignment: 16)
        gpuAddress = cm_buffer_gpu_address(handle)
        device.allocated(length)
    }

    deinit {
        cm_buffer_release(handle)
        (device as? MTLD3D12Device)?.allocated(-length)
    }

    func contents() -> UnsafeMutableRawPointer { mapped }
    func didModifyRange(_ range: Range<Int>) {}
}

final class MTLD3D12Texture: MTLTexture, @unchecked Sendable {
    var label: String?
    let device: any MTLDevice
    let handle: OpaquePointer
    let textureType: MTLTextureType
    let pixelFormat: MTLPixelFormat
    let width: Int, height: Int, depth: Int
    let mipmapLevelCount: Int
    let sampleCount: Int
    let arrayLength: Int
    let usage: MTLTextureUsage
    let isFramebufferOnly = false
    let resourceOptions: MTLResourceOptions
    var cpuCacheMode: MTLCPUCacheMode { .defaultCache }
    var storageMode: MTLStorageMode { .private }
    var hazardTrackingMode: MTLHazardTrackingMode { .tracked }
    var allocatedSize: Int { width * height * pixelFormat.bytesPerPixel }
    let d3dDevice: MTLD3D12Device

    init(device: MTLD3D12Device, handle: OpaquePointer, descriptor d: MTLTextureDescriptor) {
        self.device = device
        d3dDevice = device
        self.handle = handle
        textureType = d.textureType; pixelFormat = d.pixelFormat
        width = d.width; height = d.height; depth = d.depth
        mipmapLevelCount = d.mipmapLevelCount; sampleCount = d.sampleCount; arrayLength = d.arrayLength
        usage = d.usage; resourceOptions = d.resourceOptions
        device.allocated(allocatedSize)
    }

    deinit {
        cm_texture_release(handle)
        d3dDevice.allocated(-allocatedSize)
    }

    func replace(region: MTLRegion, mipmapLevel level: Int, slice: Int, withBytes pixelBytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int) {
        guard region.origin.x == 0, region.origin.y == 0, region.size.width == width else {
            // Partial uploads go through a full-size staging copy.
            let bpp = pixelFormat.bytesPerPixel
            var full = [UInt8](repeating: 0, count: width * bpp * height)
            getBytes(&full, bytesPerRow: width * bpp, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: level)
            for row in 0..<region.size.height {
                let dst = (region.origin.y + row) * width * bpp + region.origin.x * bpp
                full.withUnsafeMutableBytes { $0.baseAddress!.advanced(by: dst).copyMemory(from: pixelBytes + row * bytesPerRow, byteCount: region.size.width * bpp) }
            }
            _ = cm_texture_upload(d3dDevice.handle, d3dDevice.utilityQueue, handle, UInt32(level), full, UInt32(width * bpp), UInt32(height))
            return
        }
        _ = cm_texture_upload(d3dDevice.handle, d3dDevice.utilityQueue, handle, UInt32(level), pixelBytes, UInt32(bytesPerRow), UInt32(region.size.height))
    }

    func getBytes(_ pixelBytes: UnsafeMutableRawPointer, bytesPerRow: Int, bytesPerImage: Int, from region: MTLRegion, mipmapLevel level: Int, slice: Int) {
        let bpp = pixelFormat.bytesPerPixel
        if region.origin.x == 0, region.origin.y == 0, region.size.width == width, region.size.height == height {
            _ = cm_texture_read(d3dDevice.handle, d3dDevice.utilityQueue, handle, pixelBytes, UInt32(bytesPerRow), UInt32(height))
            return
        }
        var full = [UInt8](repeating: 0, count: width * bpp * height)
        _ = cm_texture_read(d3dDevice.handle, d3dDevice.utilityQueue, handle, &full, UInt32(width * bpp), UInt32(height))
        for row in 0..<region.size.height {
            let src = (region.origin.y + row) * width * bpp + region.origin.x * bpp
            full.withUnsafeBytes { (pixelBytes + row * bytesPerRow).copyMemory(from: $0.baseAddress!.advanced(by: src), byteCount: region.size.width * bpp) }
        }
    }

    func makeTextureView(pixelFormat: MTLPixelFormat) -> (any MTLTexture)? { pixelFormat == self.pixelFormat ? self : nil }
}

final class MTLD3D12SamplerState: MTLSamplerState {
    let label: String?
    let device: any MTLDevice
    let filter: UInt32, addressU: UInt32, addressV: UInt32
    init(device: any MTLDevice, descriptor d: MTLSamplerDescriptor) {
        self.device = device
        label = d.label
        filter = MTLD3D12.filter(d.minFilter, d.magFilter, d.mipFilter)
        addressU = MTLD3D12.address(d.sAddressMode)
        addressV = MTLD3D12.address(d.tAddressMode)
    }
}

final class MTLD3D12DepthStencilState: MTLDepthStencilState {
    let label: String?
    let device: any MTLDevice
    let depthWrite: Bool
    let compare: UInt32
    init(device: any MTLDevice, descriptor d: MTLDepthStencilDescriptor) {
        self.device = device
        label = d.label
        depthWrite = d.isDepthWriteEnabled
        compare = MTLD3D12.compare(d.depthCompareFunction)
    }
}

// MARK: Shaders

public final class MTLD3D12Function: MTLFunction {
    public var label: String?
    public let device: any MTLDevice
    public let functionType: MTLFunctionType
    public let name: String
    private let source: String?
    private let blob: Data?
    private var compiledHandles: [String: OpaquePointer] = [:]

    init(device: any MTLDevice, name: String, type: MTLFunctionType, source: String?, blob: Data?) {
        self.device = device; self.name = name; functionType = type; self.source = source; self.blob = blob
    }

    deinit { for (_, h) in compiledHandles { cm_shader_release(h) } }

    func compiled(profile: String) throws -> OpaquePointer {
        if let h = compiledHandles[profile] { return h }
        var error = [CChar](repeating: 0, count: 4096)
        var h: OpaquePointer? = nil
        if let blob {
            h = blob.withUnsafeBytes { cm_shader_from_blob($0.baseAddress, UInt32($0.count)) }
        } else if let source {
            let utf8 = Array(source.utf8)
            h = utf8.withUnsafeBufferPointer { buf in
                buf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: buf.count) { cm_shader_compile_hlsl($0, UInt32(buf.count), name, profile, &error, 4096) }
            }
        }
        guard let h else { throw MTLLibraryError(code: .compileFailure, message: String(cString: error)) }
        compiledHandles[profile] = h
        return h
    }
}

public final class MTLD3D12Library: MTLLibrary {
    public var label: String?
    public let device: any MTLDevice
    private let source: String?
    private let blobs: [String: (Data, MTLFunctionType)]
    private let functions: [(String, MTLFunctionType)]
    public var functionNames: [String] { functions.map(\.0) }

    init(device: any MTLDevice, source: String, functions: [(String, MTLFunctionType)]) {
        self.device = device; self.source = source; self.functions = functions; blobs = [:]
    }

    /// A library of precompiled DXIL/DXBC entry points keyed by function name.
    public init(device: any MTLDevice, blobs: [String: (Data, MTLFunctionType)]) {
        self.device = device; source = nil; self.blobs = blobs
        functions = blobs.map { ($0.key, $0.value.1) }
    }

    public func makeFunction(name: String) -> (any MTLFunction)? {
        guard let f = functions.first(where: { $0.0 == name }) else { return nil }
        return MTLD3D12Function(device: device, name: name, type: f.1, source: source, blob: blobs[name]?.0)
    }
}

final class MTLD3D12RenderPipelineState: MTLRenderPipelineState {
    let label: String?
    let device: any MTLDevice
    let handle: OpaquePointer
    let vertexStrides: [Int: Int]
    init(device: any MTLDevice, handle: OpaquePointer, descriptor: MTLRenderPipelineDescriptor) {
        self.device = device
        self.handle = handle
        label = descriptor.label
        var strides: [Int: Int] = [:]
        if let vd = descriptor.vertexDescriptor { for i in vd.layouts.indices { strides[i] = vd.layouts[i].stride } }
        vertexStrides = strides
    }
    deinit { cm_pipeline_release(handle) }
}

// MARK: Commands

final class MTLD3D12CommandQueue: MTLCommandQueue {
    var label: String?
    let device: any MTLDevice
    let handle: OpaquePointer?
    init(device: MTLD3D12Device) {
        self.device = device
        handle = cm_queue_create(device.handle)
    }
    deinit { cm_queue_release(handle) }
    func makeCommandBuffer() -> (any MTLCommandBuffer)? { MTLD3D12CommandBuffer(queue: self) }
    func makeCommandBufferWithUnretainedReferences() -> (any MTLCommandBuffer)? { makeCommandBuffer() }
}

final class MTLD3D12CommandBuffer: MTLCommandBuffer {
    let device: any MTLDevice
    let commandQueue: any MTLCommandQueue
    var label: String?
    private(set) var status: MTLCommandBufferStatus = .notEnqueued
    private(set) var error: (any Error)?
    private var work: [(OpaquePointer) -> Void] = []
    private var scheduledHandlers: [(any MTLCommandBuffer) -> Void] = []
    private var completedHandlers: [(any MTLCommandBuffer) -> Void] = []
    private var drawables: [any MTLDrawable] = []
    private var fenceValue: UInt64 = 0

    init(queue: MTLD3D12CommandQueue) { device = queue.device; commandQueue = queue }

    func record(_ block: @escaping (OpaquePointer) -> Void) { work.append(block) }

    func enqueue() { if status == .notEnqueued { status = .enqueued } }

    func commit() {
        guard status.rawValue < MTLCommandBufferStatus.committed.rawValue else { return }
        status = .committed
        guard let d3d = device as? MTLD3D12Device, let q = (commandQueue as? MTLD3D12CommandQueue)?.handle, let list = cm_commandlist_create(d3d.handle) else {
            status = .error
            error = MTLCommandBufferError.internal
            for h in completedHandlers { h(self) }
            return
        }
        cm_commandlist_reset(list)
        for w in work { w(list) }
        work.removeAll()
        status = .scheduled
        for h in scheduledHandlers { h(self) }
        fenceValue = cm_commandlist_execute(list, q)
        cm_queue_wait(q, fenceValue)
        cm_commandlist_release(list)
        for d in drawables { d.present() }
        drawables.removeAll()
        status = .completed
        for h in completedHandlers { h(self) }
    }

    func addScheduledHandler(_ block: @escaping (any MTLCommandBuffer) -> Void) { scheduledHandlers.append(block) }
    func addCompletedHandler(_ block: @escaping (any MTLCommandBuffer) -> Void) { completedHandlers.append(block) }
    func present(_ drawable: any MTLDrawable) { drawables.append(drawable) }
    func waitUntilScheduled() {}
    func waitUntilCompleted() { if status != .completed { commit() } }

    func makeRenderCommandEncoder(descriptor renderPassDescriptor: MTLRenderPassDescriptor) -> (any MTLRenderCommandEncoder)? {
        let pass = renderPassDescriptor.copy() as! MTLRenderPassDescriptor
        record { list in
            var colors: [OpaquePointer?] = []
            var loads: [UInt32] = []
            var clears: [Float] = []
            for i in pass.colorAttachments.indices {
                let a = pass.colorAttachments[i]!
                guard let t = a.texture as? MTLD3D12Texture else { continue }
                colors.append(t.handle)
                loads.append(UInt32(a.loadAction.rawValue))
                clears += [Float(a.clearColor.red), Float(a.clearColor.green), Float(a.clearColor.blue), Float(a.clearColor.alpha)]
            }
            let depth = (pass.depthAttachment.texture as? MTLD3D12Texture)?.handle
            colors.withUnsafeMutableBufferPointer { cb in
                cm_commandlist_begin_render_pass(list, cb.baseAddress, loads, clears, UInt32(cb.count), depth, UInt32(pass.depthAttachment.loadAction.rawValue), Float(pass.depthAttachment.clearDepth))
            }
        }
        return MTLD3D12RenderCommandEncoder(buffer: self)
    }

    func makeBlitCommandEncoder() -> (any MTLBlitCommandEncoder)? { MTLD3D12BlitCommandEncoder(buffer: self) }
    func makeComputeCommandEncoder() -> (any MTLComputeCommandEncoder)? { nil }
}

class MTLD3D12Encoder: MTLCommandEncoder {
    let buffer: MTLD3D12CommandBuffer
    var device: any MTLDevice { buffer.device }
    var label: String?
    init(buffer: MTLD3D12CommandBuffer) { self.buffer = buffer }
    func endEncoding() {}
    func insertDebugSignpost(_ string: String) {}
    func pushDebugGroup(_ string: String) {}
    func popDebugGroup() {}
}

final class MTLD3D12RenderCommandEncoder: MTLD3D12Encoder, MTLRenderCommandEncoder {
    private var pipeline: MTLD3D12RenderPipelineState?

    override func endEncoding() { buffer.record { cm_commandlist_end_render_pass($0) } }

    func setRenderPipelineState(_ pipelineState: any MTLRenderPipelineState) {
        guard let p = pipelineState as? MTLD3D12RenderPipelineState else { return }
        pipeline = p
        buffer.record { cm_commandlist_set_pipeline($0, p.handle) }
    }
    func setViewport(_ v: MTLViewport) { buffer.record { cm_commandlist_set_viewport($0, Float(v.originX), Float(v.originY), Float(v.width), Float(v.height), Float(v.znear), Float(v.zfar)) } }
    func setScissorRect(_ r: MTLScissorRect) { buffer.record { cm_commandlist_set_scissor($0, Int32(r.x), Int32(r.y), Int32(r.width), Int32(r.height)) } }
    func setFrontFacing(_ frontFacingWinding: MTLWinding) {}
    func setCullMode(_ cullMode: MTLCullMode) {}
    func setTriangleFillMode(_ fillMode: MTLTriangleFillMode) {}
    func setDepthStencilState(_ depthStencilState: (any MTLDepthStencilState)?) {}
    func setBlendColor(red: Float, green: Float, blue: Float, alpha: Float) {}
    func setStencilReferenceValue(_ referenceValue: UInt32) {}

    func setVertexBuffer(_ b: (any MTLBuffer)?, offset: Int, index: Int) {
        guard let b = b as? MTLD3D12Buffer else { return }
        let stride = pipeline?.vertexStrides[index] ?? 0
        buffer.record { list in
            cm_commandlist_set_vertex_buffer(list, UInt32(index), b.handle, UInt64(offset), UInt32(stride))
            cm_commandlist_set_shader_buffer(list, false, UInt32(index), b.handle, UInt64(offset))
        }
    }
    func setVertexBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int) {
        guard let b = device.makeBuffer(bytes: bytes, length: length, options: []) else { return }
        setVertexBuffer(b, offset: 0, index: index)
    }
    func setVertexTexture(_ t: (any MTLTexture)?, index: Int) { let h = (t as? MTLD3D12Texture)?.handle; buffer.record { cm_commandlist_set_shader_texture($0, false, UInt32(index), h) } }
    func setVertexSamplerState(_ s: (any MTLSamplerState)?, index: Int) {
        guard let s = s as? MTLD3D12SamplerState else { return }
        buffer.record { cm_commandlist_set_sampler($0, false, UInt32(index), s.filter, s.addressU, s.addressV) }
    }
    func setFragmentBuffer(_ b: (any MTLBuffer)?, offset: Int, index: Int) {
        let h = (b as? MTLD3D12Buffer)?.handle
        buffer.record { cm_commandlist_set_shader_buffer($0, true, UInt32(index), h, UInt64(offset)) }
    }
    func setFragmentBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int) {
        guard let b = device.makeBuffer(bytes: bytes, length: length, options: []) else { return }
        setFragmentBuffer(b, offset: 0, index: index)
    }
    func setFragmentTexture(_ t: (any MTLTexture)?, index: Int) { let h = (t as? MTLD3D12Texture)?.handle; buffer.record { cm_commandlist_set_shader_texture($0, true, UInt32(index), h) } }
    func setFragmentSamplerState(_ s: (any MTLSamplerState)?, index: Int) {
        guard let s = s as? MTLD3D12SamplerState else { return }
        buffer.record { cm_commandlist_set_sampler($0, true, UInt32(index), s.filter, s.addressU, s.addressV) }
    }
    func drawPrimitives(type: MTLPrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int) {
        buffer.record { cm_commandlist_draw($0, MTLD3D12.topology(type), UInt32(vertexStart), UInt32(vertexCount), UInt32(instanceCount)) }
    }
    func drawIndexedPrimitives(type: MTLPrimitiveType, indexCount: Int, indexType: MTLIndexType, indexBuffer: any MTLBuffer, indexBufferOffset: Int, instanceCount: Int) {
        guard let ib = indexBuffer as? MTLD3D12Buffer else { return }
        buffer.record { cm_commandlist_draw_indexed($0, MTLD3D12.topology(type), UInt32(indexCount), indexType == .uint32, ib.handle, UInt64(indexBufferOffset), UInt32(instanceCount)) }
    }
}

final class MTLD3D12BlitCommandEncoder: MTLD3D12Encoder, MTLBlitCommandEncoder {
    func copy(from s: any MTLBuffer, sourceOffset: Int, to d: any MTLBuffer, destinationOffset: Int, size: Int) {
        guard let s = s as? MTLD3D12Buffer, let d = d as? MTLD3D12Buffer else { return }
        buffer.record { cm_commandlist_copy_buffer($0, s.handle, UInt64(sourceOffset), d.handle, UInt64(destinationOffset), UInt64(size)) }
    }
    func copy(from s: any MTLTexture, to d: any MTLTexture) {
        guard let s = s as? MTLD3D12Texture, let d = d as? MTLD3D12Texture else { return }
        buffer.record { cm_commandlist_copy_texture($0, s.handle, d.handle) }
    }
    func copy(from sourceTexture: any MTLTexture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: MTLOrigin, sourceSize: MTLSize, to destinationTexture: any MTLTexture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: MTLOrigin) {
        copy(from: sourceTexture, to: destinationTexture)
    }
    func copy(from sourceBuffer: any MTLBuffer, sourceOffset: Int, sourceBytesPerRow: Int, sourceBytesPerImage: Int, sourceSize: MTLSize, to destinationTexture: any MTLTexture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: MTLOrigin) {
        buffer.record { _ in
            destinationTexture.replace(region: MTLRegion(origin: destinationOrigin, size: sourceSize), mipmapLevel: destinationLevel, withBytes: sourceBuffer.contents().advanced(by: sourceOffset), bytesPerRow: sourceBytesPerRow)
        }
    }
    func copy(from sourceTexture: any MTLTexture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: MTLOrigin, sourceSize: MTLSize, to destinationBuffer: any MTLBuffer, destinationOffset: Int, destinationBytesPerRow: Int, destinationBytesPerImage: Int) {
        buffer.record { _ in
            sourceTexture.getBytes(destinationBuffer.contents().advanced(by: destinationOffset), bytesPerRow: destinationBytesPerRow, from: MTLRegion(origin: sourceOrigin, size: sourceSize), mipmapLevel: sourceLevel)
        }
    }
    func fill(buffer target: any MTLBuffer, range: Range<Int>, value: UInt8) {
        buffer.record { _ in
            let r = range.clamped(to: 0..<target.length)
            target.contents().advanced(by: r.lowerBound).initializeMemory(as: UInt8.self, repeating: value, count: r.count)
        }
    }
    func generateMipmaps(for texture: any MTLTexture) {}
    func synchronize(resource: any MTLResource) {}
}
#endif
