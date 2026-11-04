// MetalKit: MTKView over AppKit's NSView and the Core Animation frame clock.
// With the reference device the presented drawable is drawn through CoreGraphics, so a
// cleared (or CPU-filled) texture shows on every platform. On Windows, in a window whose
// layer tree DirectComposition hosts, the Direct3D 12 device renders into a flip-model DXGI
// swap chain that is the content of the view's layer visual (`CAMetalLayer`); anywhere
// else (the host backend, software layers) a GPU drawable is read back and drawn.

import Foundation
import AppKit
import QuartzCore
import Metal

/// - SeeAlso: https://developer.apple.com/documentation/metalkit/mtkviewdelegate
@MainActor
public protocol MTKViewDelegate: AnyObject {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize)
    func draw(in view: MTKView)
}

/// - SeeAlso: https://developer.apple.com/documentation/metalkit/mtkview
@MainActor open class MTKView: NSView {
    private var _device: (any MTLDevice)?
    private var _drawableSize = CGSize.zero
    private var _currentDrawable: (any MTLDrawable)?
    private var _currentTexture: (any MTLTexture)?
    #if os(Windows)
    private var _swapChain: MTLD3D12SwapChain?
    #endif
    private var _presented: (any MTLTexture)?
    private var _displayLink: CADisplayLink?
    private var _depthTexture: (any MTLTexture)?
    private var _needsPresentImage = false
    private var _frameCount = 0

    open weak var delegate: (any MTKViewDelegate)?
    open var colorPixelFormat: MTLPixelFormat = .bgra8Unorm { didSet { _dropTextures() } }
    open var depthStencilPixelFormat: MTLPixelFormat = .invalid { didSet { _dropTextures() } }
    open var sampleCount = 1
    open var clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    open var clearDepth: Double = 1
    open var clearStencil: UInt32 = 0
    open var preferredFramesPerSecond = 60 { didSet { _displayLink?.preferredFramesPerSecond = preferredFramesPerSecond } }
    open var framebufferOnly = true
    open var autoResizeDrawable = true
    open var presentsWithTransaction = false
    /// When true the view redraws only on `setNeedsDisplay`/`draw()`.
    open var enableSetNeedsDisplay = false { didSet { _updateLink() } }
    open var isPaused = false { didSet { _updateLink() } }

    public init(frame frameRect: NSRect, device: (any MTLDevice)?) {
        _device = device ?? MTLCreateSystemDefaultDevice()
        super.init(frame: frameRect)
        wantsLayer = true
        _drawableSize = CGSize(width: frameRect.width, height: frameRect.height)
    }

    public convenience override init(frame frameRect: NSRect) { self.init(frame: frameRect, device: nil) }
    public required init?(coder: NSCoder) { return nil }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/makebackinglayer()
    open override func makeBackingLayer() -> CALayer { CAMetalLayer() }

    /// True while frames go straight to a DXGI swap chain shown by the window's
    /// DirectComposition tree (Windows); false on the CoreGraphics readback path.
    /// Not part of Apple's API (tooling and tests).
    public var _presentsThroughSwapChain: Bool {
        #if os(Windows)
        return _swapChain != nil
        #else
        return false
        #endif
    }

    #if os(Windows)
    /// The swap chain sized to the drawable, while the window hosts its layers natively and
    /// the device is Direct3D 12; otherwise nil, any chain dropped, and frames are read back.
    private func _ensureSwapChain() -> MTLD3D12SwapChain? {
        guard let d3d = _device as? MTLD3D12Device, let w = window, w._hostsLayersNatively, let l = layer else {
            _dropSwapChain()
            return nil
        }
        let width = max(1, Int(_drawableSize.width)), height = max(1, Int(_drawableSize.height))
        if let sc = _swapChain, sc.pixelFormat == colorPixelFormat {
            if (sc.width != width || sc.height != height), !sc.resize(width: width, height: height) {
                _dropSwapChain()
                return nil
            }
            return sc
        }
        _dropSwapChain()
        guard let sc = MTLD3D12SwapChain(device: d3d, width: width, height: height, pixelFormat: colorPixelFormat, opaque: true) else { return nil }
        _swapChain = sc
        l._nativeContent = sc.nativeHandle
        _presented = nil
        return sc
    }

    private func _dropSwapChain() {
        guard _swapChain != nil else { return }
        _swapChain = nil
        layer?._nativeContent = nil
        needsDisplay = true
    }
    #endif

    open var device: (any MTLDevice)? {
        get { _device }
        set { _device = newValue; _dropTextures() }
    }

    open override var isFlipped: Bool { true }

    /// - SeeAlso: https://developer.apple.com/documentation/metalkit/mtkview/drawablesize
    open var drawableSize: CGSize {
        get { _drawableSize }
        set {
            guard newValue != _drawableSize else { return }
            _drawableSize = newValue
            _dropTextures()
            delegate?.mtkView(self, drawableSizeWillChange: newValue)
        }
    }

    private func _dropTextures() {
        _currentDrawable = nil
        _currentTexture = nil
        _depthTexture = nil
    }

    private func _makeTexture(_ format: MTLPixelFormat, usage: MTLTextureUsage) -> (any MTLTexture)? {
        guard let d = _device, format != .invalid else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: max(1, Int(_drawableSize.width)), height: max(1, Int(_drawableSize.height)), mipmapped: false)
        desc.usage = usage
        desc.storageMode = .private
        return d.makeTexture(descriptor: desc)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/metalkit/mtkview/currentdrawable
    open var currentDrawable: (any MTLDrawable)? {
        if let d = _currentDrawable { return d }
        #if os(Windows)
        if let sc = _ensureSwapChain() {
            guard let d = sc.nextDrawable() else { return nil }
            _currentTexture = d.texture
            _currentDrawable = d
            return d
        }
        #endif
        guard let tex = _makeTexture(colorPixelFormat, usage: [.renderTarget, .shaderRead]) else { return nil }
        _currentTexture = tex
        let d = MTLReferenceDrawable(texture: tex) { [weak self] drawable in
            MainActor.assumeIsolated {
                guard let self else { return }
                self._presented = drawable.texture
                self._needsPresentImage = true
                self.needsDisplay = true
            }
        }
        _currentDrawable = d
        return d
    }

    /// The drawable's texture (the reference drawable exposes it directly).
    open var currentTexture: (any MTLTexture)? { _ = currentDrawable; return _currentTexture }

    /// - SeeAlso: https://developer.apple.com/documentation/metalkit/mtkview/depthstenciltexture
    open var depthStencilTexture: (any MTLTexture)? {
        if _depthTexture == nil { _depthTexture = _makeTexture(depthStencilPixelFormat, usage: .renderTarget) }
        return _depthTexture
    }

    /// - SeeAlso: https://developer.apple.com/documentation/metalkit/mtkview/currentrenderpassdescriptor
    open var currentRenderPassDescriptor: MTLRenderPassDescriptor? {
        guard let tex = currentTexture else { return nil }
        let d = MTLRenderPassDescriptor()
        d.colorAttachments[0].texture = tex
        d.colorAttachments[0].loadAction = .clear
        d.colorAttachments[0].storeAction = .store
        d.colorAttachments[0].clearColor = clearColor
        if let depth = depthStencilTexture {
            d.depthAttachment.texture = depth
            d.depthAttachment.loadAction = .clear
            d.depthAttachment.storeAction = .dontCare
            d.depthAttachment.clearDepth = clearDepth
        }
        return d
    }

    /// Frames so far (for tests and tooling).
    public var frameCount: Int { _frameCount }

    // MARK: Drawing

    /// Runs one frame: asks the delegate (or `draw(_:)` overrides) to render and releases
    /// the drawable for the next frame.
    open func draw() {
        _frameCount += 1
        if let d = delegate { d.draw(in: self) }
        _currentDrawable = nil
        _currentTexture = nil
    }

    open override func draw(_ dirtyRect: NSRect) {
        if !_needsPresentImage && delegate != nil && (enableSetNeedsDisplay || isPaused) {
            draw()
        }
        _needsPresentImage = false
        guard let tex = _presented, tex.pixelFormat.bytesPerPixel == 4, let gc = NSGraphicsContext.current else {
            NSColor(red: CGFloat(clearColor.red), green: CGFloat(clearColor.green), blue: CGFloat(clearColor.blue), alpha: CGFloat(clearColor.alpha)).setFill()
            NSBezierPath(rect: bounds).fill()
            return
        }
        // Present any 32-bit drawable texture through CoreGraphics (reference device, or a
        // GPU device read back; BGRA premultiplied expected, RGBA swizzled).
        let rowBytes = tex.width * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * tex.height)
        bytes.withUnsafeMutableBytes { buf in
            tex.getBytes(buf.baseAddress!, bytesPerRow: rowBytes, from: MTLRegionMake2D(0, 0, tex.width, tex.height), mipmapLevel: 0)
        }
        if tex.pixelFormat == .rgba8Unorm || tex.pixelFormat == .rgba8Unorm_srgb {
            for i in stride(from: 0, to: bytes.count, by: 4) { bytes.swapAt(i, i + 2) }
        }
        guard let image = MTKView._makeImage(width: tex.width, height: tex.height, stride: rowBytes, data: Data(bytes)) else { return }
        let ctx = gc.cgContext
        ctx.saveGState()
        // The view is flipped; CGContext.draw expects a y-up rect, so mirror within bounds.
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: NSRect(origin: .zero, size: bounds.size))
        ctx.restoreGState()
    }

    open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        _resizeDrawable(to: newSize)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/viewdidchangebackingproperties()
    open override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        _resizeDrawable(to: bounds.size)
    }

    /// Follows the view's size and the window's backing scale, then renders a frame at the
    /// new size at once when presenting through a swap chain, so a resize never shows a
    /// stretched or stale frame.
    private func _resizeDrawable(to size: NSSize) {
        guard autoResizeDrawable else { return }
        let scale = window?.backingScaleFactor ?? 1
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        guard newSize != _drawableSize else { return }
        drawableSize = newSize
        #if os(Windows)
        if _swapChain != nil, !isPaused, delegate != nil { draw() }
        #endif
    }

    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        #if os(Windows)
        // Presentation through DirectComposition needs the whole window layer-backed, as it
        // is on macOS; a window that stays in software still shows read-back frames.
        if _device is MTLD3D12Device, let cv = window?.contentView, !cv.wantsLayer { cv.wantsLayer = true }
        #endif
        if autoResizeDrawable, let w = window {
            drawableSize = CGSize(width: bounds.width * w.backingScaleFactor, height: bounds.height * w.backingScaleFactor)
        }
        _updateLink()
    }

    private func _updateLink() {
        let wantsLink = window != nil && !isPaused && !enableSetNeedsDisplay
        if wantsLink {
            if _displayLink == nil {
                let link = displayLink(target: self, selector: Selector(("_tick:")))
                link.preferredFramesPerSecond = preferredFramesPerSecond
                link.add(to: .main, forMode: .default)
                _displayLink = link
            }
        } else {
            _displayLink?.invalidate()
            _displayLink = nil
        }
    }

    deinit {
        MainActor.assumeIsolated {
            _displayLink?.invalidate()
            #if os(Windows)
            layer?._nativeContent = nil
            #endif
        }
    }
}

extension MTKView: NSSelectorHandling {
    public func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        guard action == Selector(("_tick:")) else { return false }
        draw()
        return true
    }
}

extension MTKView {
    /// A CGImage over premultiplied BGRA pixels (top row first).
    static func _makeImage(width: Int, height: Int, stride: Int, data: Data) -> CGImage? {
        #if os(Windows) || os(Linux)
        return CGImage.fromBGRA(width: width, height: height, stride: stride, data: data)
        #else
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: stride,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        #endif
    }

    /// The last presented texture, if any.
    public var presentedTexture: (any MTLTexture)? { _presented }
}
