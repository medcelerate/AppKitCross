// The Liquid Glass program on Linux (ADR-0052 stage 2): the glass_*.comp compute shaders
// as SPIR-V on the Vulkan shim of the Metal module (CMetalVulkan, ADR-0012), the whole
// program (box passes, saturation, luminance probe, lens) in one command list with one
// read-back of the shaded surface into the cairo image the window draws. The device is the
// one `MTLCreateSystemDefaultDevice` would pick (lavapipe in the container); no device, no
// Vulkan 1.3, or `APPKITWIN_METAL_REFERENCE=1` leaves the software pass in place.

#if os(Linux)
import Foundation
import CoreGraphics
@_implementationOnly import CMetalVulkan

@MainActor
final class LinuxGlassVulkanProgram: PlatformGlassProgram {
    private let device: OpaquePointer
    private let queue: OpaquePointer
    private let box: OpaquePointer, saturate: OpaquePointer, luminance: OpaquePointer, lens: OpaquePointer
    private var shaders: [OpaquePointer]
    /// Storage buffers reused between runs, grown when a run needs more.
    private var buffers: [Int: (buffer: OpaquePointer, length: Int)] = [:]
    let name: String
    var runsBackdropStage: Bool { true }
    var drawsInPlace: Bool { false }
    private(set) var lastLuminance: Float = -1

    private init(device: OpaquePointer, queue: OpaquePointer, shaders: [OpaquePointer], pipelines: [OpaquePointer], name: String) {
        self.device = device; self.queue = queue; self.shaders = shaders
        box = pipelines[0]; saturate = pipelines[1]; luminance = pipelines[2]; lens = pipelines[3]
        self.name = name
    }

    static func make() -> Result<any PlatformGlassProgram, _GlassProgramError> {
        if ProcessInfo.processInfo.environment["APPKITWIN_METAL_REFERENCE"] == "1" { return .failure(.init("Vulkan: APPKITWIN_METAL_REFERENCE=1")) }
        guard cmv_available() else { return .failure(.init("Vulkan: no loader")) }
        guard let device = cmv_device_create(false) else { return .failure(.init("Vulkan: " + String(cString: cmv_last_error()))) }
        guard let queue = cmv_queue_create(device) else { cmv_device_release(device); return .failure(.init("Vulkan: no queue")) }
        var shaders: [OpaquePointer] = [], pipelines: [OpaquePointer] = []
        func fail(_ message: String) -> Result<any PlatformGlassProgram, _GlassProgramError> {
            for p in pipelines { cmv_pipeline_release(p) }
            for s in shaders { cmv_shader_release(s) }
            cmv_queue_release(queue); cmv_device_release(device)
            return .failure(.init("Vulkan: " + message))
        }
        for words in [_GlassShaders.glassBoxSPIRV, _GlassShaders.glassSaturateSPIRV, _GlassShaders.glassLuminanceSPIRV, _GlassShaders.glassLensSPIRV] {
            var error = [CChar](repeating: 0, count: 512)
            let shader = words.withUnsafeBytes { cmv_shader_from_spirv(device, $0.baseAddress, UInt32($0.count), "main", 32, &error, UInt32(error.count)) }
            guard let shader else { return fail(String(cString: error)) }
            shaders.append(shader)
            guard let pipeline = cmv_compute_pipeline_create(device, shader, &error, UInt32(error.count)) else { return fail(String(cString: error)) }
            pipelines.append(pipeline)
        }
        var info = CMVDeviceInfo()
        cmv_device_info(device, &info)
        let deviceName = withUnsafeBytes(of: &info.name) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        return .success(LinuxGlassVulkanProgram(device: device, queue: queue, shaders: shaders, pipelines: pipelines, name: "Vulkan (\(deviceName))"))
    }

    /// The buffer for `slot`, at least `length` bytes.
    private func buffer(_ slot: Int, length: Int) -> OpaquePointer? {
        if let b = buffers[slot], b.length >= length { return b.buffer }
        if let b = buffers[slot] { cmv_buffer_release(b.buffer) }
        let size = max(256, length.nextPowerOfTwo)
        guard let b = cmv_buffer_create(device, UInt64(size)) else { buffers[slot] = nil; return nil }
        buffers[slot] = (b, size)
        return b
    }

    func render(_ backdrop: CGImage, request: PlatformGlassRequest) -> CGImage? {
        guard let up = _GlassUpload(backdrop) else { return nil }
        let w = request.parameters.width, h = request.parameters.height
        guard w > 0, h > 0, up.stride % 4 == 0 else { return nil }
        let bytes = up.stride * up.height
        let constants = request.constants(sampleWidth: up.width, sampleHeight: up.height)
        guard let a = buffer(0, length: bytes), let b = buffer(1, length: bytes), let o = buffer(2, length: w * h * 4),
              let k = buffer(3, length: constants.count * 4), let lum = buffer(4, length: 16),
              let passH = buffer(5, length: 32), let passV = buffer(6, length: 32),
              let list = cmv_commandlist_create(device) else { return nil }
        defer { cmv_commandlist_release(list) }
        up.bytes.withUnsafeBytes { _ = memcpy(cmv_buffer_map(a), $0.baseAddress!, bytes) }
        constants.withUnsafeBytes { _ = memcpy(cmv_buffer_map(k), $0.baseAddress!, $0.count) }
        cmv_buffer_map(lum).assumingMemoryBound(to: Float.self).pointee = -1
        let radius = UInt32(request.boxRadius)
        let pass: (UInt32) -> [UInt32] = { [UInt32(up.width), UInt32(up.height), UInt32(up.stride / 4), radius, $0, 0, 0, 0] }
        pass(1).withUnsafeBytes { _ = memcpy(cmv_buffer_map(passH), $0.baseAddress!, 32) }
        pass(0).withUnsafeBytes { _ = memcpy(cmv_buffer_map(passV), $0.baseAddress!, 32) }
        let groups = (UInt32((up.width + 7) / 8), UInt32((up.height + 7) / 8))
        cmv_commandlist_reset(list)
        func bind(_ slots: [(Int, OpaquePointer)]) { for (slot, buffer) in slots { cmv_commandlist_set_shader_buffer(list, 0, UInt32(slot), buffer, 0) } }
        bind([(2, k), (4, lum)])
        if request.luminance == nil {
            if radius > 0 {
                cmv_commandlist_set_pipeline(list, box)
                for _ in 0..<3 {
                    bind([(0, a), (1, b), (3, passH)]); cmv_commandlist_dispatch(list, groups.0, groups.1, 1)
                    bind([(0, b), (1, a), (3, passV)]); cmv_commandlist_dispatch(list, groups.0, groups.1, 1)
                }
            }
            bind([(1, a), (3, passV)])
            if request.saturation != 1 {
                cmv_commandlist_set_pipeline(list, saturate)
                cmv_commandlist_dispatch(list, groups.0, groups.1, 1)
            }
            cmv_commandlist_set_pipeline(list, luminance)
            cmv_commandlist_dispatch(list, 1, 1, 1)
        }
        bind([(0, a), (1, o), (3, passV)])
        cmv_commandlist_set_pipeline(list, lens)
        cmv_commandlist_dispatch(list, UInt32((w + 7) / 8), UInt32((h + 7) / 8), 1)
        let fence = cmv_commandlist_execute(list, queue)
        guard fence != 0 else { return nil }
        cmv_queue_wait(queue, fence)
        guard !cmv_device_lost(device) else { return nil }
        lastLuminance = cmv_buffer_map(lum).assumingMemoryBound(to: Float.self).pointee
        let out = [UInt8](UnsafeRawBufferPointer(start: cmv_buffer_map(o), count: w * h * 4))
        return _GlassUpload.image(bytes: out, width: w, height: h, template: backdrop)
    }

    func draw(_ backdrop: CGImage, request: PlatformGlassRequest, in rect: CGRect, of context: CGContext, flipped: Bool) -> Bool {
        drawRendered(backdrop, request: request, in: rect, of: context, flipped: flipped)
    }
}

private extension Int {
    var nextPowerOfTwo: Int { self <= 1 ? 1 : 1 << (Int.bitWidth - (self - 1).leadingZeroBitCount) }
}
#endif
