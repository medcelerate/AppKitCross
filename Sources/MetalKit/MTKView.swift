// MetalKit: MTKView over AppKit's NSView and the Core Animation frame clock.
// With the reference device the presented drawable is drawn through CoreGraphics, so a
// cleared (or CPU-filled) texture shows on every platform; GPU devices present through
// their swap chain.

import Foundation
import AppKit
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
    private var _currentDrawable: MTLReferenceDrawable?
    private var _currentTexture: (any MTLTexture)?
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
        guard let tex = _presented as? MTLReferenceTexture, let gc = NSGraphicsContext.current else {
            NSColor(red: CGFloat(clearColor.red), green: CGFloat(clearColor.green), blue: CGFloat(clearColor.blue), alpha: CGFloat(clearColor.alpha)).setFill()
            NSBezierPath(rect: bounds).fill()
            return
        }
        // Present the reference texture through CoreGraphics (BGRA premultiplied expected).
        var bytes = [UInt8](repeating: 0, count: tex.bytesPerRow * tex.height)
        bytes.withUnsafeMutableBytes { buf in
            tex.getBytes(buf.baseAddress!, bytesPerRow: tex.bytesPerRow, from: MTLRegionMake2D(0, 0, tex.width, tex.height), mipmapLevel: 0)
        }
        if tex.pixelFormat == .rgba8Unorm || tex.pixelFormat == .rgba8Unorm_srgb {
            for i in stride(from: 0, to: bytes.count, by: 4) { bytes.swapAt(i, i + 2) }
        }
        guard let image = MTKView._makeImage(width: tex.width, height: tex.height, stride: tex.bytesPerRow, data: Data(bytes)) else { return }
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
        if autoResizeDrawable {
            let scale = window?.backingScaleFactor ?? 1
            drawableSize = CGSize(width: newSize.width * scale, height: newSize.height * scale)
        }
    }

    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
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
        MainActor.assumeIsolated { _displayLink?.invalidate() }
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
