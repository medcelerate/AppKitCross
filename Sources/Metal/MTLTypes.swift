// Metal value types and enumerations (the subset the reference and D3D12 devices use).

import Foundation

public struct MTLOrigin: Equatable, Sendable {
    public var x: Int, y: Int, z: Int
    public init(x: Int = 0, y: Int = 0, z: Int = 0) { self.x = x; self.y = y; self.z = z }
}
public func MTLOriginMake(_ x: Int, _ y: Int, _ z: Int) -> MTLOrigin { MTLOrigin(x: x, y: y, z: z) }

public struct MTLSize: Equatable, Sendable {
    public var width: Int, height: Int, depth: Int
    public init(width: Int = 0, height: Int = 0, depth: Int = 0) { self.width = width; self.height = height; self.depth = depth }
}
public func MTLSizeMake(_ w: Int, _ h: Int, _ d: Int) -> MTLSize { MTLSize(width: w, height: h, depth: d) }

public struct MTLRegion: Equatable, Sendable {
    public var origin: MTLOrigin, size: MTLSize
    public init(origin: MTLOrigin = MTLOrigin(), size: MTLSize = MTLSize()) { self.origin = origin; self.size = size }
}
public func MTLRegionMake2D(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> MTLRegion { MTLRegion(origin: MTLOrigin(x: x, y: y), size: MTLSize(width: w, height: h, depth: 1)) }
public func MTLRegionMake3D(_ x: Int, _ y: Int, _ z: Int, _ w: Int, _ h: Int, _ d: Int) -> MTLRegion { MTLRegion(origin: MTLOrigin(x: x, y: y, z: z), size: MTLSize(width: w, height: h, depth: d)) }

public struct MTLClearColor: Equatable, Sendable {
    public var red: Double, green: Double, blue: Double, alpha: Double
    public init(red: Double = 0, green: Double = 0, blue: Double = 0, alpha: Double = 1) { self.red = red; self.green = green; self.blue = blue; self.alpha = alpha }
}
public func MTLClearColorMake(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> MTLClearColor { MTLClearColor(red: r, green: g, blue: b, alpha: a) }

public struct MTLViewport: Equatable, Sendable {
    public var originX: Double, originY: Double, width: Double, height: Double, znear: Double, zfar: Double
    public init(originX: Double = 0, originY: Double = 0, width: Double = 0, height: Double = 0, znear: Double = 0, zfar: Double = 1) {
        self.originX = originX; self.originY = originY; self.width = width; self.height = height; self.znear = znear; self.zfar = zfar
    }
}

public struct MTLScissorRect: Equatable, Sendable {
    public var x: Int, y: Int, width: Int, height: Int
    public init(x: Int = 0, y: Int = 0, width: Int = 0, height: Int = 0) { self.x = x; self.y = y; self.width = width; self.height = height }
}

public enum MTLPixelFormat: UInt, Sendable {
    case invalid = 0
    case a8Unorm = 1, r8Unorm = 10, r8Unorm_srgb = 11, r8Snorm = 12, r8Uint = 13, r8Sint = 14
    case r16Unorm = 20, r16Snorm = 22, r16Uint = 23, r16Sint = 24, r16Float = 25
    case rg8Unorm = 30, rg8Unorm_srgb = 31, rg8Snorm = 32, rg8Uint = 33, rg8Sint = 34
    case r32Uint = 53, r32Sint = 54, r32Float = 55
    case rg16Unorm = 60, rg16Snorm = 62, rg16Uint = 63, rg16Sint = 64, rg16Float = 65
    case rgba8Unorm = 70, rgba8Unorm_srgb = 71, rgba8Snorm = 72, rgba8Uint = 73, rgba8Sint = 74
    case bgra8Unorm = 80, bgra8Unorm_srgb = 81
    case rgb10a2Unorm = 90, rgb10a2Uint = 91, rg11b10Float = 92, rgb9e5Float = 93
    case rg32Uint = 103, rg32Sint = 104, rg32Float = 105
    case rgba16Unorm = 110, rgba16Snorm = 112, rgba16Uint = 113, rgba16Sint = 114, rgba16Float = 115
    case rgba32Uint = 123, rgba32Sint = 124, rgba32Float = 125
    case depth16Unorm = 250, depth32Float = 252, stencil8 = 253, depth24Unorm_stencil8 = 255, depth32Float_stencil8 = 260

    /// Bytes per pixel for uncompressed formats (0 when unknown).
    public var bytesPerPixel: Int {
        switch self {
        case .invalid: return 0
        case .a8Unorm, .r8Unorm, .r8Unorm_srgb, .r8Snorm, .r8Uint, .r8Sint, .stencil8: return 1
        case .r16Unorm, .r16Snorm, .r16Uint, .r16Sint, .r16Float, .rg8Unorm, .rg8Unorm_srgb, .rg8Snorm, .rg8Uint, .rg8Sint, .depth16Unorm: return 2
        case .r32Uint, .r32Sint, .r32Float, .rg16Unorm, .rg16Snorm, .rg16Uint, .rg16Sint, .rg16Float,
             .rgba8Unorm, .rgba8Unorm_srgb, .rgba8Snorm, .rgba8Uint, .rgba8Sint, .bgra8Unorm, .bgra8Unorm_srgb,
             .rgb10a2Unorm, .rgb10a2Uint, .rg11b10Float, .rgb9e5Float, .depth32Float, .depth24Unorm_stencil8: return 4
        case .rg32Uint, .rg32Sint, .rg32Float, .rgba16Unorm, .rgba16Snorm, .rgba16Uint, .rgba16Sint, .rgba16Float, .depth32Float_stencil8: return 8
        case .rgba32Uint, .rgba32Sint, .rgba32Float: return 16
        }
    }

    public var isDepthOrStencil: Bool {
        switch self {
        case .depth16Unorm, .depth32Float, .stencil8, .depth24Unorm_stencil8, .depth32Float_stencil8: return true
        default: return false
        }
    }
}

public enum MTLPrimitiveType: UInt, Sendable { case point = 0, line = 1, lineStrip = 2, triangle = 3, triangleStrip = 4 }
public enum MTLIndexType: UInt, Sendable { case uint16 = 0, uint32 = 1 }
public enum MTLLoadAction: UInt, Sendable { case dontCare = 0, load = 1, clear = 2 }
public enum MTLStoreAction: UInt, Sendable { case dontCare = 0, store = 1, multisampleResolve = 2, storeAndMultisampleResolve = 3, unknown = 4, customSampleDepthStore = 5 }
public enum MTLCullMode: UInt, Sendable { case none = 0, front = 1, back = 2 }
public enum MTLWinding: UInt, Sendable { case clockwise = 0, counterClockwise = 1 }
public enum MTLTriangleFillMode: UInt, Sendable { case fill = 0, lines = 1 }
public enum MTLCompareFunction: UInt, Sendable { case never = 0, less = 1, equal = 2, lessEqual = 3, greater = 4, notEqual = 5, greaterEqual = 6, always = 7 }
public enum MTLBlendFactor: UInt, Sendable {
    case zero = 0, one = 1, sourceColor = 2, oneMinusSourceColor = 3, sourceAlpha = 4, oneMinusSourceAlpha = 5, destinationColor = 6, oneMinusDestinationColor = 7
    case destinationAlpha = 8, oneMinusDestinationAlpha = 9, sourceAlphaSaturated = 10, blendColor = 11, oneMinusBlendColor = 12, blendAlpha = 13, oneMinusBlendAlpha = 14
    case source1Color = 15, oneMinusSource1Color = 16, source1Alpha = 17, oneMinusSource1Alpha = 18
}
public enum MTLBlendOperation: UInt, Sendable { case add = 0, subtract = 1, reverseSubtract = 2, min = 3, max = 4 }
public struct MTLColorWriteMask: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let none = MTLColorWriteMask([])
    public static let red = MTLColorWriteMask(rawValue: 8), green = MTLColorWriteMask(rawValue: 4), blue = MTLColorWriteMask(rawValue: 2), alpha = MTLColorWriteMask(rawValue: 1)
    public static let all = MTLColorWriteMask(rawValue: 15)
}
public enum MTLVertexFormat: UInt, Sendable {
    case invalid = 0, uchar2 = 1, uchar3 = 2, uchar4 = 3, char2 = 4, char3 = 5, char4 = 6, uchar2Normalized = 7, uchar3Normalized = 8, uchar4Normalized = 9
    case char2Normalized = 10, char3Normalized = 11, char4Normalized = 12, ushort2 = 13, ushort3 = 14, ushort4 = 15, short2 = 16, short3 = 17, short4 = 18
    case ushort2Normalized = 19, ushort3Normalized = 20, ushort4Normalized = 21, short2Normalized = 22, short3Normalized = 23, short4Normalized = 24
    case half2 = 25, half3 = 26, half4 = 27, float = 28, float2 = 29, float3 = 30, float4 = 31, int = 32, int2 = 33, int3 = 34, int4 = 35
    case uint = 36, uint2 = 37, uint3 = 38, uint4 = 39, int1010102Normalized = 40, uint1010102Normalized = 41, uchar4Normalized_bgra = 42
    case uchar = 45, char = 46, ucharNormalized = 47, charNormalized = 48, ushort = 49, short = 50, ushortNormalized = 51, shortNormalized = 52, half = 53
    case floatRG11B10 = 54, floatRGB9E5 = 55
}
public enum MTLVertexStepFunction: UInt, Sendable { case constant = 0, perVertex = 1, perInstance = 2, perPatch = 3, perPatchControlPoint = 4 }
public enum MTLTextureType: UInt, Sendable { case type1D = 0, type1DArray = 1, type2D = 2, type2DArray = 3, type2DMultisample = 4, typeCube = 5, typeCubeArray = 6, type3D = 7, type2DMultisampleArray = 8, typeTextureBuffer = 9 }
public struct MTLTextureUsage: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let unknown = MTLTextureUsage([])
    public static let shaderRead = MTLTextureUsage(rawValue: 1), shaderWrite = MTLTextureUsage(rawValue: 2), renderTarget = MTLTextureUsage(rawValue: 4), pixelFormatView = MTLTextureUsage(rawValue: 16), shaderAtomic = MTLTextureUsage(rawValue: 32)
}
public enum MTLStorageMode: UInt, Sendable { case shared = 0, managed = 1, `private` = 2, memoryless = 3 }
public enum MTLCPUCacheMode: UInt, Sendable { case defaultCache = 0, writeCombined = 1 }
public enum MTLHazardTrackingMode: UInt, Sendable { case `default` = 0, untracked = 1, tracked = 2 }
public struct MTLResourceOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let cpuCacheModeDefaultCache = MTLResourceOptions([])
    public static let cpuCacheModeWriteCombined = MTLResourceOptions(rawValue: 1)
    public static let storageModeShared = MTLResourceOptions(rawValue: 0 << 4)
    public static let storageModeManaged = MTLResourceOptions(rawValue: 1 << 4)
    public static let storageModePrivate = MTLResourceOptions(rawValue: 2 << 4)
    public static let storageModeMemoryless = MTLResourceOptions(rawValue: 3 << 4)
    public static let hazardTrackingModeUntracked = MTLResourceOptions(rawValue: 1 << 8)
    public static let hazardTrackingModeTracked = MTLResourceOptions(rawValue: 2 << 8)
    public var storageMode: MTLStorageMode { MTLStorageMode(rawValue: (rawValue >> 4) & 0xF) ?? .shared }
}
public enum MTLCommandBufferStatus: UInt, Sendable { case notEnqueued = 0, enqueued = 1, committed = 2, scheduled = 3, completed = 4, error = 5 }
public enum MTLSamplerMinMagFilter: UInt, Sendable { case nearest = 0, linear = 1 }
public enum MTLSamplerMipFilter: UInt, Sendable { case notMipmapped = 0, nearest = 1, linear = 2 }
public enum MTLSamplerAddressMode: UInt, Sendable { case clampToEdge = 0, mirrorClampToEdge = 1, `repeat` = 2, mirrorRepeat = 3, clampToZero = 4, clampToBorderColor = 5 }
public enum MTLSamplerBorderColor: UInt, Sendable { case transparentBlack = 0, opaqueBlack = 1, opaqueWhite = 2 }
public enum MTLLanguageVersion: UInt, Sendable {
    case version1_1 = 0x10001, version1_2 = 0x10002, version2_0 = 0x20000, version2_1 = 0x20001, version2_2 = 0x20002, version2_3 = 0x20003, version2_4 = 0x20004
    case version3_0 = 0x30000, version3_1 = 0x30001, version3_2 = 0x30002, version4_0 = 0x40000
}
public enum MTLFunctionType: UInt, Sendable { case vertex = 1, fragment = 2, kernel = 3, visible = 5, intersection = 6, mesh = 7, object = 8 }
public enum MTLGPUFamily: Int, Sendable { case common1 = 3001, common2 = 3002, common3 = 3003, mac2 = 2002, metal3 = 5001 }
public enum MTLFeatureSet: UInt, Sendable { case macOS_GPUFamily1_v1 = 10000, macOS_GPUFamily2_v1 = 10005 }
public enum MTLArgumentBuffersTier: UInt, Sendable { case tier1 = 0, tier2 = 1 }

/// Shader source dialects a library can be built from (`makeLibrary(source:options:)`).
public enum MTLShaderLanguage: Sendable { case metal, hlsl }

public struct MTLDispatchThreadgroupsIndirectArguments: Sendable { public var threadgroupsPerGrid: (UInt32, UInt32, UInt32) = (0, 0, 0); public init() {} }

public enum MTLCommandBufferError: Int, Error, Sendable { case none = 0, `internal` = 1, timeout = 2, pageFault = 3, notPermitted = 7, outOfMemory = 8, invalidResource = 9, deviceRemoved = 11 }

public struct MTLLibraryError: Error, Sendable, CustomStringConvertible {
    public enum Code: Int, Sendable { case unsupported = 1, `internal` = 2, compileFailure = 3, compileWarning = 4, functionNotFound = 5, fileNotFound = 6 }
    public let code: Code
    public let message: String
    public init(code: Code, message: String) { self.code = code; self.message = message }
    public var description: String { "MTLLibraryError(\(code)): \(message)" }
}
