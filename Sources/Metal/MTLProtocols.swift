// Metal's object model as protocols, exactly as Apple declares them, so application
// code compiles unchanged; devices come from a backend (ADR-0004).

import Foundation

// MARK: Resources

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlresource
public protocol MTLResource: AnyObject {
    var label: String? { get set }
    var device: any MTLDevice { get }
    var cpuCacheMode: MTLCPUCacheMode { get }
    var storageMode: MTLStorageMode { get }
    var hazardTrackingMode: MTLHazardTrackingMode { get }
    var resourceOptions: MTLResourceOptions { get }
    var allocatedSize: Int { get }
}

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlbuffer
public protocol MTLBuffer: MTLResource {
    var length: Int { get }
    func contents() -> UnsafeMutableRawPointer
    func didModifyRange(_ range: Range<Int>)
    var gpuAddress: UInt64 { get }
}

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtltexture
public protocol MTLTexture: MTLResource {
    var textureType: MTLTextureType { get }
    var pixelFormat: MTLPixelFormat { get }
    var width: Int { get }
    var height: Int { get }
    var depth: Int { get }
    var mipmapLevelCount: Int { get }
    var sampleCount: Int { get }
    var arrayLength: Int { get }
    var usage: MTLTextureUsage { get }
    var isFramebufferOnly: Bool { get }
    func replace(region: MTLRegion, mipmapLevel level: Int, withBytes pixelBytes: UnsafeRawPointer, bytesPerRow: Int)
    func replace(region: MTLRegion, mipmapLevel level: Int, slice: Int, withBytes pixelBytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int)
    func getBytes(_ pixelBytes: UnsafeMutableRawPointer, bytesPerRow: Int, from region: MTLRegion, mipmapLevel level: Int)
    func getBytes(_ pixelBytes: UnsafeMutableRawPointer, bytesPerRow: Int, bytesPerImage: Int, from region: MTLRegion, mipmapLevel level: Int, slice: Int)
    func makeTextureView(pixelFormat: MTLPixelFormat) -> (any MTLTexture)?
}

extension MTLTexture {
    public func replace(region: MTLRegion, mipmapLevel level: Int, withBytes pixelBytes: UnsafeRawPointer, bytesPerRow: Int) {
        replace(region: region, mipmapLevel: level, slice: 0, withBytes: pixelBytes, bytesPerRow: bytesPerRow, bytesPerImage: 0)
    }
    public func getBytes(_ pixelBytes: UnsafeMutableRawPointer, bytesPerRow: Int, from region: MTLRegion, mipmapLevel level: Int) {
        getBytes(pixelBytes, bytesPerRow: bytesPerRow, bytesPerImage: 0, from: region, mipmapLevel: level, slice: 0)
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlsamplerstate
public protocol MTLSamplerState: AnyObject {
    var label: String? { get }
    var device: any MTLDevice { get }
}

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtldepthstencilstate
public protocol MTLDepthStencilState: AnyObject {
    var label: String? { get }
    var device: any MTLDevice { get }
}

// MARK: Shaders

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlfunction
public protocol MTLFunction: AnyObject {
    var label: String? { get set }
    var device: any MTLDevice { get }
    var functionType: MTLFunctionType { get }
    var name: String { get }
}

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtllibrary
public protocol MTLLibrary: AnyObject {
    var label: String? { get set }
    var device: any MTLDevice { get }
    var functionNames: [String] { get }
    func makeFunction(name: String) -> (any MTLFunction)?
}

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlrenderpipelinestate
public protocol MTLRenderPipelineState: AnyObject {
    var label: String? { get }
    var device: any MTLDevice { get }
}

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlcomputepipelinestate
public protocol MTLComputePipelineState: AnyObject {
    var label: String? { get }
    var device: any MTLDevice { get }
    var maxTotalThreadsPerThreadgroup: Int { get }
    var threadExecutionWidth: Int { get }
}

// MARK: Commands

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlcommandencoder
public protocol MTLCommandEncoder: AnyObject {
    var device: any MTLDevice { get }
    var label: String? { get set }
    func endEncoding()
    func insertDebugSignpost(_ string: String)
    func pushDebugGroup(_ string: String)
    func popDebugGroup()
}

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlrendercommandencoder
public protocol MTLRenderCommandEncoder: MTLCommandEncoder {
    func setRenderPipelineState(_ pipelineState: any MTLRenderPipelineState)
    func setViewport(_ viewport: MTLViewport)
    func setScissorRect(_ rect: MTLScissorRect)
    func setFrontFacing(_ frontFacingWinding: MTLWinding)
    func setCullMode(_ cullMode: MTLCullMode)
    func setTriangleFillMode(_ fillMode: MTLTriangleFillMode)
    func setDepthStencilState(_ depthStencilState: (any MTLDepthStencilState)?)
    func setBlendColor(red: Float, green: Float, blue: Float, alpha: Float)
    func setStencilReferenceValue(_ referenceValue: UInt32)
    func setVertexBuffer(_ buffer: (any MTLBuffer)?, offset: Int, index: Int)
    func setVertexBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int)
    func setVertexTexture(_ texture: (any MTLTexture)?, index: Int)
    func setVertexSamplerState(_ sampler: (any MTLSamplerState)?, index: Int)
    func setFragmentBuffer(_ buffer: (any MTLBuffer)?, offset: Int, index: Int)
    func setFragmentBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int)
    func setFragmentTexture(_ texture: (any MTLTexture)?, index: Int)
    func setFragmentSamplerState(_ sampler: (any MTLSamplerState)?, index: Int)
    func drawPrimitives(type primitiveType: MTLPrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int)
    func drawPrimitives(type primitiveType: MTLPrimitiveType, vertexStart: Int, vertexCount: Int)
    func drawIndexedPrimitives(type primitiveType: MTLPrimitiveType, indexCount: Int, indexType: MTLIndexType, indexBuffer: any MTLBuffer, indexBufferOffset: Int, instanceCount: Int)
    func drawIndexedPrimitives(type primitiveType: MTLPrimitiveType, indexCount: Int, indexType: MTLIndexType, indexBuffer: any MTLBuffer, indexBufferOffset: Int)
}

extension MTLRenderCommandEncoder {
    public func drawPrimitives(type primitiveType: MTLPrimitiveType, vertexStart: Int, vertexCount: Int) {
        drawPrimitives(type: primitiveType, vertexStart: vertexStart, vertexCount: vertexCount, instanceCount: 1)
    }
    public func drawIndexedPrimitives(type primitiveType: MTLPrimitiveType, indexCount: Int, indexType: MTLIndexType, indexBuffer: any MTLBuffer, indexBufferOffset: Int) {
        drawIndexedPrimitives(type: primitiveType, indexCount: indexCount, indexType: indexType, indexBuffer: indexBuffer, indexBufferOffset: indexBufferOffset, instanceCount: 1)
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlblitcommandencoder
public protocol MTLBlitCommandEncoder: MTLCommandEncoder {
    func copy(from sourceBuffer: any MTLBuffer, sourceOffset: Int, to destinationBuffer: any MTLBuffer, destinationOffset: Int, size: Int)
    func copy(from sourceTexture: any MTLTexture, to destinationTexture: any MTLTexture)
    func copy(from sourceTexture: any MTLTexture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: MTLOrigin, sourceSize: MTLSize, to destinationTexture: any MTLTexture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: MTLOrigin)
    func copy(from sourceBuffer: any MTLBuffer, sourceOffset: Int, sourceBytesPerRow: Int, sourceBytesPerImage: Int, sourceSize: MTLSize, to destinationTexture: any MTLTexture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: MTLOrigin)
    func copy(from sourceTexture: any MTLTexture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: MTLOrigin, sourceSize: MTLSize, to destinationBuffer: any MTLBuffer, destinationOffset: Int, destinationBytesPerRow: Int, destinationBytesPerImage: Int)
    func fill(buffer: any MTLBuffer, range: Range<Int>, value: UInt8)
    func generateMipmaps(for texture: any MTLTexture)
    func synchronize(resource: any MTLResource)
}

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlcomputecommandencoder
public protocol MTLComputeCommandEncoder: MTLCommandEncoder {
    func setComputePipelineState(_ state: any MTLComputePipelineState)
    func setBuffer(_ buffer: (any MTLBuffer)?, offset: Int, index: Int)
    func setBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int)
    func setTexture(_ texture: (any MTLTexture)?, index: Int)
    func setSamplerState(_ sampler: (any MTLSamplerState)?, index: Int)
    func dispatchThreadgroups(_ threadgroupsPerGrid: MTLSize, threadsPerThreadgroup: MTLSize)
    func dispatchThreads(_ threadsPerGrid: MTLSize, threadsPerThreadgroup: MTLSize)
}

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtldrawable
public protocol MTLDrawable: AnyObject {
    var drawableID: Int { get }
    var presentedTime: TimeInterval { get }
    func present()
    func present(atTime presentationTime: TimeInterval)
    func addPresentedHandler(_ block: @escaping (any MTLDrawable) -> Void)
}

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlcommandbuffer
public protocol MTLCommandBuffer: AnyObject {
    var device: any MTLDevice { get }
    var commandQueue: any MTLCommandQueue { get }
    var label: String? { get set }
    var status: MTLCommandBufferStatus { get }
    var error: (any Error)? { get }
    func enqueue()
    func commit()
    func addScheduledHandler(_ block: @escaping (any MTLCommandBuffer) -> Void)
    func addCompletedHandler(_ block: @escaping (any MTLCommandBuffer) -> Void)
    func present(_ drawable: any MTLDrawable)
    func waitUntilScheduled()
    func waitUntilCompleted()
    func makeRenderCommandEncoder(descriptor renderPassDescriptor: MTLRenderPassDescriptor) -> (any MTLRenderCommandEncoder)?
    func makeBlitCommandEncoder() -> (any MTLBlitCommandEncoder)?
    func makeComputeCommandEncoder() -> (any MTLComputeCommandEncoder)?
}

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlcommandqueue
public protocol MTLCommandQueue: AnyObject {
    var label: String? { get set }
    var device: any MTLDevice { get }
    func makeCommandBuffer() -> (any MTLCommandBuffer)?
    func makeCommandBufferWithUnretainedReferences() -> (any MTLCommandBuffer)?
}

// MARK: Device

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtldevice
public protocol MTLDevice: AnyObject {
    var name: String { get }
    var registryID: UInt64 { get }
    var isLowPower: Bool { get }
    var isHeadless: Bool { get }
    var isRemovable: Bool { get }
    var hasUnifiedMemory: Bool { get }
    var recommendedMaxWorkingSetSize: UInt64 { get }
    var maxThreadsPerThreadgroup: MTLSize { get }
    var maxBufferLength: Int { get }
    var currentAllocatedSize: Int { get }
    var argumentBuffersSupport: MTLArgumentBuffersTier { get }
    /// False on the reference device: draws are accepted but nothing is rasterized.
    var supportsRasterization: Bool { get }
    func supportsFamily(_ gpuFamily: MTLGPUFamily) -> Bool
    func supportsFeatureSet(_ featureSet: MTLFeatureSet) -> Bool
    func supportsTextureSampleCount(_ sampleCount: Int) -> Bool
    func makeCommandQueue() -> (any MTLCommandQueue)?
    func makeCommandQueue(maxCommandBufferCount: Int) -> (any MTLCommandQueue)?
    func makeBuffer(length: Int, options: MTLResourceOptions) -> (any MTLBuffer)?
    func makeBuffer(bytes pointer: UnsafeRawPointer, length: Int, options: MTLResourceOptions) -> (any MTLBuffer)?
    func makeTexture(descriptor: MTLTextureDescriptor) -> (any MTLTexture)?
    func makeSamplerState(descriptor: MTLSamplerDescriptor) -> (any MTLSamplerState)?
    func makeDepthStencilState(descriptor: MTLDepthStencilDescriptor) -> (any MTLDepthStencilState)?
    func makeDefaultLibrary() -> (any MTLLibrary)?
    func makeLibrary(source: String, options: MTLCompileOptions?) throws -> any MTLLibrary
    func makeLibrary(data: Data) throws -> any MTLLibrary
    func makeRenderPipelineState(descriptor: MTLRenderPipelineDescriptor) throws -> any MTLRenderPipelineState
    func makeComputePipelineState(function: any MTLFunction) throws -> any MTLComputePipelineState
    func makeComputePipelineState(descriptor: MTLComputePipelineDescriptor) throws -> any MTLComputePipelineState
    func minimumLinearTextureAlignment(for format: MTLPixelFormat) -> Int
    func minimumTextureBufferAlignment(for format: MTLPixelFormat) -> Int
    func makeEvent() -> (any MTLEvent)?
    func makeSharedEvent() -> (any MTLSharedEvent)?
}

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlevent
public protocol MTLEvent: AnyObject {
    var device: any MTLDevice { get }
    var label: String? { get set }
}

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlsharedevent
public protocol MTLSharedEvent: MTLEvent {
    var signaledValue: UInt64 { get set }
}

extension MTLDevice {
    public func makeCommandQueue() -> (any MTLCommandQueue)? { makeCommandQueue(maxCommandBufferCount: 64) }
    public func makeComputePipelineState(descriptor: MTLComputePipelineDescriptor) throws -> any MTLComputePipelineState {
        guard let f = descriptor.computeFunction else { throw MTLLibraryError(code: .functionNotFound, message: "no compute function") }
        return try makeComputePipelineState(function: f)
    }
    public func supportsFeatureSet(_ featureSet: MTLFeatureSet) -> Bool { true }
    public func supportsTextureSampleCount(_ sampleCount: Int) -> Bool { sampleCount == 1 || sampleCount == 4 }
}

// MARK: Device discovery

/// Where devices come from. The reference device is always available; platform backends
/// (D3D12 on Windows) register themselves at startup and take precedence.
public enum MTLDeviceRegistry {
    nonisolated(unsafe) public static var makers: [() -> (any MTLDevice)?] = []
    nonisolated(unsafe) private static var cached: (any MTLDevice)?

    public static func defaultDevice() -> (any MTLDevice)? {
        if let c = cached { return c }
        for m in makers { if let d = m() { cached = d; return d } }
        #if os(Windows)
        // The D3D12 backend, when its shim is built (APPKITWIN_METAL_REFERENCE=1 skips it).
        if ProcessInfo.processInfo.environment["APPKITWIN_METAL_REFERENCE"] != "1", let d = MTLD3D12Device() { cached = d; return d }
        #endif
        let r = MTLReferenceDevice()
        cached = r
        return r
    }

    public static func allDevices() -> [any MTLDevice] {
        var out: [any MTLDevice] = makers.compactMap { $0() }
        if out.isEmpty, let d = defaultDevice() { out = [d] }
        return out
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlcreatesystemdefaultdevice()
public func MTLCreateSystemDefaultDevice() -> (any MTLDevice)? { MTLDeviceRegistry.defaultDevice() }

/// - SeeAlso: https://developer.apple.com/documentation/metal/mtlcopyalldevices()
public func MTLCopyAllDevices() -> [any MTLDevice] { MTLDeviceRegistry.allDevices() }
