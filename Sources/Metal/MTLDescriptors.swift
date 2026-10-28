// Descriptor classes: plain value holders, copied when a state object is created.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtltexturedescriptor
public final class MTLTextureDescriptor: NSObject, NSCopying {
    public var textureType: MTLTextureType = .type2D
    public var pixelFormat: MTLPixelFormat = .rgba8Unorm
    public var width = 1
    public var height = 1
    public var depth = 1
    public var mipmapLevelCount = 1
    public var sampleCount = 1
    public var arrayLength = 1
    public var resourceOptions: MTLResourceOptions = []
    public var cpuCacheMode: MTLCPUCacheMode = .defaultCache
    public var storageMode: MTLStorageMode = .managed
    public var hazardTrackingMode: MTLHazardTrackingMode = .default
    public var usage: MTLTextureUsage = .shaderRead
    public var allowGPUOptimizedContents = true

    public override init() { super.init() }

    public class func texture2DDescriptor(pixelFormat: MTLPixelFormat, width: Int, height: Int, mipmapped: Bool) -> MTLTextureDescriptor {
        let d = MTLTextureDescriptor()
        d.pixelFormat = pixelFormat; d.width = width; d.height = height
        d.mipmapLevelCount = mipmapped ? max(1, Int(log2(Double(max(width, height)))) + 1) : 1
        return d
    }

    public class func textureCubeDescriptor(pixelFormat: MTLPixelFormat, size: Int, mipmapped: Bool) -> MTLTextureDescriptor {
        let d = texture2DDescriptor(pixelFormat: pixelFormat, width: size, height: size, mipmapped: mipmapped)
        d.textureType = .typeCube
        return d
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        let d = MTLTextureDescriptor()
        d.textureType = textureType; d.pixelFormat = pixelFormat; d.width = width; d.height = height; d.depth = depth
        d.mipmapLevelCount = mipmapLevelCount; d.sampleCount = sampleCount; d.arrayLength = arrayLength; d.resourceOptions = resourceOptions
        d.cpuCacheMode = cpuCacheMode; d.storageMode = storageMode; d.hazardTrackingMode = hazardTrackingMode; d.usage = usage
        return d
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlrenderpassattachmentdescriptor
public class MTLRenderPassAttachmentDescriptor: NSObject, NSCopying {
    public var texture: (any MTLTexture)?
    public var level = 0
    public var slice = 0
    public var depthPlane = 0
    public var loadAction: MTLLoadAction = .dontCare
    public var storeAction: MTLStoreAction = .dontCare
    public var resolveTexture: (any MTLTexture)?
    public var resolveLevel = 0
    public var resolveSlice = 0
    public override init() { super.init() }
    func copyInto(_ d: MTLRenderPassAttachmentDescriptor) {
        d.texture = texture; d.level = level; d.slice = slice; d.depthPlane = depthPlane; d.loadAction = loadAction; d.storeAction = storeAction
        d.resolveTexture = resolveTexture; d.resolveLevel = resolveLevel; d.resolveSlice = resolveSlice
    }
    public func copy(with zone: NSZone? = nil) -> Any { let d = MTLRenderPassAttachmentDescriptor(); copyInto(d); return d }
}

public final class MTLRenderPassColorAttachmentDescriptor: MTLRenderPassAttachmentDescriptor {
    public var clearColor = MTLClearColor()
    public override func copy(with zone: NSZone? = nil) -> Any { let d = MTLRenderPassColorAttachmentDescriptor(); copyInto(d); d.clearColor = clearColor; return d }
}

public final class MTLRenderPassDepthAttachmentDescriptor: MTLRenderPassAttachmentDescriptor {
    public var clearDepth: Double = 1
    public override func copy(with zone: NSZone? = nil) -> Any { let d = MTLRenderPassDepthAttachmentDescriptor(); copyInto(d); d.clearDepth = clearDepth; return d }
}

public final class MTLRenderPassStencilAttachmentDescriptor: MTLRenderPassAttachmentDescriptor {
    public var clearStencil: UInt32 = 0
    public override func copy(with zone: NSZone? = nil) -> Any { let d = MTLRenderPassStencilAttachmentDescriptor(); copyInto(d); d.clearStencil = clearStencil; return d }
}

/// Indexed collection with Metal's sparse semantics (`colorAttachments[0]`).
public final class MTLRenderPassColorAttachmentDescriptorArray: NSObject {
    private var items: [Int: MTLRenderPassColorAttachmentDescriptor] = [:]
    public subscript(index: Int) -> MTLRenderPassColorAttachmentDescriptor! {
        get {
            if let d = items[index] { return d }
            let d = MTLRenderPassColorAttachmentDescriptor()
            items[index] = d
            return d
        }
        set { items[index] = newValue }
    }
    var indices: [Int] { items.keys.sorted() }
}

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlrenderpassdescriptor
public final class MTLRenderPassDescriptor: NSObject, NSCopying {
    public let colorAttachments = MTLRenderPassColorAttachmentDescriptorArray()
    public var depthAttachment: MTLRenderPassDepthAttachmentDescriptor! = MTLRenderPassDepthAttachmentDescriptor()
    public var stencilAttachment: MTLRenderPassStencilAttachmentDescriptor! = MTLRenderPassStencilAttachmentDescriptor()
    public var visibilityResultBuffer: (any MTLBuffer)?
    public var renderTargetArrayLength = 0
    public var renderTargetWidth = 0
    public var renderTargetHeight = 0
    public var defaultRasterSampleCount = 0
    public override init() { super.init() }
    public func copy(with zone: NSZone? = nil) -> Any {
        let d = MTLRenderPassDescriptor()
        for i in colorAttachments.indices { d.colorAttachments[i] = (colorAttachments[i].copy() as! MTLRenderPassColorAttachmentDescriptor) }
        d.depthAttachment = (depthAttachment.copy() as! MTLRenderPassDepthAttachmentDescriptor)
        d.stencilAttachment = (stencilAttachment.copy() as! MTLRenderPassStencilAttachmentDescriptor)
        d.renderTargetWidth = renderTargetWidth; d.renderTargetHeight = renderTargetHeight
        return d
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlrenderpipelinecolorattachmentdescriptor
public final class MTLRenderPipelineColorAttachmentDescriptor: NSObject, NSCopying {
    public var pixelFormat: MTLPixelFormat = .invalid
    public var isBlendingEnabled = false
    public var sourceRGBBlendFactor: MTLBlendFactor = .one
    public var destinationRGBBlendFactor: MTLBlendFactor = .zero
    public var rgbBlendOperation: MTLBlendOperation = .add
    public var sourceAlphaBlendFactor: MTLBlendFactor = .one
    public var destinationAlphaBlendFactor: MTLBlendFactor = .zero
    public var alphaBlendOperation: MTLBlendOperation = .add
    public var writeMask: MTLColorWriteMask = .all
    public override init() { super.init() }
    public func copy(with zone: NSZone? = nil) -> Any {
        let d = MTLRenderPipelineColorAttachmentDescriptor()
        d.pixelFormat = pixelFormat; d.isBlendingEnabled = isBlendingEnabled
        d.sourceRGBBlendFactor = sourceRGBBlendFactor; d.destinationRGBBlendFactor = destinationRGBBlendFactor; d.rgbBlendOperation = rgbBlendOperation
        d.sourceAlphaBlendFactor = sourceAlphaBlendFactor; d.destinationAlphaBlendFactor = destinationAlphaBlendFactor; d.alphaBlendOperation = alphaBlendOperation
        d.writeMask = writeMask
        return d
    }
}

public final class MTLRenderPipelineColorAttachmentDescriptorArray: NSObject {
    private var items: [Int: MTLRenderPipelineColorAttachmentDescriptor] = [:]
    public subscript(index: Int) -> MTLRenderPipelineColorAttachmentDescriptor! {
        get {
            if let d = items[index] { return d }
            let d = MTLRenderPipelineColorAttachmentDescriptor()
            items[index] = d
            return d
        }
        set { items[index] = newValue }
    }
    var indices: [Int] { items.keys.sorted() }
}

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlvertexattributedescriptor
public final class MTLVertexAttributeDescriptor: NSObject {
    public var format: MTLVertexFormat = .invalid
    public var offset = 0
    public var bufferIndex = 0
    public override init() { super.init() }
}

public final class MTLVertexBufferLayoutDescriptor: NSObject {
    public var stride = 0
    public var stepFunction: MTLVertexStepFunction = .perVertex
    public var stepRate = 1
    public override init() { super.init() }
}

public final class MTLVertexAttributeDescriptorArray: NSObject {
    private var items: [Int: MTLVertexAttributeDescriptor] = [:]
    public subscript(index: Int) -> MTLVertexAttributeDescriptor! {
        get { if let d = items[index] { return d }; let d = MTLVertexAttributeDescriptor(); items[index] = d; return d }
        set { items[index] = newValue }
    }
    public var indices: [Int] { items.keys.sorted() }
}

public final class MTLVertexBufferLayoutDescriptorArray: NSObject {
    private var items: [Int: MTLVertexBufferLayoutDescriptor] = [:]
    public subscript(index: Int) -> MTLVertexBufferLayoutDescriptor! {
        get { if let d = items[index] { return d }; let d = MTLVertexBufferLayoutDescriptor(); items[index] = d; return d }
        set { items[index] = newValue }
    }
    public var indices: [Int] { items.keys.sorted() }
}

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlvertexdescriptor
public final class MTLVertexDescriptor: NSObject, NSCopying {
    public let attributes = MTLVertexAttributeDescriptorArray()
    public let layouts = MTLVertexBufferLayoutDescriptorArray()
    public override init() { super.init() }
    public func reset() {
        for i in attributes.indices { attributes[i] = nil }
        for i in layouts.indices { layouts[i] = nil }
    }
    public func copy(with zone: NSZone? = nil) -> Any {
        let d = MTLVertexDescriptor()
        for i in attributes.indices { let a = MTLVertexAttributeDescriptor(); a.format = attributes[i].format; a.offset = attributes[i].offset; a.bufferIndex = attributes[i].bufferIndex; d.attributes[i] = a }
        for i in layouts.indices { let l = MTLVertexBufferLayoutDescriptor(); l.stride = layouts[i].stride; l.stepFunction = layouts[i].stepFunction; l.stepRate = layouts[i].stepRate; d.layouts[i] = l }
        return d
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlrenderpipelinedescriptor
public final class MTLRenderPipelineDescriptor: NSObject, NSCopying {
    public var label: String?
    public var vertexFunction: (any MTLFunction)?
    public var fragmentFunction: (any MTLFunction)?
    public var vertexDescriptor: MTLVertexDescriptor?
    public let colorAttachments = MTLRenderPipelineColorAttachmentDescriptorArray()
    public var depthAttachmentPixelFormat: MTLPixelFormat = .invalid
    public var stencilAttachmentPixelFormat: MTLPixelFormat = .invalid
    public var rasterSampleCount = 1
    public var isAlphaToCoverageEnabled = false
    public var isAlphaToOneEnabled = false
    public var isRasterizationEnabled = true
    public var inputPrimitiveTopology: MTLPrimitiveTopologyClass = .unspecified
    public var maxVertexAmplificationCount = 1
    public override init() { super.init() }
    public func reset() {
        label = nil; vertexFunction = nil; fragmentFunction = nil; vertexDescriptor = nil
        for i in colorAttachments.indices { colorAttachments[i] = nil }
        depthAttachmentPixelFormat = .invalid; stencilAttachmentPixelFormat = .invalid; rasterSampleCount = 1
    }
    public func copy(with zone: NSZone? = nil) -> Any {
        let d = MTLRenderPipelineDescriptor()
        d.label = label; d.vertexFunction = vertexFunction; d.fragmentFunction = fragmentFunction
        d.vertexDescriptor = vertexDescriptor.map { $0.copy() as! MTLVertexDescriptor }
        for i in colorAttachments.indices { d.colorAttachments[i] = (colorAttachments[i].copy() as! MTLRenderPipelineColorAttachmentDescriptor) }
        d.depthAttachmentPixelFormat = depthAttachmentPixelFormat; d.stencilAttachmentPixelFormat = stencilAttachmentPixelFormat
        d.rasterSampleCount = rasterSampleCount; d.isAlphaToCoverageEnabled = isAlphaToCoverageEnabled; d.isAlphaToOneEnabled = isAlphaToOneEnabled
        d.isRasterizationEnabled = isRasterizationEnabled; d.inputPrimitiveTopology = inputPrimitiveTopology
        return d
    }
}

public enum MTLPrimitiveTopologyClass: UInt, Sendable { case unspecified = 0, point = 1, line = 2, triangle = 3 }

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlcomputepipelinedescriptor
public final class MTLComputePipelineDescriptor: NSObject {
    public var label: String?
    public var computeFunction: (any MTLFunction)?
    public var threadGroupSizeIsMultipleOfThreadExecutionWidth = false
    public var maxTotalThreadsPerThreadgroup = 1024
    public override init() { super.init() }
}

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlstencildescriptor
public final class MTLStencilDescriptor: NSObject {
    public var stencilCompareFunction: MTLCompareFunction = .always
    public var stencilFailureOperation: MTLStencilOperation = .keep
    public var depthFailureOperation: MTLStencilOperation = .keep
    public var depthStencilPassOperation: MTLStencilOperation = .keep
    public var readMask: UInt32 = 0xFFFF_FFFF
    public var writeMask: UInt32 = 0xFFFF_FFFF
    public override init() { super.init() }
}

public enum MTLStencilOperation: UInt, Sendable { case keep = 0, zero = 1, replace = 2, incrementClamp = 3, decrementClamp = 4, invert = 5, incrementWrap = 6, decrementWrap = 7 }

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtldepthstencildescriptor
public final class MTLDepthStencilDescriptor: NSObject {
    public var label: String?
    public var depthCompareFunction: MTLCompareFunction = .always
    public var isDepthWriteEnabled = false
    public var frontFaceStencil: MTLStencilDescriptor! = MTLStencilDescriptor()
    public var backFaceStencil: MTLStencilDescriptor! = MTLStencilDescriptor()
    public override init() { super.init() }
}

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlsamplerdescriptor
public final class MTLSamplerDescriptor: NSObject {
    public var label: String?
    public var minFilter: MTLSamplerMinMagFilter = .nearest
    public var magFilter: MTLSamplerMinMagFilter = .nearest
    public var mipFilter: MTLSamplerMipFilter = .notMipmapped
    public var maxAnisotropy = 1
    public var sAddressMode: MTLSamplerAddressMode = .clampToEdge
    public var tAddressMode: MTLSamplerAddressMode = .clampToEdge
    public var rAddressMode: MTLSamplerAddressMode = .clampToEdge
    public var borderColor: MTLSamplerBorderColor = .transparentBlack
    public var normalizedCoordinates = true
    public var lodMinClamp: Float = 0
    public var lodMaxClamp: Float = .greatestFiniteMagnitude
    public var compareFunction: MTLCompareFunction = .never
    public var supportArgumentBuffers = false
    public override init() { super.init() }
}

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlcompileoptions
public final class MTLCompileOptions: NSObject {
    public var preprocessorMacros: [String: NSObject]?
    public var fastMathEnabled = true
    public var languageVersion: MTLLanguageVersion = .version3_1
    public var preserveInvariance = false
    public var optimizationLevel = 0
    /// Which dialect `source` is written in (this port's extension; see ADR-0004).
    public var shaderLanguage: MTLShaderLanguage = .metal
    public override init() { super.init() }
}
