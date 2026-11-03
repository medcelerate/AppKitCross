// Vulkan device for the Metal module (Linux), over the CMetalVulkan C interface.
// Command buffers record closures and replay them into a Vulkan command buffer on
// commit; drawables are Vulkan images read back on present (MTKView's readback seam).
// Shaders are SPIR-V: passed through, or compiled from HLSL/MSL with dxc or glslang
// found on PATH. See ADR-0011.

#if os(Linux)
import Foundation
import CMetalVulkan

public final class MTLVulkanDevice: MTLDevice, @unchecked Sendable {
    let handle: OpaquePointer
    public let name: String
    public let registryID: UInt64 = 3
    public let isLowPower: Bool
    public let isHeadless: Bool
    public let isRemovable = false
    public let hasUnifiedMemory: Bool
    public let recommendedMaxWorkingSetSize: UInt64
    public let maxThreadsPerThreadgroup: MTLSize
    public let maxBufferLength = 1 << 30
    public private(set) var currentAllocatedSize = 0
    public let argumentBuffersSupport: MTLArgumentBuffersTier = .tier2
    public let supportsRasterization = true
    /// True for CPU implementations (lavapipe, SwiftShader).
    public let isSoftwareDevice: Bool
    /// True when `APPKITWIN_VULKAN_DEBUG=1` found and enabled the validation layer.
    public let validationEnabled: Bool
    let subgroupSize: Int
    let maxComputeInvocations: Int
    let uniformAlignment: Int
    private let lock = NSLock()

    /// Nil when there is no loader, no Vulkan 1.3 device with a graphics and compute
    /// queue, or the shim was built without the headers; `unavailabilityReason` says which.
    public init?() {
        let debug = ProcessInfo.processInfo.environment["APPKITWIN_VULKAN_DEBUG"] == "1"
        guard let h = cmv_device_create(debug) else { return nil }
        var info = CMVDeviceInfo()
        cmv_device_info(h, &info)
        handle = h
        name = withUnsafePointer(to: &info.name) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
        }
        isSoftwareDevice = info.isSoftware
        validationEnabled = info.validation
        isLowPower = info.isSoftware || info.isIntegrated
        isHeadless = !info.presentable
        hasUnifiedMemory = info.isSoftware || info.isIntegrated
        recommendedMaxWorkingSetSize = info.deviceLocalMemory
        maxThreadsPerThreadgroup = MTLSize(width: Int(info.maxComputeWorkGroupSize.0), height: Int(info.maxComputeWorkGroupSize.1), depth: Int(info.maxComputeWorkGroupSize.2))
        subgroupSize = Int(max(1, info.subgroupSize))
        maxComputeInvocations = Int(max(1, info.maxComputeWorkGroupInvocations))
        uniformAlignment = Int(max(16, info.minUniformBufferOffsetAlignment))
    }

    deinit { cmv_device_release(handle) }

    /// Why `init` returned nil the last time (loader, devices, headers).
    public static var unavailabilityReason: String { String(cString: cmv_last_error()) }

    func allocated(_ delta: Int) { lock.lock(); currentAllocatedSize += delta; lock.unlock() }

    public func supportsFamily(_ gpuFamily: MTLGPUFamily) -> Bool { gpuFamily != .metal3 }

    public func makeCommandQueue(maxCommandBufferCount: Int) -> (any MTLCommandQueue)? {
        guard let q = cmv_queue_create(handle) else { return nil }
        return MTLVulkanCommandQueue(device: self, handle: q)
    }

    public func makeBuffer(length: Int, options: MTLResourceOptions) -> (any MTLBuffer)? {
        guard length > 0, length <= maxBufferLength, let b = cmv_buffer_create(handle, UInt64(length)) else { return nil }
        return MTLVulkanBuffer(device: self, handle: b, length: length, options: options)
    }

    public func makeBuffer(bytes pointer: UnsafeRawPointer, length: Int, options: MTLResourceOptions) -> (any MTLBuffer)? {
        guard let b = makeBuffer(length: length, options: options) else { return nil }
        b.contents().copyMemory(from: pointer, byteCount: length)
        return b
    }

    /// The VkFormat a Metal pixel format is created with (substituting a supported
    /// depth/stencil format when the exact one is not).
    func vkFormat(for format: MTLPixelFormat, attachment: Bool) -> UInt32? {
        guard var f = MTLVulkan.vkFormat(format) else { return nil }
        if !cmv_device_supports_format(handle, f, attachment) {
            switch format {
            case .depth24Unorm_stencil8: f = 130   // D32_SFLOAT_S8_UINT
            case .depth16Unorm: f = 126            // D32_SFLOAT
            case .stencil8: f = 130
            default: return nil
            }
            guard cmv_device_supports_format(handle, f, attachment) else { return nil }
        }
        return f
    }

    public func makeTexture(descriptor: MTLTextureDescriptor) -> (any MTLTexture)? {
        guard descriptor.width > 0, descriptor.height > 0, descriptor.textureType == .type2D || descriptor.textureType == .type2DMultisample,
              let format = vkFormat(for: descriptor.pixelFormat, attachment: descriptor.usage.contains(.renderTarget)) else { return nil }
        var usage: UInt32 = 0
        if descriptor.usage.contains(.renderTarget) { usage |= UInt32(CMV_TEXTURE_RENDER_TARGET) }
        if descriptor.usage.contains(.shaderRead) || descriptor.usage.isEmpty { usage |= UInt32(CMV_TEXTURE_SHADER_READ) }
        if descriptor.usage.contains(.shaderWrite) { usage |= UInt32(CMV_TEXTURE_SHADER_WRITE) }
        guard let t = cmv_texture_create(handle, UInt32(descriptor.width), UInt32(descriptor.height), UInt32(max(1, descriptor.mipmapLevelCount)), format, usage, UInt32(max(1, descriptor.sampleCount))) else { return nil }
        return MTLVulkanTexture(device: self, handle: t, descriptor: descriptor)
    }

    public func makeSamplerState(descriptor: MTLSamplerDescriptor) -> (any MTLSamplerState)? { MTLVulkanSamplerState(device: self, descriptor: descriptor) }
    public func makeDepthStencilState(descriptor: MTLDepthStencilDescriptor) -> (any MTLDepthStencilState)? { MTLVulkanDepthStencilState(device: self, descriptor: descriptor) }
    public func makeDefaultLibrary() -> (any MTLLibrary)? { nil }

    /// HLSL (or MSL translated to HLSL, ADR-0006) compiled to SPIR-V per entry point when
    /// a pipeline needs it, through dxc or glslangValidator on PATH.
    public func makeLibrary(source: String, options: MTLCompileOptions?) throws -> any MTLLibrary {
        let (functions, translation) = try MTLReferenceLibrary.prepare(source: source, options: options)
        return MTLVulkanLibrary(device: self, source: translation?.hlsl ?? source, functions: functions, translation: translation)
    }

    /// A SPIR-V module; every `OpEntryPoint` becomes a function.
    public func makeLibrary(data: Data) throws -> any MTLLibrary {
        let entries = try MTLVulkanSPIRV.entryPoints(in: data)
        guard !entries.isEmpty else { throw MTLLibraryError(code: .functionNotFound, message: "the SPIR-V module declares no entry points") }
        var modules: [String: (Data, MTLFunctionType)] = [:]
        for (name, type) in entries { modules[name] = (data, type) }
        return MTLVulkanLibrary(device: self, spirv: modules)
    }

    public func makeRenderPipelineState(descriptor: MTLRenderPipelineDescriptor) throws -> any MTLRenderPipelineState {
        guard let vf = descriptor.vertexFunction as? MTLVulkanFunction else { throw MTLLibraryError(code: .functionNotFound, message: "render pipeline needs a Vulkan vertex function") }
        for i in descriptor.colorAttachments.indices where descriptor.colorAttachments[i].pixelFormat == .invalid {
            throw MTLLibraryError(code: .internal, message: "color attachment \(i) has no pixel format")
        }
        let vs = try vf.compiled()
        var fs: OpaquePointer? = nil
        if let ff = descriptor.fragmentFunction as? MTLVulkanFunction { fs = try ff.compiled() }
        var desc = CMVPipelineDesc()
        desc.vertex = vs
        desc.fragment = fs
        var formats = [UInt32](repeating: 0, count: 8)
        var blends = [CMVBlend](repeating: CMVBlend(), count: 8)
        for i in descriptor.colorAttachments.indices where i < 8 {
            let a = descriptor.colorAttachments[i]!
            guard let f = vkFormat(for: a.pixelFormat, attachment: true) else { throw MTLLibraryError(code: .unsupported, message: "color attachment \(i): \(a.pixelFormat) is not a renderable format on \(name)") }
            formats[i] = f
            blends[i] = CMVBlend(enabled: a.isBlendingEnabled,
                                 srcRGB: MTLVulkan.blend(a.sourceRGBBlendFactor), dstRGB: MTLVulkan.blend(a.destinationRGBBlendFactor), opRGB: UInt32(a.rgbBlendOperation.rawValue),
                                 srcAlpha: MTLVulkan.blend(a.sourceAlphaBlendFactor), dstAlpha: MTLVulkan.blend(a.destinationAlphaBlendFactor), opAlpha: UInt32(a.alphaBlendOperation.rawValue),
                                 writeMask: MTLVulkan.writeMask(a.writeMask))
        }
        withUnsafeMutableBytes(of: &desc.colorFormats) { $0.copyBytes(from: formats.withUnsafeBytes { Array($0) }) }
        withUnsafeMutableBytes(of: &desc.blends) { $0.copyBytes(from: blends.withUnsafeBytes { Array($0) }) }
        if descriptor.depthAttachmentPixelFormat != .invalid {
            desc.depthFormat = vkFormat(for: descriptor.depthAttachmentPixelFormat, attachment: true) ?? 0
            if MTLVulkan.hasStencil(descriptor.depthAttachmentPixelFormat) { desc.stencilFormat = desc.depthFormat }
        }
        if descriptor.stencilAttachmentPixelFormat != .invalid {
            desc.stencilFormat = vkFormat(for: descriptor.stencilAttachmentPixelFormat, attachment: true) ?? desc.stencilFormat
        }
        desc.topologyClass = descriptor.inputPrimitiveTopology == .point ? 0 : descriptor.inputPrimitiveTopology == .line ? 1 : 2
        desc.wireframe = false
        desc.alphaToCoverage = descriptor.isAlphaToCoverageEnabled
        desc.alphaToOne = descriptor.isAlphaToOneEnabled
        desc.rasterizationEnabled = descriptor.isRasterizationEnabled
        desc.sampleCount = UInt32(max(1, descriptor.rasterSampleCount))
        var attributes: [CMVVertexAttribute] = []
        var layouts: [CMVVertexLayout] = []
        if let vd = descriptor.vertexDescriptor {
            for i in vd.attributes.indices {
                let a = vd.attributes[i]!
                attributes.append(CMVVertexAttribute(location: UInt32(i), vkFormat: MTLVulkan.vertexFormat(a.format), binding: UInt32(a.bufferIndex), offset: UInt32(a.offset)))
            }
            for i in vd.layouts.indices {
                let l = vd.layouts[i]!
                layouts.append(CMVVertexLayout(binding: UInt32(i), stride: UInt32(l.stride), perInstance: l.stepFunction == .perInstance))
            }
        }
        var error = [CChar](repeating: 0, count: 2048)
        let pipeline: OpaquePointer? = attributes.withUnsafeBufferPointer { ab in
            layouts.withUnsafeBufferPointer { lb in
                desc.attributes = ab.baseAddress
                desc.attributeCount = UInt32(ab.count)
                desc.layouts = lb.baseAddress
                desc.layoutCount = UInt32(lb.count)
                return cmv_pipeline_create(handle, &desc, &error, 2048)
            }
        }
        guard let pipeline else { throw MTLLibraryError(code: .internal, message: String(cString: error)) }
        return MTLVulkanRenderPipelineState(device: self, handle: pipeline, descriptor: descriptor)
    }

    public func makeComputePipelineState(function: any MTLFunction) throws -> any MTLComputePipelineState {
        guard let f = function as? MTLVulkanFunction else { throw MTLLibraryError(code: .functionNotFound, message: "compute pipeline needs a Vulkan kernel function") }
        guard f.functionType == .kernel else { throw MTLLibraryError(code: .internal, message: "'\(f.name)' is not a kernel function") }
        let shader = try f.compiled()
        var error = [CChar](repeating: 0, count: 2048)
        guard let p = cmv_compute_pipeline_create(handle, shader, &error, 2048) else { throw MTLLibraryError(code: .internal, message: String(cString: error)) }
        return MTLVulkanComputePipelineState(device: self, handle: p, function: f)
    }

    public func minimumLinearTextureAlignment(for format: MTLPixelFormat) -> Int { 256 }
    public func minimumTextureBufferAlignment(for format: MTLPixelFormat) -> Int { 256 }
    public func makeEvent() -> (any MTLEvent)? { MTLReferenceEvent(device: self) }
    public func makeSharedEvent() -> (any MTLSharedEvent)? { MTLReferenceEvent(device: self) }
}

// MARK: Enum mapping (VkFormat, VkBlendFactor, ... numeric values)

enum MTLVulkan {
    static func vkFormat(_ f: MTLPixelFormat) -> UInt32? {
        switch f {
        case .invalid: return nil
        case .a8Unorm, .r8Unorm: return 9
        case .r8Unorm_srgb: return 15
        case .r8Snorm: return 10
        case .r8Uint: return 13
        case .r8Sint: return 14
        case .r16Unorm: return 70
        case .r16Snorm: return 71
        case .r16Uint: return 74
        case .r16Sint: return 75
        case .r16Float: return 76
        case .rg8Unorm: return 16
        case .rg8Unorm_srgb: return 22
        case .rg8Snorm: return 17
        case .rg8Uint: return 20
        case .rg8Sint: return 21
        case .r32Uint: return 98
        case .r32Sint: return 99
        case .r32Float: return 100
        case .rg16Unorm: return 77
        case .rg16Snorm: return 78
        case .rg16Uint: return 81
        case .rg16Sint: return 82
        case .rg16Float: return 83
        case .rgba8Unorm: return 37
        case .rgba8Unorm_srgb: return 43
        case .rgba8Snorm: return 38
        case .rgba8Uint: return 41
        case .rgba8Sint: return 42
        case .bgra8Unorm: return 44
        case .bgra8Unorm_srgb: return 50
        case .rgb10a2Unorm: return 64
        case .rgb10a2Uint: return 68
        case .rg11b10Float: return 122
        case .rgb9e5Float: return 123
        case .rg32Uint: return 101
        case .rg32Sint: return 102
        case .rg32Float: return 103
        case .rgba16Unorm: return 91
        case .rgba16Snorm: return 92
        case .rgba16Uint: return 95
        case .rgba16Sint: return 96
        case .rgba16Float: return 97
        case .rgba32Uint: return 107
        case .rgba32Sint: return 108
        case .rgba32Float: return 109
        case .depth16Unorm: return 124
        case .depth32Float: return 126
        case .stencil8: return 127
        case .depth24Unorm_stencil8: return 129
        case .depth32Float_stencil8: return 130
        }
    }

    static func hasStencil(_ f: MTLPixelFormat) -> Bool { f == .stencil8 || f == .depth24Unorm_stencil8 || f == .depth32Float_stencil8 }

    static func vertexFormat(_ f: MTLVertexFormat) -> UInt32 {
        switch f {
        case .float: return 100
        case .float2: return 103
        case .float3: return 106
        case .float4: return 109
        case .half: return 76
        case .half2: return 83
        case .half3: return 90
        case .half4: return 97
        case .int: return 99
        case .int2: return 102
        case .int3: return 105
        case .int4: return 108
        case .uint: return 98
        case .uint2: return 101
        case .uint3: return 104
        case .uint4: return 107
        case .short: return 75
        case .short2: return 82
        case .short3: return 89
        case .short4: return 96
        case .ushort: return 74
        case .ushort2: return 81
        case .ushort3: return 88
        case .ushort4: return 95
        case .shortNormalized: return 71
        case .short2Normalized: return 78
        case .short3Normalized: return 85
        case .short4Normalized: return 92
        case .ushortNormalized: return 70
        case .ushort2Normalized: return 77
        case .ushort3Normalized: return 84
        case .ushort4Normalized: return 91
        case .char: return 14
        case .char2: return 21
        case .char3: return 28
        case .char4: return 42
        case .uchar: return 13
        case .uchar2: return 20
        case .uchar3: return 27
        case .uchar4: return 41
        case .charNormalized: return 10
        case .char2Normalized: return 17
        case .char3Normalized: return 24
        case .char4Normalized: return 38
        case .ucharNormalized: return 9
        case .uchar2Normalized: return 16
        case .uchar3Normalized: return 23
        case .uchar4Normalized: return 37
        case .uchar4Normalized_bgra: return 44
        case .uint1010102Normalized: return 64
        case .int1010102Normalized: return 65
        case .floatRG11B10: return 122
        case .floatRGB9E5: return 123
        case .invalid: return 0
        }
    }

    static func blend(_ f: MTLBlendFactor) -> UInt32 {
        switch f {
        case .zero: return 0
        case .one: return 1
        case .sourceColor: return 2
        case .oneMinusSourceColor: return 3
        case .destinationColor: return 4
        case .oneMinusDestinationColor: return 5
        case .sourceAlpha: return 6
        case .oneMinusSourceAlpha: return 7
        case .destinationAlpha: return 8
        case .oneMinusDestinationAlpha: return 9
        case .blendColor: return 10
        case .oneMinusBlendColor: return 11
        case .blendAlpha: return 12
        case .oneMinusBlendAlpha: return 13
        case .sourceAlphaSaturated: return 14
        case .source1Color: return 15
        case .oneMinusSource1Color: return 16
        case .source1Alpha: return 17
        case .oneMinusSource1Alpha: return 18
        }
    }

    static func writeMask(_ m: MTLColorWriteMask) -> UInt8 {
        var out: UInt8 = 0
        if m.contains(.red) { out |= 1 }
        if m.contains(.green) { out |= 2 }
        if m.contains(.blue) { out |= 4 }
        if m.contains(.alpha) { out |= 8 }
        return out
    }

    /// VkPrimitiveTopology shares Metal's numbering for the five list/strip types.
    static func topology(_ t: MTLPrimitiveType) -> UInt32 { UInt32(t.rawValue) }
    static func filter(_ f: MTLSamplerMinMagFilter) -> UInt32 { f == .linear ? 1 : 0 }
    static func mipMode(_ f: MTLSamplerMipFilter) -> UInt32 { f == .linear ? 1 : 0 }
    static func address(_ a: MTLSamplerAddressMode) -> UInt32 {
        switch a {
        case .repeat: return 0
        case .mirrorRepeat: return 1
        case .clampToEdge: return 2
        case .clampToBorderColor, .clampToZero: return 3
        case .mirrorClampToEdge: return 4
        }
    }
}

// MARK: Resources

final class MTLVulkanBuffer: MTLBuffer, @unchecked Sendable {
    var label: String?
    let device: any MTLDevice
    let handle: OpaquePointer
    let length: Int
    let resourceOptions: MTLResourceOptions
    var cpuCacheMode: MTLCPUCacheMode { .defaultCache }
    var storageMode: MTLStorageMode { .shared }
    var hazardTrackingMode: MTLHazardTrackingMode { .tracked }
    var allocatedSize: Int { length }
    let gpuAddress: UInt64 = 0
    private let mapped: UnsafeMutableRawPointer

    init(device: MTLVulkanDevice, handle: OpaquePointer, length: Int, options: MTLResourceOptions) {
        self.device = device
        self.handle = handle
        self.length = length
        resourceOptions = options
        mapped = cmv_buffer_map(handle)!
        device.allocated(length)
    }

    deinit {
        cmv_buffer_release(handle)
        (device as? MTLVulkanDevice)?.allocated(-length)
    }

    func contents() -> UnsafeMutableRawPointer { mapped }
    func didModifyRange(_ range: Range<Int>) {}
}

final class MTLVulkanTexture: MTLTexture, @unchecked Sendable {
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
    let vkDevice: MTLVulkanDevice

    init(device: MTLVulkanDevice, handle: OpaquePointer, descriptor d: MTLTextureDescriptor) {
        self.device = device
        vkDevice = device
        self.handle = handle
        textureType = d.textureType; pixelFormat = d.pixelFormat
        width = d.width; height = d.height; depth = d.depth
        mipmapLevelCount = max(1, d.mipmapLevelCount); sampleCount = max(1, d.sampleCount); arrayLength = d.arrayLength
        usage = d.usage; resourceOptions = d.resourceOptions
        device.allocated(allocatedSize)
    }

    deinit {
        cmv_texture_release(handle)
        vkDevice.allocated(-allocatedSize)
    }

    func levelSize(_ level: Int) -> (Int, Int) { (max(1, width >> level), max(1, height >> level)) }

    func replace(region: MTLRegion, mipmapLevel level: Int, slice: Int, withBytes pixelBytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int) {
        guard slice == 0, level < mipmapLevelCount else { return }
        let (w, h) = levelSize(level)
        let rw = min(region.size.width, w - region.origin.x), rh = min(region.size.height, h - region.origin.y)
        guard rw > 0, rh > 0 else { return }
        _ = cmv_texture_upload(vkDevice.handle, handle, UInt32(level), UInt32(region.origin.x), UInt32(region.origin.y), UInt32(rw), UInt32(rh), pixelBytes, UInt32(bytesPerRow))
    }

    func getBytes(_ pixelBytes: UnsafeMutableRawPointer, bytesPerRow: Int, bytesPerImage: Int, from region: MTLRegion, mipmapLevel level: Int, slice: Int) {
        guard slice == 0, level < mipmapLevelCount else { return }
        let (w, h) = levelSize(level)
        let rw = min(region.size.width, w - region.origin.x), rh = min(region.size.height, h - region.origin.y)
        guard rw > 0, rh > 0 else { return }
        _ = cmv_texture_read(vkDevice.handle, handle, UInt32(level), UInt32(region.origin.x), UInt32(region.origin.y), UInt32(rw), UInt32(rh), pixelBytes, UInt32(bytesPerRow))
    }

    func makeTextureView(pixelFormat: MTLPixelFormat) -> (any MTLTexture)? { pixelFormat == self.pixelFormat ? self : nil }
}

final class MTLVulkanSamplerState: MTLSamplerState {
    let label: String?
    let device: any MTLDevice
    let handle: OpaquePointer?
    init(device: MTLVulkanDevice, descriptor d: MTLSamplerDescriptor) {
        self.device = device
        label = d.label
        handle = MTLVulkanSamplerState.make(device, minFilter: d.minFilter, magFilter: d.magFilter, mipFilter: d.mipFilter, s: d.sAddressMode, t: d.tAddressMode, r: d.rAddressMode,
                                            compare: d.compareFunction, lodMin: d.lodMinClamp, lodMax: d.lodMaxClamp, anisotropy: d.maxAnisotropy, border: d.borderColor)
    }
    init(device: MTLVulkanDevice, constexpr s: MSLTranslation.ConstexprSampler) {
        self.device = device
        label = s.name
        handle = MTLVulkanSamplerState.make(device, minFilter: s.minFilter, magFilter: s.magFilter, mipFilter: s.mipFilter, s: s.sAddressMode, t: s.tAddressMode, r: s.rAddressMode,
                                            compare: s.compareFunction, lodMin: 0, lodMax: .greatestFiniteMagnitude, anisotropy: 1, border: .transparentBlack)
    }
    static func make(_ device: MTLVulkanDevice, minFilter: MTLSamplerMinMagFilter, magFilter: MTLSamplerMinMagFilter, mipFilter: MTLSamplerMipFilter, s: MTLSamplerAddressMode, t: MTLSamplerAddressMode, r: MTLSamplerAddressMode,
                     compare: MTLCompareFunction, lodMin: Float, lodMax: Float, anisotropy: Int, border: MTLSamplerBorderColor) -> OpaquePointer? {
        cmv_sampler_create(device.handle, MTLVulkan.filter(minFilter), MTLVulkan.filter(magFilter), MTLVulkan.mipMode(mipFilter),
                           MTLVulkan.address(s), MTLVulkan.address(t), MTLVulkan.address(r),
                           compare != .never, UInt32(compare.rawValue), lodMin, mipFilter == .notMipmapped ? 0.25 : lodMax, UInt32(max(1, anisotropy)), UInt32(border.rawValue))
    }
    deinit { cmv_sampler_release(handle) }
}

final class MTLVulkanDepthStencilState: MTLDepthStencilState {
    let label: String?
    let device: any MTLDevice
    let depthWrite: Bool
    let compare: MTLCompareFunction
    let front: MTLStencilDescriptor, back: MTLStencilDescriptor
    let stencilEnabled: Bool
    init(device: any MTLDevice, descriptor d: MTLDepthStencilDescriptor) {
        self.device = device
        label = d.label
        depthWrite = d.isDepthWriteEnabled
        compare = d.depthCompareFunction
        func copy(_ s: MTLStencilDescriptor) -> MTLStencilDescriptor {
            let c = MTLStencilDescriptor()
            c.stencilCompareFunction = s.stencilCompareFunction; c.stencilFailureOperation = s.stencilFailureOperation
            c.depthFailureOperation = s.depthFailureOperation; c.depthStencilPassOperation = s.depthStencilPassOperation
            c.readMask = s.readMask; c.writeMask = s.writeMask
            return c
        }
        front = copy(d.frontFaceStencil)
        back = copy(d.backFaceStencil)
        func active(_ s: MTLStencilDescriptor) -> Bool { s.stencilCompareFunction != .always || s.stencilFailureOperation != .keep || s.depthFailureOperation != .keep || s.depthStencilPassOperation != .keep }
        stencilEnabled = active(front) || active(back)
    }
}

// MARK: Shaders

/// Entry points of a SPIR-V module (`OpEntryPoint`).
enum MTLVulkanSPIRV {
    static func entryPoints(in data: Data) throws -> [(String, MTLFunctionType)] {
        guard data.count >= 20, data.count % 4 == 0 else { throw MTLLibraryError(code: .compileFailure, message: "not a SPIR-V module (\(data.count) bytes)") }
        let words: [UInt32] = data.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
        guard words[0] == 0x0723_0203 else { throw MTLLibraryError(code: .compileFailure, message: "not a SPIR-V module (bad magic number)") }
        var out: [(String, MTLFunctionType)] = []
        var i = 5
        while i < words.count {
            let count = Int(words[i] >> 16), opcode = words[i] & 0xFFFF
            guard count > 0 else { break }
            if opcode == 15, count >= 4 {   // OpEntryPoint model id name...
                let model = words[i + 1]
                var bytes: [UInt8] = []
                var j = i + 3
                scan: while j < i + count {
                    let w = words[j]
                    for shift in stride(from: 0, to: 32, by: 8) {
                        let b = UInt8((w >> UInt32(shift)) & 0xFF)
                        if b == 0 { break scan }
                        bytes.append(b)
                    }
                    j += 1
                }
                let name = String(decoding: bytes, as: UTF8.self)
                let type: MTLFunctionType? = model == 0 ? .vertex : model == 4 ? .fragment : model == 5 ? .kernel : nil
                if let type, !name.isEmpty { out.append((name, type)) }
            }
            i += count
        }
        return out
    }
}

/// HLSL → SPIR-V through a compiler on PATH: dxc when present, glslangValidator otherwise.
/// Register shifts implement the binding model of ADR-0011.
enum MTLVulkanShaderCompiler {
    nonisolated(unsafe) static var cachedTool: (String, String)?? = nil

    /// ("dxc", path) or ("glslang", path), nil when neither is installed.
    static func tool() -> (String, String)? {
        if let c = cachedTool { return c }
        var found: (String, String)? = nil
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin"
        let dirs = path.split(separator: ":").map(String.init) + ["/usr/local/bin", "/usr/bin"]
        search: for (kind, names) in [("dxc", ["dxc"]), ("glslang", ["glslangValidator", "glslang"])] {
            for name in names {
                for dir in dirs where FileManager.default.isExecutableFile(atPath: "\(dir)/\(name)") {
                    found = (kind, "\(dir)/\(name)")
                    break search
                }
            }
        }
        cachedTool = .some(found)
        return found
    }

    static func compile(hlsl: String, entryPoint: String, type: MTLFunctionType, device: String) throws -> Data {
        guard let (kind, path) = tool() else {
            throw MTLLibraryError(code: .unsupported, message: "no SPIR-V compiler for HLSL on PATH: install dxc or glslang (glslangValidator), or build the library from SPIR-V with makeLibrary(data:) on \(device)")
        }
        let half = type == .fragment ? 32 : 0
        let set1 = type == .fragment ? 8 : 0
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("appkitwin-spirv-\(getpid())-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("shader.hlsl"), output = dir.appendingPathComponent("shader.spv")
        try hlsl.write(to: input, atomically: true, encoding: .utf8)
        var arguments: [String]
        if kind == "dxc" {
            let profile = type == .vertex ? "vs_6_0" : type == .fragment ? "ps_6_0" : "cs_6_0"
            arguments = ["-spirv", "-fspv-target-env=vulkan1.3", "-T", profile, "-E", entryPoint, "-fvk-use-dx-layout",
                         "-fvk-b-shift", "\(half)", "0", "-fvk-t-shift", "\(half + 8)", "0", "-fvk-s-shift", "\(half + 16)", "0", "-fvk-u-shift", "\(half + 24)", "0",
                         "-fvk-t-shift", "\(set1)", "1", "-fvk-u-shift", "\(set1)", "1",
                         "-Fo", output.path, input.path]
        } else {
            let stage = type == .vertex ? "vert" : type == .fragment ? "frag" : "comp"
            arguments = ["-D", "-V", "--target-env", "vulkan1.3", "-S", stage, "-e", entryPoint, "--hlsl-offsets", "--hlsl-iomap", "--auto-map-bindings", "--auto-map-locations",
                         // Per-set shifts: `[num set]...` pairs; glslang files StructuredBuffer under
                         // textures and RWStructuredBuffer under UAVs, so `space1` lands in set 1 at slot + set1.
                         "--shift-cbuffer-binding", "\(half)", "--shift-texture-binding", "\(half + 8)", "0", "\(set1)", "1", "--shift-sampler-binding", "\(half + 16)",
                         "--shift-image-binding", "\(half + 24)", "--shift-uav-binding", "\(half + 24)", "0", "\(set1)", "1", "--shift-ssbo-binding", "0", "0", "\(set1)", "1",
                         "-o", output.path, input.path]
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { throw MTLLibraryError(code: .internal, message: "could not run \(path): \(error)") }
        let log = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let data = try? Data(contentsOf: output), !data.isEmpty else {
            let text = String(decoding: log, as: UTF8.self).replacingOccurrences(of: input.path, with: "shader.hlsl").trimmingCharacters(in: .whitespacesAndNewlines)
            throw MTLLibraryError(code: .compileFailure, message: "\(kind) failed for '\(entryPoint)': \(text)")
        }
        return data
    }
}

public final class MTLVulkanFunction: MTLFunction {
    public var label: String?
    public let device: any MTLDevice
    public let functionType: MTLFunctionType
    public let name: String
    private let source: String?
    private let spirv: Data?
    /// The HLSL entry point: the MSL name unless it collided with an HLSL keyword.
    let entryPoint: String
    /// Translation details when the library came from MSL.
    let translated: MSLTranslation.Function?
    private var shader: OpaquePointer?
    /// The SPIR-V the function was built from (after compilation when it came from source).
    public private(set) var spirvData: Data?

    init(device: any MTLDevice, name: String, type: MTLFunctionType, source: String?, spirv: Data?, translated: MSLTranslation.Function? = nil) {
        self.device = device; self.name = name; functionType = type; self.source = source; self.spirv = spirv
        self.translated = translated
        entryPoint = translated?.entryPoint ?? name
        spirvData = spirv
    }

    deinit { cmv_shader_release(shader) }

    func compiled() throws -> OpaquePointer {
        if let shader { return shader }
        guard let dev = device as? MTLVulkanDevice else { throw MTLLibraryError(code: .internal, message: "function belongs to another device") }
        var data: Data
        var entry = entryPoint
        if let spirv {
            data = spirv
        } else if let source {
            data = try MTLVulkanShaderCompiler.compile(hlsl: source, entryPoint: entryPoint, type: functionType, device: dev.name)
            // The compiler may rename the entry point (glslang emits the -e name; dxc keeps it).
            if let first = try? MTLVulkanSPIRV.entryPoints(in: data).first { entry = first.0 }
            spirvData = data
        } else {
            throw MTLLibraryError(code: .functionNotFound, message: "'\(name)' has neither source nor SPIR-V")
        }
        let stage: UInt32 = functionType == .vertex ? 1 : functionType == .fragment ? 16 : 32
        var error = [CChar](repeating: 0, count: 1024)
        let h: OpaquePointer? = data.withUnsafeBytes { cmv_shader_from_spirv(dev.handle, $0.baseAddress, UInt32($0.count), entry, stage, &error, 1024) }
        guard let h else { throw MTLLibraryError(code: .compileFailure, message: "'\(name)': \(String(cString: error))") }
        shader = h
        return h
    }
}

public final class MTLVulkanLibrary: MTLLibrary {
    public var label: String?
    public let device: any MTLDevice
    private let source: String?
    private let spirv: [String: (Data, MTLFunctionType)]
    private let functions: [(String, MTLFunctionType)]
    /// The MSL → HLSL translation when the source was MSL.
    public let translation: MSLTranslation?
    /// The HLSL that is compiled to SPIR-V: the source itself, or the translation of MSL.
    public var hlslSource: String? { source }
    public var functionNames: [String] { functions.map(\.0) }

    init(device: any MTLDevice, source: String, functions: [(String, MTLFunctionType)], translation: MSLTranslation? = nil) {
        self.device = device; self.source = source; self.functions = functions; spirv = [:]; self.translation = translation
    }

    /// A library of SPIR-V modules keyed by function name (each module's entry point of
    /// that name, or its only entry point when the names differ).
    public init(device: any MTLDevice, spirv: [String: (Data, MTLFunctionType)]) {
        self.device = device; source = nil; self.spirv = spirv; translation = nil
        functions = spirv.keys.sorted().map { ($0, spirv[$0]!.1) }
    }

    public func makeFunction(name: String) -> (any MTLFunction)? {
        guard let f = functions.first(where: { $0.0 == name }) else { return nil }
        return MTLVulkanFunction(device: device, name: name, type: f.1, source: source, spirv: spirv[name]?.0, translated: translation?.function(named: name))
    }
}

final class MTLVulkanRenderPipelineState: MTLRenderPipelineState {
    let label: String?
    let device: any MTLDevice
    let handle: OpaquePointer
    /// `constexpr sampler`s of translated MSL functions, bound when the pipeline is set.
    let constexprSamplers: [(stage: UInt32, slot: Int, sampler: MTLVulkanSamplerState)]
    init(device: MTLVulkanDevice, handle: OpaquePointer, descriptor: MTLRenderPipelineDescriptor) {
        self.device = device
        self.handle = handle
        label = descriptor.label
        var samplers: [(stage: UInt32, slot: Int, sampler: MTLVulkanSamplerState)] = []
        for (stage, function) in [(UInt32(0), descriptor.vertexFunction), (UInt32(1), descriptor.fragmentFunction)] {
            guard let f = function as? MTLVulkanFunction, let translated = f.translated else { continue }
            for s in translated.constexprSamplers { samplers.append((stage, s.slot, MTLVulkanSamplerState(device: device, constexpr: s))) }
        }
        constexprSamplers = samplers
    }
    deinit { cmv_pipeline_release(handle) }
}

final class MTLVulkanComputePipelineState: MTLComputePipelineState {
    let label: String?
    let device: any MTLDevice
    let handle: OpaquePointer
    let maxTotalThreadsPerThreadgroup: Int
    let threadExecutionWidth: Int
    let constexprSamplers: [(slot: Int, sampler: MTLVulkanSamplerState)]
    init(device: MTLVulkanDevice, handle: OpaquePointer, function: MTLVulkanFunction) {
        self.device = device
        self.handle = handle
        label = function.label ?? function.name
        maxTotalThreadsPerThreadgroup = device.maxComputeInvocations
        threadExecutionWidth = device.subgroupSize
        constexprSamplers = (function.translated?.constexprSamplers ?? []).map { ($0.slot, MTLVulkanSamplerState(device: device, constexpr: $0)) }
    }
    deinit { cmv_pipeline_release(handle) }
}

// MARK: Commands

final class MTLVulkanCommandQueue: MTLCommandQueue {
    var label: String?
    let device: any MTLDevice
    let handle: OpaquePointer
    init(device: MTLVulkanDevice, handle: OpaquePointer) {
        self.device = device
        self.handle = handle
    }
    deinit { cmv_queue_release(handle) }
    func makeCommandBuffer() -> (any MTLCommandBuffer)? { MTLVulkanCommandBuffer(queue: self) }
    func makeCommandBufferWithUnretainedReferences() -> (any MTLCommandBuffer)? { makeCommandBuffer() }
}

final class MTLVulkanCommandBuffer: MTLCommandBuffer {
    let device: any MTLDevice
    let commandQueue: any MTLCommandQueue
    var label: String?
    private(set) var status: MTLCommandBufferStatus = .notEnqueued
    private(set) var error: (any Error)?
    private var work: [(OpaquePointer) -> Void] = []
    /// Objects the recorded work refers to (kept alive until completion).
    private var retained: [AnyObject] = []
    private var scheduledHandlers: [(any MTLCommandBuffer) -> Void] = []
    private var completedHandlers: [(any MTLCommandBuffer) -> Void] = []
    private var drawables: [any MTLDrawable] = []
    private var fenceValue: UInt64 = 0

    init(queue: MTLVulkanCommandQueue) { device = queue.device; commandQueue = queue }

    func record(_ block: @escaping (OpaquePointer) -> Void) { work.append(block) }
    func retain(_ object: AnyObject?) { if let object { retained.append(object) } }

    func enqueue() { if status == .notEnqueued { status = .enqueued } }

    func commit() {
        guard status.rawValue < MTLCommandBufferStatus.committed.rawValue else { return }
        status = .committed
        guard let vk = device as? MTLVulkanDevice, let q = (commandQueue as? MTLVulkanCommandQueue)?.handle, let list = cmv_commandlist_create(vk.handle) else {
            status = .error
            error = MTLCommandBufferError.internal
            for h in completedHandlers { h(self) }
            return
        }
        cmv_commandlist_reset(list)
        for w in work { w(list) }
        work.removeAll()
        status = .scheduled
        for h in scheduledHandlers { h(self) }
        fenceValue = cmv_commandlist_execute(list, q)
        cmv_queue_wait(q, fenceValue)
        cmv_commandlist_release(list)
        retained.removeAll()
        if cmv_device_lost(vk.handle) || fenceValue == 0 {
            status = .error
            error = cmv_device_lost(vk.handle) ? MTLCommandBufferError.deviceRemoved : MTLCommandBufferError.internal
        } else {
            for d in drawables { d.present() }
            status = .completed
        }
        drawables.removeAll()
        for h in completedHandlers { h(self) }
    }

    func addScheduledHandler(_ block: @escaping (any MTLCommandBuffer) -> Void) { scheduledHandlers.append(block) }
    func addCompletedHandler(_ block: @escaping (any MTLCommandBuffer) -> Void) { completedHandlers.append(block) }
    func present(_ drawable: any MTLDrawable) { drawables.append(drawable) }
    func waitUntilScheduled() {}
    func waitUntilCompleted() { if status.rawValue < MTLCommandBufferStatus.completed.rawValue { commit() } }

    func makeRenderCommandEncoder(descriptor renderPassDescriptor: MTLRenderPassDescriptor) -> (any MTLRenderCommandEncoder)? {
        let pass = renderPassDescriptor.copy() as! MTLRenderPassDescriptor
        retain(pass)
        record { list in
            var colors: [OpaquePointer?] = []
            var loads: [UInt32] = [], stores: [UInt32] = []
            var clears: [Float] = []
            for i in pass.colorAttachments.indices {
                let a = pass.colorAttachments[i]!
                guard let t = a.texture as? MTLVulkanTexture else { continue }
                colors.append(t.handle)
                loads.append(UInt32(a.loadAction.rawValue))
                stores.append(UInt32(a.storeAction.rawValue))
                clears += [Float(a.clearColor.red), Float(a.clearColor.green), Float(a.clearColor.blue), Float(a.clearColor.alpha)]
            }
            let depthTexture = pass.depthAttachment.texture as? MTLVulkanTexture
            var stencilTexture = pass.stencilAttachment.texture as? MTLVulkanTexture
            var stencilLoad = pass.stencilAttachment.loadAction, stencilStore = pass.stencilAttachment.storeAction
            if stencilTexture == nil, let d = depthTexture, MTLVulkan.hasStencil(d.pixelFormat) {
                stencilTexture = d
                stencilLoad = pass.depthAttachment.loadAction
                stencilStore = pass.depthAttachment.storeAction
            }
            colors.withUnsafeMutableBufferPointer { cb in
                cmv_commandlist_begin_render_pass(list, cb.baseAddress, loads, stores, clears, UInt32(cb.count),
                                                  depthTexture?.handle, UInt32(pass.depthAttachment.loadAction.rawValue), UInt32(pass.depthAttachment.storeAction.rawValue), Float(pass.depthAttachment.clearDepth),
                                                  stencilTexture?.handle, UInt32(stencilLoad.rawValue), UInt32(stencilStore.rawValue), pass.stencilAttachment.clearStencil)
            }
        }
        return MTLVulkanRenderCommandEncoder(buffer: self)
    }

    func makeBlitCommandEncoder() -> (any MTLBlitCommandEncoder)? { MTLVulkanBlitCommandEncoder(buffer: self) }
    func makeComputeCommandEncoder() -> (any MTLComputeCommandEncoder)? {
        record { cmv_commandlist_clear_bindings($0) }
        return MTLVulkanComputeCommandEncoder(buffer: self)
    }
}

class MTLVulkanEncoder: MTLCommandEncoder {
    let buffer: MTLVulkanCommandBuffer
    var device: any MTLDevice { buffer.device }
    var label: String?
    init(buffer: MTLVulkanCommandBuffer) { self.buffer = buffer }
    func endEncoding() {}
    func insertDebugSignpost(_ string: String) {}
    func pushDebugGroup(_ string: String) {}
    func popDebugGroup() {}

    /// `setVertexBytes`/`setBytes`: a fresh buffer the command buffer keeps alive.
    func temporaryBuffer(_ bytes: UnsafeRawPointer, length: Int) -> MTLVulkanBuffer? {
        guard let b = device.makeBuffer(bytes: bytes, length: max(16, length), options: []) as? MTLVulkanBuffer else { return nil }
        buffer.retain(b)
        return b
    }
}

final class MTLVulkanRenderCommandEncoder: MTLVulkanEncoder, MTLRenderCommandEncoder {
    override func endEncoding() { buffer.record { cmv_commandlist_end_render_pass($0) } }

    func setRenderPipelineState(_ pipelineState: any MTLRenderPipelineState) {
        guard let p = pipelineState as? MTLVulkanRenderPipelineState else { return }
        buffer.retain(p)
        buffer.record { cmv_commandlist_set_pipeline($0, p.handle) }
        for s in p.constexprSamplers {
            buffer.record { cmv_commandlist_set_sampler($0, s.stage, UInt32(s.slot), s.sampler.handle) }
        }
    }
    func setViewport(_ v: MTLViewport) { buffer.record { cmv_commandlist_set_viewport($0, Float(v.originX), Float(v.originY), Float(v.width), Float(v.height), Float(v.znear), Float(v.zfar)) } }
    func setScissorRect(_ r: MTLScissorRect) { buffer.record { cmv_commandlist_set_scissor($0, Int32(r.x), Int32(r.y), Int32(r.width), Int32(r.height)) } }
    func setFrontFacing(_ w: MTLWinding) { buffer.record { cmv_commandlist_set_front_face($0, w == .counterClockwise ? 0 : 1) } }
    func setCullMode(_ c: MTLCullMode) { buffer.record { cmv_commandlist_set_cull_mode($0, UInt32(c.rawValue)) } }
    func setTriangleFillMode(_ fillMode: MTLTriangleFillMode) {}
    func setDepthStencilState(_ state: (any MTLDepthStencilState)?) {
        guard let s = state as? MTLVulkanDepthStencilState else {
            buffer.record { cmv_commandlist_set_depth_state($0, false, false, 7); cmv_commandlist_set_stencil_state($0, false, 0, 0, 0, 7, 0xFFFF_FFFF, 0xFFFF_FFFF, 0, 0, 0, 7, 0xFFFF_FFFF, 0xFFFF_FFFF) }
            return
        }
        buffer.retain(s)
        buffer.record { list in
            cmv_commandlist_set_depth_state(list, s.compare != .always || s.depthWrite, s.depthWrite, UInt32(s.compare.rawValue))
            let f = s.front, b = s.back
            cmv_commandlist_set_stencil_state(list, s.stencilEnabled,
                                              UInt32(f.stencilFailureOperation.rawValue), UInt32(f.depthStencilPassOperation.rawValue), UInt32(f.depthFailureOperation.rawValue), UInt32(f.stencilCompareFunction.rawValue), f.readMask, f.writeMask,
                                              UInt32(b.stencilFailureOperation.rawValue), UInt32(b.depthStencilPassOperation.rawValue), UInt32(b.depthFailureOperation.rawValue), UInt32(b.stencilCompareFunction.rawValue), b.readMask, b.writeMask)
        }
    }
    func setBlendColor(red: Float, green: Float, blue: Float, alpha: Float) { buffer.record { cmv_commandlist_set_blend_constants($0, red, green, blue, alpha) } }
    func setStencilReferenceValue(_ referenceValue: UInt32) { buffer.record { cmv_commandlist_set_stencil_reference($0, referenceValue) } }

    func setVertexBuffer(_ b: (any MTLBuffer)?, offset: Int, index: Int) {
        let vb = b as? MTLVulkanBuffer
        buffer.retain(vb)
        buffer.record { list in
            cmv_commandlist_set_vertex_buffer(list, UInt32(index), vb?.handle, UInt64(offset))
            cmv_commandlist_set_shader_buffer(list, 0, UInt32(index), vb?.handle, UInt64(offset))
        }
    }
    func setVertexBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int) {
        guard let b = temporaryBuffer(bytes, length: length) else { return }
        setVertexBuffer(b, offset: 0, index: index)
    }
    func setVertexTexture(_ t: (any MTLTexture)?, index: Int) { let h = (t as? MTLVulkanTexture)?.handle; buffer.retain(t as AnyObject?); buffer.record { cmv_commandlist_set_shader_texture($0, 0, UInt32(index), h) } }
    func setVertexSamplerState(_ s: (any MTLSamplerState)?, index: Int) { let h = (s as? MTLVulkanSamplerState)?.handle; buffer.retain(s as AnyObject?); buffer.record { cmv_commandlist_set_sampler($0, 0, UInt32(index), h) } }
    func setFragmentBuffer(_ b: (any MTLBuffer)?, offset: Int, index: Int) {
        let h = (b as? MTLVulkanBuffer)?.handle
        buffer.retain(b as AnyObject?)
        buffer.record { cmv_commandlist_set_shader_buffer($0, 1, UInt32(index), h, UInt64(offset)) }
    }
    func setFragmentBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int) {
        guard let b = temporaryBuffer(bytes, length: length) else { return }
        setFragmentBuffer(b, offset: 0, index: index)
    }
    func setFragmentTexture(_ t: (any MTLTexture)?, index: Int) { let h = (t as? MTLVulkanTexture)?.handle; buffer.retain(t as AnyObject?); buffer.record { cmv_commandlist_set_shader_texture($0, 1, UInt32(index), h) } }
    func setFragmentSamplerState(_ s: (any MTLSamplerState)?, index: Int) { let h = (s as? MTLVulkanSamplerState)?.handle; buffer.retain(s as AnyObject?); buffer.record { cmv_commandlist_set_sampler($0, 1, UInt32(index), h) } }
    func drawPrimitives(type: MTLPrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int) {
        buffer.record { cmv_commandlist_draw($0, MTLVulkan.topology(type), UInt32(vertexStart), UInt32(vertexCount), UInt32(instanceCount)) }
    }
    func drawIndexedPrimitives(type: MTLPrimitiveType, indexCount: Int, indexType: MTLIndexType, indexBuffer: any MTLBuffer, indexBufferOffset: Int, instanceCount: Int) {
        guard let ib = indexBuffer as? MTLVulkanBuffer else { return }
        buffer.retain(ib)
        buffer.record { cmv_commandlist_draw_indexed($0, MTLVulkan.topology(type), UInt32(indexCount), indexType == .uint32, ib.handle, UInt64(indexBufferOffset), UInt32(instanceCount)) }
    }
}

final class MTLVulkanBlitCommandEncoder: MTLVulkanEncoder, MTLBlitCommandEncoder {
    func copy(from s: any MTLBuffer, sourceOffset: Int, to d: any MTLBuffer, destinationOffset: Int, size: Int) {
        guard let s = s as? MTLVulkanBuffer, let d = d as? MTLVulkanBuffer else { return }
        buffer.retain(s); buffer.retain(d)
        buffer.record { cmv_commandlist_copy_buffer($0, s.handle, UInt64(sourceOffset), d.handle, UInt64(destinationOffset), UInt64(size)) }
    }
    func copy(from s: any MTLTexture, to d: any MTLTexture) {
        let w = min(s.width, d.width), h = min(s.height, d.height)
        copy(from: s, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: w, height: h, depth: 1), to: d, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
    }
    func copy(from sourceTexture: any MTLTexture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: MTLOrigin, sourceSize: MTLSize, to destinationTexture: any MTLTexture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: MTLOrigin) {
        guard let s = sourceTexture as? MTLVulkanTexture, let d = destinationTexture as? MTLVulkanTexture else { return }
        buffer.retain(s); buffer.retain(d)
        buffer.record { cmv_commandlist_copy_texture($0, s.handle, UInt32(sourceLevel), UInt32(sourceOrigin.x), UInt32(sourceOrigin.y), d.handle, UInt32(destinationLevel), UInt32(destinationOrigin.x), UInt32(destinationOrigin.y), UInt32(sourceSize.width), UInt32(sourceSize.height)) }
    }
    func copy(from sourceBuffer: any MTLBuffer, sourceOffset: Int, sourceBytesPerRow: Int, sourceBytesPerImage: Int, sourceSize: MTLSize, to destinationTexture: any MTLTexture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: MTLOrigin) {
        guard let s = sourceBuffer as? MTLVulkanBuffer, let d = destinationTexture as? MTLVulkanTexture else { return }
        buffer.retain(s); buffer.retain(d)
        buffer.record { cmv_commandlist_copy_buffer_to_texture($0, s.handle, UInt64(sourceOffset), UInt32(sourceBytesPerRow), d.handle, UInt32(destinationLevel), UInt32(destinationOrigin.x), UInt32(destinationOrigin.y), UInt32(sourceSize.width), UInt32(sourceSize.height)) }
    }
    func copy(from sourceTexture: any MTLTexture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: MTLOrigin, sourceSize: MTLSize, to destinationBuffer: any MTLBuffer, destinationOffset: Int, destinationBytesPerRow: Int, destinationBytesPerImage: Int) {
        guard let s = sourceTexture as? MTLVulkanTexture, let d = destinationBuffer as? MTLVulkanBuffer else { return }
        buffer.retain(s); buffer.retain(d)
        let bpp = s.pixelFormat.bytesPerPixel
        if destinationBytesPerRow % max(1, bpp) != 0 || destinationOffset % 4 != 0 || destinationOffset % max(1, bpp) != 0 {
            // Vulkan needs aligned rows; read back on the CPU instead (the buffer is host-visible).
            buffer.record { _ in
                s.getBytes(d.contents().advanced(by: destinationOffset), bytesPerRow: destinationBytesPerRow, from: MTLRegion(origin: sourceOrigin, size: sourceSize), mipmapLevel: sourceLevel)
            }
            return
        }
        buffer.record { cmv_commandlist_copy_texture_to_buffer($0, s.handle, UInt32(sourceLevel), UInt32(sourceOrigin.x), UInt32(sourceOrigin.y), UInt32(sourceSize.width), UInt32(sourceSize.height), d.handle, UInt64(destinationOffset), UInt32(destinationBytesPerRow)) }
    }
    func fill(buffer target: any MTLBuffer, range: Range<Int>, value: UInt8) {
        guard let t = target as? MTLVulkanBuffer else { return }
        buffer.retain(t)
        let r = range.clamped(to: 0..<target.length)
        buffer.record { cmv_commandlist_fill_buffer($0, t.handle, UInt64(r.lowerBound), UInt64(r.count), value) }
    }
    func generateMipmaps(for texture: any MTLTexture) {
        guard let t = texture as? MTLVulkanTexture else { return }
        buffer.retain(t)
        buffer.record { cmv_commandlist_generate_mipmaps($0, t.handle) }
    }
    func synchronize(resource: any MTLResource) {}
}

final class MTLVulkanComputeCommandEncoder: MTLVulkanEncoder, MTLComputeCommandEncoder {
    func setComputePipelineState(_ state: any MTLComputePipelineState) {
        guard let p = state as? MTLVulkanComputePipelineState else { return }
        buffer.retain(p)
        buffer.record { cmv_commandlist_set_pipeline($0, p.handle) }
        for s in p.constexprSamplers { buffer.record { cmv_commandlist_set_sampler($0, 0, UInt32(s.slot), s.sampler.handle) } }
    }
    func setBuffer(_ b: (any MTLBuffer)?, offset: Int, index: Int) {
        let h = (b as? MTLVulkanBuffer)?.handle
        buffer.retain(b as AnyObject?)
        buffer.record { cmv_commandlist_set_shader_buffer($0, 0, UInt32(index), h, UInt64(offset)) }
    }
    func setBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int) {
        guard let b = temporaryBuffer(bytes, length: length) else { return }
        setBuffer(b, offset: 0, index: index)
    }
    func setTexture(_ t: (any MTLTexture)?, index: Int) { let h = (t as? MTLVulkanTexture)?.handle; buffer.retain(t as AnyObject?); buffer.record { cmv_commandlist_set_shader_texture($0, 0, UInt32(index), h) } }
    func setSamplerState(_ s: (any MTLSamplerState)?, index: Int) { let h = (s as? MTLVulkanSamplerState)?.handle; buffer.retain(s as AnyObject?); buffer.record { cmv_commandlist_set_sampler($0, 0, UInt32(index), h) } }
    func dispatchThreadgroups(_ g: MTLSize, threadsPerThreadgroup: MTLSize) {
        buffer.record { cmv_commandlist_dispatch($0, UInt32(max(1, g.width)), UInt32(max(1, g.height)), UInt32(max(1, g.depth))) }
    }
    /// The SPIR-V module fixes the workgroup size; partial groups at the grid's edge run in full.
    func dispatchThreads(_ t: MTLSize, threadsPerThreadgroup: MTLSize) {
        let g = MTLSize(width: (t.width + max(1, threadsPerThreadgroup.width) - 1) / max(1, threadsPerThreadgroup.width),
                        height: (t.height + max(1, threadsPerThreadgroup.height) - 1) / max(1, threadsPerThreadgroup.height),
                        depth: (t.depth + max(1, threadsPerThreadgroup.depth) - 1) / max(1, threadsPerThreadgroup.depth))
        dispatchThreadgroups(g, threadsPerThreadgroup: threadsPerThreadgroup)
    }
}
#endif
