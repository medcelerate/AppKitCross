// The reference device: CPU-side resources, blits and render-pass clears, no
// rasterization. It makes the Metal API usable and testable on every platform and is
// what MTKView presents when no GPU backend is registered (ADR-0004).

import Foundation

/// - SeeAlso: ADR-0004
public final class MTLReferenceDevice: MTLDevice, @unchecked Sendable {
    public let name = "AppKitWin Reference Device"
    public let registryID: UInt64 = 1
    public let isLowPower = true
    public let isHeadless = true
    public let isRemovable = false
    public let hasUnifiedMemory = true
    public let recommendedMaxWorkingSetSize: UInt64 = 1 << 30
    public let maxThreadsPerThreadgroup = MTLSize(width: 1024, height: 1024, depth: 1024)
    public let maxBufferLength = 1 << 30
    public private(set) var currentAllocatedSize = 0
    public let argumentBuffersSupport: MTLArgumentBuffersTier = .tier1
    public let supportsRasterization = false
    private let lock = NSLock()

    public init() {}

    func allocated(_ delta: Int) { lock.lock(); currentAllocatedSize += delta; lock.unlock() }

    public func supportsFamily(_ gpuFamily: MTLGPUFamily) -> Bool { gpuFamily == .common1 || gpuFamily == .common2 }

    public func makeCommandQueue(maxCommandBufferCount: Int) -> (any MTLCommandQueue)? { MTLReferenceCommandQueue(device: self) }

    public func makeBuffer(length: Int, options: MTLResourceOptions) -> (any MTLBuffer)? {
        guard length > 0, length <= maxBufferLength else { return nil }
        return MTLReferenceBuffer(device: self, length: length, options: options)
    }

    public func makeBuffer(bytes pointer: UnsafeRawPointer, length: Int, options: MTLResourceOptions) -> (any MTLBuffer)? {
        guard let b = makeBuffer(length: length, options: options) else { return nil }
        b.contents().copyMemory(from: pointer, byteCount: length)
        return b
    }

    public func makeTexture(descriptor: MTLTextureDescriptor) -> (any MTLTexture)? {
        guard descriptor.width > 0, descriptor.height > 0, descriptor.pixelFormat != .invalid else { return nil }
        return MTLReferenceTexture(device: self, descriptor: descriptor)
    }

    public func makeSamplerState(descriptor: MTLSamplerDescriptor) -> (any MTLSamplerState)? { MTLReferenceSamplerState(device: self, label: descriptor.label) }
    public func makeDepthStencilState(descriptor: MTLDepthStencilDescriptor) -> (any MTLDepthStencilState)? { MTLReferenceDepthStencilState(device: self, label: descriptor.label) }

    public func makeDefaultLibrary() -> (any MTLLibrary)? { nil }

    /// MSL is translated to HLSL (ADR-0006) so unsupported constructs fail here as they
    /// would on the D3D12 device; HLSL is scanned for its entry points. Nothing is
    /// compiled (the reference device does not run shaders).
    public func makeLibrary(source: String, options: MTLCompileOptions?) throws -> any MTLLibrary {
        let (functions, translation) = try MTLReferenceLibrary.prepare(source: source, options: options)
        return MTLReferenceLibrary(device: self, functions: functions, translation: translation)
    }

    public func makeLibrary(data: Data) throws -> any MTLLibrary {
        throw MTLLibraryError(code: .unsupported, message: "the reference device cannot load compiled libraries")
    }

    public func makeRenderPipelineState(descriptor: MTLRenderPipelineDescriptor) throws -> any MTLRenderPipelineState {
        guard descriptor.vertexFunction != nil else { throw MTLLibraryError(code: .functionNotFound, message: "render pipeline needs a vertex function") }
        for i in descriptor.colorAttachments.indices where descriptor.colorAttachments[i].pixelFormat == .invalid {
            throw MTLLibraryError(code: .internal, message: "color attachment \(i) has no pixel format")
        }
        return MTLReferenceRenderPipelineState(device: self, descriptor: descriptor.copy() as! MTLRenderPipelineDescriptor)
    }

    public func makeComputePipelineState(function: any MTLFunction) throws -> any MTLComputePipelineState {
        MTLReferenceComputePipelineState(device: self, function: function)
    }

    public func minimumLinearTextureAlignment(for format: MTLPixelFormat) -> Int { 16 }
    public func minimumTextureBufferAlignment(for format: MTLPixelFormat) -> Int { 16 }
    public func makeEvent() -> (any MTLEvent)? { MTLReferenceEvent(device: self) }
    public func makeSharedEvent() -> (any MTLSharedEvent)? { MTLReferenceEvent(device: self) }
}

// MARK: Resources

public final class MTLReferenceBuffer: MTLBuffer, @unchecked Sendable {
    public var label: String?
    public let device: any MTLDevice
    public let length: Int
    public let resourceOptions: MTLResourceOptions
    public var cpuCacheMode: MTLCPUCacheMode { resourceOptions.contains(.cpuCacheModeWriteCombined) ? .writeCombined : .defaultCache }
    public var storageMode: MTLStorageMode { resourceOptions.storageMode }
    public var hazardTrackingMode: MTLHazardTrackingMode { .default }
    public var allocatedSize: Int { length }
    public let gpuAddress: UInt64
    let storage: UnsafeMutableRawPointer

    init(device: MTLReferenceDevice, length: Int, options: MTLResourceOptions) {
        self.device = device
        self.length = length
        resourceOptions = options
        storage = UnsafeMutableRawPointer.allocate(byteCount: length, alignment: 16)
        storage.initializeMemory(as: UInt8.self, repeating: 0, count: length)
        gpuAddress = UInt64(UInt(bitPattern: storage))
        device.allocated(length)
    }

    deinit {
        storage.deallocate()
        (device as? MTLReferenceDevice)?.allocated(-length)
    }

    public func contents() -> UnsafeMutableRawPointer { storage }
    public func didModifyRange(_ range: Range<Int>) {}
}

public final class MTLReferenceTexture: MTLTexture, @unchecked Sendable {
    public var label: String?
    public let device: any MTLDevice
    public let textureType: MTLTextureType
    public let pixelFormat: MTLPixelFormat
    public let width: Int, height: Int, depth: Int
    public let mipmapLevelCount: Int
    public let sampleCount: Int
    public let arrayLength: Int
    public let usage: MTLTextureUsage
    public let isFramebufferOnly = false
    public let resourceOptions: MTLResourceOptions
    public var cpuCacheMode: MTLCPUCacheMode { .defaultCache }
    public var storageMode: MTLStorageMode { resourceOptions.storageMode }
    public var hazardTrackingMode: MTLHazardTrackingMode { .default }
    public var allocatedSize: Int { pixels.count }
    /// Level 0, slice 0 pixels, row-major, `bytesPerRow` apart (other levels/slices are not stored).
    var pixels: [UInt8]
    public let bytesPerRow: Int

    init(device: MTLReferenceDevice, descriptor d: MTLTextureDescriptor) {
        self.device = device
        textureType = d.textureType; pixelFormat = d.pixelFormat
        width = d.width; height = d.height; depth = d.depth
        mipmapLevelCount = d.mipmapLevelCount; sampleCount = d.sampleCount; arrayLength = d.arrayLength
        usage = d.usage; resourceOptions = d.resourceOptions
        bytesPerRow = d.width * max(1, d.pixelFormat.bytesPerPixel)
        pixels = [UInt8](repeating: 0, count: bytesPerRow * d.height * max(1, d.depth))
        device.allocated(pixels.count)
    }

    deinit { (device as? MTLReferenceDevice)?.allocated(-pixels.count) }

    public func replace(region: MTLRegion, mipmapLevel level: Int, slice: Int, withBytes pixelBytes: UnsafeRawPointer, bytesPerRow srcBytesPerRow: Int, bytesPerImage: Int) {
        guard level == 0, slice == 0 else { return }
        let bpp = pixelFormat.bytesPerPixel
        for row in 0..<region.size.height {
            let y = region.origin.y + row
            guard y < height else { break }
            let src = pixelBytes + row * srcBytesPerRow
            let dst = y * bytesPerRow + region.origin.x * bpp
            let n = min(region.size.width, width - region.origin.x) * bpp
            pixels.withUnsafeMutableBytes { $0.baseAddress!.advanced(by: dst).copyMemory(from: src, byteCount: n) }
        }
    }

    public func getBytes(_ pixelBytes: UnsafeMutableRawPointer, bytesPerRow dstBytesPerRow: Int, bytesPerImage: Int, from region: MTLRegion, mipmapLevel level: Int, slice: Int) {
        guard level == 0, slice == 0 else { return }
        let bpp = pixelFormat.bytesPerPixel
        for row in 0..<region.size.height {
            let y = region.origin.y + row
            guard y < height else { break }
            let src = y * bytesPerRow + region.origin.x * bpp
            let n = min(region.size.width, width - region.origin.x) * bpp
            pixels.withUnsafeBytes { (pixelBytes + row * dstBytesPerRow).copyMemory(from: $0.baseAddress!.advanced(by: src), byteCount: n) }
        }
    }

    public func makeTextureView(pixelFormat: MTLPixelFormat) -> (any MTLTexture)? { pixelFormat == self.pixelFormat ? self : nil }

    /// Fills level 0 with a colour (render-pass clear).
    func clear(_ c: MTLClearColor) {
        func u8(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        let r = u8(c.red), g = u8(c.green), b = u8(c.blue), a = u8(c.alpha)
        let bpp = pixelFormat.bytesPerPixel
        var px: [UInt8]
        switch pixelFormat {
        case .bgra8Unorm, .bgra8Unorm_srgb: px = [b, g, r, a]
        case .rgba8Unorm, .rgba8Unorm_srgb: px = [r, g, b, a]
        case .r8Unorm, .a8Unorm: px = [pixelFormat == .a8Unorm ? a : r]
        case .rg8Unorm: px = [r, g]
        case .rgba32Float, .rg32Float, .r32Float, .depth32Float:
            var f: [Float] = [Float(c.red), Float(c.green), Float(c.blue), Float(c.alpha)]
            if pixelFormat == .depth32Float { f = [Float(c.red)] }
            px = f.prefix(bpp / 4).flatMap { withUnsafeBytes(of: $0.bitPattern.littleEndian) { Array($0) } }
        default: px = [UInt8](repeating: 0, count: bpp)
        }
        guard px.count == bpp else { return }
        for i in stride(from: 0, to: pixels.count, by: bpp) { pixels.replaceSubrange(i..<i + bpp, with: px) }
    }
}

final class MTLReferenceSamplerState: MTLSamplerState {
    let label: String?
    let device: any MTLDevice
    init(device: any MTLDevice, label: String?) { self.device = device; self.label = label }
}

final class MTLReferenceDepthStencilState: MTLDepthStencilState {
    let label: String?
    let device: any MTLDevice
    init(device: any MTLDevice, label: String?) { self.device = device; self.label = label }
}

final class MTLReferenceEvent: MTLSharedEvent {
    let device: any MTLDevice
    var label: String?
    var signaledValue: UInt64 = 0
    init(device: any MTLDevice) { self.device = device }
}

// MARK: Shaders

public final class MTLReferenceFunction: MTLFunction {
    public var label: String?
    public let device: any MTLDevice
    public let functionType: MTLFunctionType
    public let name: String
    init(device: any MTLDevice, name: String, type: MTLFunctionType) { self.device = device; self.name = name; functionType = type }
}

public final class MTLReferenceLibrary: MTLLibrary {
    public var label: String?
    public let device: any MTLDevice
    let functions: [(String, MTLFunctionType)]
    /// The MSL → HLSL translation when the source was MSL.
    public let translation: MSLTranslation?
    /// The HLSL the library compiles (translated from MSL); nil for HLSL sources.
    public var hlslSource: String? { translation?.hlsl }
    public var functionNames: [String] { functions.map(\.0) }

    init(device: any MTLDevice, functions: [(String, MTLFunctionType)], translation: MSLTranslation? = nil) { self.device = device; self.functions = functions; self.translation = translation }

    /// Shared by the devices: picks the dialect (`options.shaderLanguage`, else detected
    /// from the source), translates MSL and lists the entry points.
    static func prepare(source: String, options: MTLCompileOptions?) throws -> ([(String, MTLFunctionType)], MSLTranslation?) {
        let language = options?.shaderLanguage == .hlsl ? MTLShaderLanguage.hlsl : MSLTranslator.detectLanguage(source)
        if language == .hlsl { return (scanFunctions(in: source, language: .hlsl), nil) }
        do {
            let translation = try MSLTranslator.translate(source)
            return (translation.functions.map { ($0.name, $0.type) }, translation)
        } catch let error as MSLTranslationError {
            throw MTLLibraryError(code: .compileFailure, message: "MSL translation failed at \(error)")
        }
    }

    public func makeFunction(name: String) -> (any MTLFunction)? {
        guard let f = functions.first(where: { $0.0 == name }) else { return nil }
        return MTLReferenceFunction(device: device, name: f.0, type: f.1)
    }

    /// Finds `vertex`/`fragment`/`kernel` functions in MSL, or any top-level function in HLSL.
    static func scanFunctions(in source: String, language: MTLShaderLanguage) -> [(String, MTLFunctionType)] {
        var out: [(String, MTLFunctionType)] = []
        let tokens = source.replacingOccurrences(of: "(", with: " ( ").split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            if language == .metal, let type: MTLFunctionType = t == "vertex" ? .vertex : t == "fragment" ? .fragment : t == "kernel" ? .kernel : nil {
                // vertex <return type...> name (
                var j = i + 1
                while j + 1 < tokens.count && tokens[j + 1] != "(" { j += 1 }
                if j + 1 < tokens.count { out.append((tokens[j], type)) }
                i = j + 1
                continue
            }
            if language == .hlsl, i >= 1, t == "(", !tokens[i - 1].isEmpty, i >= 2 {
                let name = tokens[i - 1]
                let returnType = tokens[i - 2]
                let keywords: Set<String> = ["if", "for", "while", "switch", "return", "sizeof"]
                if !keywords.contains(name), name.first!.isLetter || name.first == "_", returnType != "=" {
                    let type: MTLFunctionType = name.lowercased().contains("vert") || name.lowercased().hasPrefix("vs") ? .vertex : name.lowercased().contains("frag") || name.lowercased().contains("pixel") || name.lowercased().hasPrefix("ps") ? .fragment : .kernel
                    if !out.contains(where: { $0.0 == name }) { out.append((name, type)) }
                }
            }
            i += 1
        }
        return out
    }
}

final class MTLReferenceRenderPipelineState: MTLRenderPipelineState {
    let label: String?
    let device: any MTLDevice
    let descriptor: MTLRenderPipelineDescriptor
    init(device: any MTLDevice, descriptor: MTLRenderPipelineDescriptor) { self.device = device; self.descriptor = descriptor; label = descriptor.label }
}

final class MTLReferenceComputePipelineState: MTLComputePipelineState {
    let label: String?
    let device: any MTLDevice
    let maxTotalThreadsPerThreadgroup = 1024
    let threadExecutionWidth = 32
    init(device: any MTLDevice, function: any MTLFunction) { self.device = device; label = function.label }
}

// MARK: Commands

final class MTLReferenceCommandQueue: MTLCommandQueue {
    var label: String?
    let device: any MTLDevice
    init(device: any MTLDevice) { self.device = device }
    func makeCommandBuffer() -> (any MTLCommandBuffer)? { MTLReferenceCommandBuffer(queue: self) }
    func makeCommandBufferWithUnretainedReferences() -> (any MTLCommandBuffer)? { makeCommandBuffer() }
}

/// Records work as closures and runs them synchronously on commit.
public final class MTLReferenceCommandBuffer: MTLCommandBuffer {
    public let device: any MTLDevice
    public let commandQueue: any MTLCommandQueue
    public var label: String?
    public private(set) var status: MTLCommandBufferStatus = .notEnqueued
    public private(set) var error: (any Error)?
    var work: [() -> Void] = []
    private var scheduledHandlers: [(any MTLCommandBuffer) -> Void] = []
    private var completedHandlers: [(any MTLCommandBuffer) -> Void] = []
    private var drawables: [any MTLDrawable] = []
    /// Number of draw calls recorded (for tests and tooling).
    public private(set) var drawCallCount = 0

    init(queue: MTLReferenceCommandQueue) { device = queue.device; commandQueue = queue }

    public func enqueue() { if status == .notEnqueued { status = .enqueued } }

    public func commit() {
        guard status.rawValue < MTLCommandBufferStatus.committed.rawValue else { return }
        status = .committed
        status = .scheduled
        for h in scheduledHandlers { h(self) }
        for w in work { w() }
        work.removeAll()
        for d in drawables { d.present() }
        drawables.removeAll()
        status = .completed
        for h in completedHandlers { h(self) }
    }

    public func addScheduledHandler(_ block: @escaping (any MTLCommandBuffer) -> Void) { scheduledHandlers.append(block) }
    public func addCompletedHandler(_ block: @escaping (any MTLCommandBuffer) -> Void) { completedHandlers.append(block) }
    public func present(_ drawable: any MTLDrawable) { drawables.append(drawable) }
    public func waitUntilScheduled() {}
    public func waitUntilCompleted() { if status != .completed { commit() } }

    public func makeRenderCommandEncoder(descriptor renderPassDescriptor: MTLRenderPassDescriptor) -> (any MTLRenderCommandEncoder)? {
        let pass = renderPassDescriptor.copy() as! MTLRenderPassDescriptor
        work.append {
            for i in pass.colorAttachments.indices {
                let a = pass.colorAttachments[i]!
                if a.loadAction == .clear, let t = a.texture as? MTLReferenceTexture { t.clear(a.clearColor) }
            }
            if pass.depthAttachment.loadAction == .clear, let t = pass.depthAttachment.texture as? MTLReferenceTexture {
                t.clear(MTLClearColor(red: pass.depthAttachment.clearDepth, green: 0, blue: 0, alpha: 0))
            }
        }
        return MTLReferenceRenderCommandEncoder(buffer: self)
    }

    public func makeBlitCommandEncoder() -> (any MTLBlitCommandEncoder)? { MTLReferenceBlitCommandEncoder(buffer: self) }
    public func makeComputeCommandEncoder() -> (any MTLComputeCommandEncoder)? { MTLReferenceComputeCommandEncoder(buffer: self) }

    func recordDraw() { drawCallCount += 1 }
}

class MTLReferenceEncoder: MTLCommandEncoder {
    let buffer: MTLReferenceCommandBuffer
    var device: any MTLDevice { buffer.device }
    var label: String?
    private(set) var hasEnded = false
    init(buffer: MTLReferenceCommandBuffer) { self.buffer = buffer }
    func endEncoding() { hasEnded = true }
    func insertDebugSignpost(_ string: String) {}
    func pushDebugGroup(_ string: String) {}
    func popDebugGroup() {}
}

final class MTLReferenceRenderCommandEncoder: MTLReferenceEncoder, MTLRenderCommandEncoder {
    private(set) var pipelineState: (any MTLRenderPipelineState)?
    private(set) var vertexBuffers: [Int: (any MTLBuffer, Int)] = [:]
    private(set) var fragmentBuffers: [Int: (any MTLBuffer, Int)] = [:]
    func setRenderPipelineState(_ pipelineState: any MTLRenderPipelineState) { self.pipelineState = pipelineState }
    func setViewport(_ viewport: MTLViewport) {}
    func setScissorRect(_ rect: MTLScissorRect) {}
    func setFrontFacing(_ frontFacingWinding: MTLWinding) {}
    func setCullMode(_ cullMode: MTLCullMode) {}
    func setTriangleFillMode(_ fillMode: MTLTriangleFillMode) {}
    func setDepthStencilState(_ depthStencilState: (any MTLDepthStencilState)?) {}
    func setBlendColor(red: Float, green: Float, blue: Float, alpha: Float) {}
    func setStencilReferenceValue(_ referenceValue: UInt32) {}
    func setVertexBuffer(_ buffer: (any MTLBuffer)?, offset: Int, index: Int) { if let b = buffer { vertexBuffers[index] = (b, offset) } else { vertexBuffers[index] = nil } }
    func setVertexBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int) {
        if let b = device.makeBuffer(bytes: bytes, length: length, options: []) { vertexBuffers[index] = (b, 0) }
    }
    func setVertexTexture(_ texture: (any MTLTexture)?, index: Int) {}
    func setVertexSamplerState(_ sampler: (any MTLSamplerState)?, index: Int) {}
    func setFragmentBuffer(_ buffer: (any MTLBuffer)?, offset: Int, index: Int) { if let b = buffer { fragmentBuffers[index] = (b, offset) } else { fragmentBuffers[index] = nil } }
    func setFragmentBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int) {
        if let b = device.makeBuffer(bytes: bytes, length: length, options: []) { fragmentBuffers[index] = (b, 0) }
    }
    func setFragmentTexture(_ texture: (any MTLTexture)?, index: Int) {}
    func setFragmentSamplerState(_ sampler: (any MTLSamplerState)?, index: Int) {}
    func drawPrimitives(type primitiveType: MTLPrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int) { buffer.recordDraw() }
    func drawIndexedPrimitives(type primitiveType: MTLPrimitiveType, indexCount: Int, indexType: MTLIndexType, indexBuffer: any MTLBuffer, indexBufferOffset: Int, instanceCount: Int) { buffer.recordDraw() }
}

final class MTLReferenceBlitCommandEncoder: MTLReferenceEncoder, MTLBlitCommandEncoder {
    func copy(from sourceBuffer: any MTLBuffer, sourceOffset: Int, to destinationBuffer: any MTLBuffer, destinationOffset: Int, size: Int) {
        buffer.work.append {
            let n = min(size, sourceBuffer.length - sourceOffset, destinationBuffer.length - destinationOffset)
            guard n > 0 else { return }
            destinationBuffer.contents().advanced(by: destinationOffset).copyMemory(from: sourceBuffer.contents().advanced(by: sourceOffset), byteCount: n)
        }
    }

    func copy(from sourceTexture: any MTLTexture, to destinationTexture: any MTLTexture) {
        copy(from: sourceTexture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: sourceTexture.width, height: sourceTexture.height, depth: 1),
             to: destinationTexture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
    }

    func copy(from sourceTexture: any MTLTexture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: MTLOrigin, sourceSize: MTLSize, to destinationTexture: any MTLTexture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: MTLOrigin) {
        buffer.work.append {
            let bpp = sourceTexture.pixelFormat.bytesPerPixel
            let rowBytes = sourceSize.width * bpp
            var scratch = [UInt8](repeating: 0, count: rowBytes * sourceSize.height)
            scratch.withUnsafeMutableBytes { buf in
                sourceTexture.getBytes(buf.baseAddress!, bytesPerRow: rowBytes, from: MTLRegion(origin: sourceOrigin, size: sourceSize), mipmapLevel: sourceLevel)
                destinationTexture.replace(region: MTLRegion(origin: destinationOrigin, size: sourceSize), mipmapLevel: destinationLevel, withBytes: buf.baseAddress!, bytesPerRow: rowBytes)
            }
        }
    }

    func copy(from sourceBuffer: any MTLBuffer, sourceOffset: Int, sourceBytesPerRow: Int, sourceBytesPerImage: Int, sourceSize: MTLSize, to destinationTexture: any MTLTexture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: MTLOrigin) {
        buffer.work.append {
            destinationTexture.replace(region: MTLRegion(origin: destinationOrigin, size: sourceSize), mipmapLevel: destinationLevel,
                                       withBytes: sourceBuffer.contents().advanced(by: sourceOffset), bytesPerRow: sourceBytesPerRow)
        }
    }

    func copy(from sourceTexture: any MTLTexture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: MTLOrigin, sourceSize: MTLSize, to destinationBuffer: any MTLBuffer, destinationOffset: Int, destinationBytesPerRow: Int, destinationBytesPerImage: Int) {
        buffer.work.append {
            sourceTexture.getBytes(destinationBuffer.contents().advanced(by: destinationOffset), bytesPerRow: destinationBytesPerRow,
                                   from: MTLRegion(origin: sourceOrigin, size: sourceSize), mipmapLevel: sourceLevel)
        }
    }

    func fill(buffer target: any MTLBuffer, range: Range<Int>, value: UInt8) {
        buffer.work.append {
            let r = range.clamped(to: 0..<target.length)
            target.contents().advanced(by: r.lowerBound).initializeMemory(as: UInt8.self, repeating: value, count: r.count)
        }
    }

    func generateMipmaps(for texture: any MTLTexture) {}
    func synchronize(resource: any MTLResource) {}
}

final class MTLReferenceComputeCommandEncoder: MTLReferenceEncoder, MTLComputeCommandEncoder {
    func setComputePipelineState(_ state: any MTLComputePipelineState) {}
    func setBuffer(_ buffer: (any MTLBuffer)?, offset: Int, index: Int) {}
    func setBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int) {}
    func setTexture(_ texture: (any MTLTexture)?, index: Int) {}
    func setSamplerState(_ sampler: (any MTLSamplerState)?, index: Int) {}
    func dispatchThreadgroups(_ threadgroupsPerGrid: MTLSize, threadsPerThreadgroup: MTLSize) {}
    func dispatchThreads(_ threadsPerGrid: MTLSize, threadsPerThreadgroup: MTLSize) {}
}

/// A drawable over a reference texture; `present()` hands the texture to the owner
/// (MTKView draws it through CoreGraphics).
public final class MTLReferenceDrawable: MTLDrawable {
    public let drawableID: Int
    public private(set) var presentedTime: TimeInterval = 0
    public let texture: any MTLTexture
    private var handlers: [(any MTLDrawable) -> Void] = []
    private let onPresent: (MTLReferenceDrawable) -> Void
    nonisolated(unsafe) private static var counter = 0

    public init(texture: any MTLTexture, onPresent: @escaping (MTLReferenceDrawable) -> Void) {
        MTLReferenceDrawable.counter += 1
        drawableID = MTLReferenceDrawable.counter
        self.texture = texture
        self.onPresent = onPresent
    }

    public func present() {
        presentedTime = ProcessInfo.processInfo.systemUptime
        onPresent(self)
        for h in handlers { h(self) }
    }

    public func present(atTime presentationTime: TimeInterval) { present() }
    public func addPresentedHandler(_ block: @escaping (any MTLDrawable) -> Void) { handlers.append(block) }
}
