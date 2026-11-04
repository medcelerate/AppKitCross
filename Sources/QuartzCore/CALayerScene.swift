// A layer tree flattened for a native compositor (DirectComposition on Windows). Not part
// of Apple's API: this is the seam between QuartzCore and the platform. The scene is
// retained-mode: the platform keeps one visual per node id and re-rasterises a node's
// content only when its `version` changes. Everything the software compositor cannot
// express as a visual (masks, shadows, sublayer transforms) is flattened into one node.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Drawable content of a scene node. `draw` receives a context whose space is points with
/// a bottom-left origin and `size` extent (the same convention as window drawing); the
/// node's pixels are `size` times the scene scale.
public struct _CALayerSceneContent {
    public let version: Int
    public let draw: @MainActor (CGContext) -> Void
    public init(version: Int, draw: @escaping @MainActor (CGContext) -> Void) {
        self.version = version
        self.draw = draw
    }
}

/// One visual. `transform` maps the node's local space (points, y-down, origin at its
/// top-left) into the parent's local space; the root's parent is the window's content
/// area (points, y-down). Nodes come in pre-order, so a parent precedes its children, and
/// children are already in back-to-front order.
public struct _CALayerSceneNode {
    /// Stable across scenes for the same layer (derived from its identity).
    public var id: Int
    public var parent: Int?
    public var transform: CGAffineTransform
    /// The full local → parent-local matrix when it is not affine (a 3D rotation, a
    /// perspective sublayerTransform). `transform` then holds the affine approximation for
    /// hosts without 3D compositing; a host that has it applies this instead.
    public var transform3D: CATransform3D? = nil
    public var size: CGSize
    public var opacity: Float
    /// Clips content and children to the node's rect, rounded by `cornerRadius` on `maskedCorners`.
    public var clipsToBounds: Bool
    public var cornerRadius: CGFloat
    public var maskedCorners: CACornerMask
    public var content: _CALayerSceneContent?
    /// Content the compositor shows directly instead of a rasterised surface: on Windows an
    /// `IDXGISwapChain1` (a `CAMetalLayer` presenting through DirectComposition). The node's
    /// own `content` is nil then; children still composite above it.
    public var nativeContent: UnsafeMutableRawPointer?
    public var name: String?
}

public struct _CALayerScene {
    public var nodes: [_CALayerSceneNode] = []
    /// Backing scale: content rasterises at `size * scale` pixels.
    public var scale: CGFloat = 1
    public var contentSize: CGSize = .zero
    public init() {}
}

extension CALayer {
    /// Returns the sublayers plus any layers a host attaches below this one outside the
    /// layer tree (AppKit views that host a foreign layer). Installed by the host.
    @MainActor public static var _sceneExtraChildren: ((CALayer) -> [CALayer])?

    /// Flattens this tree into a scene. `parentFlipped`/`parentBounds` describe the space the
    /// root is positioned in (for a window: unflipped, the content rect at origin zero).
    /// `frame` is a counter that makes animating rasters re-draw every commit.
    @MainActor
    public func _buildScene(parentFlipped: Bool, parentBounds: CGRect, scale: CGFloat, frame: Int) -> _CALayerScene {
        var scene = _CALayerScene()
        scene.scale = scale
        scene.contentSize = parentBounds.size
        _appendNodes(to: &scene, parent: nil, parentFlipped: parentFlipped, parentBounds: parentBounds, time: CARuntime.now(), frame: frame)
        return scene
    }

    private static func _nodeID(_ layer: CALayer, part: Int) -> Int {
        Int(bitPattern: UInt(bitPattern: ObjectIdentifier(layer))) &+ part
    }

    /// True when the layer's own rasterised content is animating (so it must redraw each frame).
    private var _rasterAnimates: Bool {
        func animates(_ a: CAAnimation) -> Bool {
            if let g = a as? CAAnimationGroup { return (g.animations ?? []).contains(where: animates) }
            guard let kp = (a as? CAPropertyAnimation)?.keyPath else { return true }
            // "transform.scale", "position.x": the property is the first path component.
            let property = kp.split(separator: ".", maxSplits: 1).first.map(String.init) ?? kp
            return !CALayer.compositingOnlyKeys.contains(property)
        }
        return animations.contains { animates($0.animation) }
    }

    private var _subtreeAnimates: Bool {
        if !animations.isEmpty { return true }
        if let m = _mask, m._subtreeAnimates { return true }
        return _sublayers.contains { $0._subtreeAnimates }
    }

    /// Whether this layer must be rendered through the software compositor as one surface.
    private var _needsFlattening: Bool {
        if _mask != nil { return true }
        if _shadowOpacity > 0 && _shadowColor != nil { return true }
        return false
    }

    /// The local (points, y-down, origin top-left) → parent-local transform of a presentation,
    /// including the parent's sublayerTransform (applied about the parent's anchor point, as
    /// the software compositor does). Affine inputs give an affine result exactly.
    /// With `affineOnly`, the 3D factors contribute their affine parts, as the software
    /// compositor draws them: the approximation a 2D-only host shows.
    static func _nodeTransform(_ p: CALayer, parentFlipped: Bool, parentBounds: CGRect,
                               parentSublayerTransform: CATransform3D, parentAnchor: CGPoint, affineOnly: Bool = false) -> CATransform3D {
        func m3(_ m: CGAffineTransform) -> CATransform3D { CATransform3DMakeAffineTransform(m) }
        func factor(_ t: CATransform3D) -> CATransform3D { affineOnly ? m3(t.affineTransform) : t }
        // Oriented bounds space of `p` → parent's oriented bounds space (as `_compose` sets up).
        let ax = p._bounds.minX + p._anchorPoint.x * p._bounds.width
        let ay = p._bounds.minY + p._anchorPoint.y * p._bounds.height
        var m = CATransform3DIdentity
        if p._isGeometryFlipped != parentFlipped {
            m = m3(CGAffineTransform(scaleX: 1, y: -1).concatenating(CGAffineTransform(translationX: 0, y: p._bounds.minY + p._bounds.maxY)))
        }
        m = m.concatenating(m3(CGAffineTransform(translationX: -ax, y: -ay)))
            .concatenating(factor(p._transform))
            .concatenating(m3(CGAffineTransform(translationX: p._position.x, y: p._position.y)))
        if !parentSublayerTransform.isIdentity {
            let px = parentBounds.minX + parentAnchor.x * parentBounds.width
            let py = parentBounds.minY + parentAnchor.y * parentBounds.height
            m = m.concatenating(m3(CGAffineTransform(translationX: -px, y: -py)))
                .concatenating(factor(parentSublayerTransform))
                .concatenating(m3(CGAffineTransform(translationX: px, y: py)))
        }
        // Local y-down → oriented bounds space of `p`.
        let toSelf: CGAffineTransform = p._isGeometryFlipped
            ? CGAffineTransform(translationX: p._bounds.minX, y: p._bounds.minY)
            : CGAffineTransform(scaleX: 1, y: -1).concatenating(CGAffineTransform(translationX: p._bounds.minX, y: p._bounds.maxY))
        // Parent's oriented bounds space → parent local y-down.
        let fromParent: CGAffineTransform = parentFlipped
            ? CGAffineTransform(translationX: -parentBounds.minX, y: -parentBounds.minY)
            : CGAffineTransform(scaleX: 1, y: -1).concatenating(CGAffineTransform(translationX: -parentBounds.minX, y: parentBounds.maxY))
        return m3(toSelf).concatenating(m).concatenating(m3(fromParent))
    }

    /// Sets `ctx` (points, bottom-left origin, `rect.size` extent) up as this layer's
    /// oriented bounds space, with `rect` (that space) filling the context.
    private func _enterBoundsSpace(_ ctx: CGContext, p: CALayer, rect: CGRect? = nil) {
        let r = rect ?? p._bounds
        if p._isGeometryFlipped {
            ctx.translateBy(x: 0, y: r.height)
            ctx.scaleBy(x: 1, y: -1)
        }
        ctx.translateBy(x: -r.minX, y: -r.minY)
    }

    @MainActor
    private func _appendNodes(to scene: inout _CALayerScene, parent: Int?, parentFlipped: Bool, parentBounds: CGRect, time: CFTimeInterval, frame: Int,
                              parentSublayerTransform: CATransform3D = CATransform3DIdentity, parentAnchor: CGPoint = .zero) {
        hasPresentation = true
        let p = animations.isEmpty ? self : _presentation(at: time)
        guard !p._isHidden, p._opacity > 0 else { return }
        if _needsLayout { _needsLayout = false; layoutSublayers() }
        let full = CALayer._nodeTransform(p, parentFlipped: parentFlipped, parentBounds: parentBounds,
                                          parentSublayerTransform: parentSublayerTransform, parentAnchor: parentAnchor)
        let transform = full.isAffine ? full.affineTransform
            : CALayer._nodeTransform(p, parentFlipped: parentFlipped, parentBounds: parentBounds,
                                     parentSublayerTransform: parentSublayerTransform, parentAnchor: parentAnchor, affineOnly: true).affineTransform
        let index = scene.nodes.count
        var node = _CALayerSceneNode(id: CALayer._nodeID(self, part: 0), parent: parent, transform: transform, size: p._bounds.size,
                                     opacity: p._opacity, clipsToBounds: p._masksToBounds, cornerRadius: p._cornerRadius,
                                     maskedCorners: p.maskedCorners, content: nil, name: name)
        if !full.isAffine { node.transform3D = full }

        if _needsFlattening {
            // One surface for the whole subtree, drawn by the software compositor. It covers
            // everything the raster reaches (sublayers outside the bounds, the shadow), so
            // the node is placed at that rect's corner rather than the bounds'.
            let extent = _flattenedExtent(presentation: p)
            let b = p._bounds
            let offset = CGPoint(x: extent.minX - b.minX, y: p._isGeometryFlipped ? extent.minY - b.minY : b.maxY - extent.maxY)
            node.transform = CGAffineTransform(translationX: offset.x, y: offset.y).concatenating(transform)
            if !full.isAffine { node.transform3D = CATransform3DMakeAffineTransform(CGAffineTransform(translationX: offset.x, y: offset.y)).concatenating(full) }
            node.size = extent.size
            let version = _subtreeAnimates ? frame : _treeVersion
            node.content = _CALayerSceneContent(version: version) { [self] ctx in
                _enterBoundsSpace(ctx, p: p, rect: extent)
                render(in: ctx)
            }
            node.clipsToBounds = false       // the compositor already applied masksToBounds
            node.opacity = 1                 // and the opacity
            scene.nodes.append(node)
            return
        }

        let hasOwnContent = p._backgroundColor != nil || _contents != nil || delegate != nil || !(type(of: self) == CALayer.self || self is CATransformLayer)
        if let native = _nativeContent {
            node.nativeContent = native
        } else if hasOwnContent {
            let version = _rasterAnimates ? frame : _rasterVersion
            node.content = _CALayerSceneContent(version: version) { [self] ctx in
                _enterBoundsSpace(ctx, p: p)
                _drawOwnContent(into: ctx, presentation: p)
            }
        }
        scene.nodes.append(node)

        let subs = p._sublayers.isEmpty ? _sublayers : p._sublayers
        let ordered = subs.enumerated().sorted { l, r in
            l.element._zPosition != r.element._zPosition ? l.element._zPosition < r.element._zPosition : l.offset < r.offset
        }.map(\.element)
        for s in ordered {
            s._appendNodes(to: &scene, parent: index, parentFlipped: p._isGeometryFlipped, parentBounds: p._bounds, time: time, frame: frame,
                           parentSublayerTransform: p._sublayerTransform, parentAnchor: p._anchorPoint)
        }
        for extra in CALayer._sceneExtraChildren?(self) ?? [] {
            extra._appendNodes(to: &scene, parent: index, parentFlipped: p._isGeometryFlipped, parentBounds: p._bounds, time: time, frame: frame,
                               parentSublayerTransform: p._sublayerTransform, parentAnchor: p._anchorPoint)
        }

        if p._borderWidth > 0, p._borderColor != nil {
            // The border sits above the sublayers: its own node, last among the children.
            let border = _CALayerSceneNode(id: CALayer._nodeID(self, part: 1), parent: index, transform: .identity, size: p._bounds.size,
                                           opacity: 1, clipsToBounds: false, cornerRadius: 0, maskedCorners: [],
                                           content: _CALayerSceneContent(version: _rasterAnimates ? frame : _borderVersion) { ctx in
                                               p._enterBoundsSpace(ctx, p: p)
                                               p._drawBorder(into: ctx)
                                           }, name: name.map { "\($0).border" })
            scene.nodes.append(border)
        }
    }
}
