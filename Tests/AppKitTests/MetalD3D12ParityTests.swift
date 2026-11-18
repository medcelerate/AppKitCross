// The Direct3D 12 backend (ADR-0004) against the reference device, the way
// MetalVulkanParityTests checks the Vulkan backend: the same scene of clears in several
// formats, an upload, texture and buffer copies in every direction, a fill and a presented
// MTKView frame runs on both devices and every readback must match within one level per
// channel. Skips where the backend is absent (macOS, Linux); on Windows CI the device is
// WARP, on the test PC the GPU.

import XCTest
@testable import AppKit
import Metal
import MetalKit

final class MetalD3D12ParityTests: XCTestCase, @unchecked Sendable {
    func testSceneMatchesReferenceDevice() throws {
        let d3d12 = try MetalD3D12DeviceTests.d3d12Device()
        let reference = try MetalVulkanParityTests.runScene(on: MTLReferenceDevice())
        let onD3D12 = try MetalVulkanParityTests.runScene(on: d3d12)
        MetalVulkanParityTests.compare(reference, onD3D12, backend: "Direct3D 12")
        XCTAssertGreaterThanOrEqual(reference.count, 10)
    }

    func testMTKViewFrameMatchesReferenceDevice() throws {
        try requireHostBackend("needs the host backend's rendered window (APPKITWIN_HOST_BACKEND=1)")
        let d3d12 = try MetalD3D12DeviceTests.d3d12Device()
        let reference = try MetalVulkanParityTests.presentedMTKViewFrame(on: MTLReferenceDevice())
        MetalVulkanParityTests.compareFrames(reference, try MetalVulkanParityTests.presentedMTKViewFrame(on: d3d12), backend: "Direct3D 12")
    }
}

