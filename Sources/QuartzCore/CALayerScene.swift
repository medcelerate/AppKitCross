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
    public var size: CGSize
    public var opacity: Float
    /// Clips content and children to the node's rect, rounded by `cornerRadius` on `maskedCorners`.
    public var clipsToBounds: Bool
    public var cornerRadius: CGFloat
    public var maskedCorners: CACornerMask
    public var content: _CALayerSceneContent?
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
            return !CALayer.compositingOnlyKeys.contains(kp)
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
        if !_sublayerTransform.isIdentity { return true }
        return false
    }

    /// The local (points, y-down, origin top-left) → parent-local transform of a presentation.
    static func _nodeTransform(_ p: CALayer, parentFlipped: Bool, parentBounds: CGRect) -> CGAffineTransform {
        // Oriented bounds space of `p` → parent's oriented bounds space (as `_compose` sets up).
        let ax = p._bounds.minX + p._anchorPoint.x * p._bounds.width
        let ay = p._bounds.minY + p._anchorPoint.y * p._bounds.height
        var m = CGAffineTransform.identity
        if p._isGeometryFlipped != parentFlipped {
            m = CGAffineTransform(scaleX: 1, y: -1).concatenating(CGAffineTransform(translationX: 0, y: p._bounds.minY + p._bounds.maxY))
        }
        m = m.concatenating(CGAffineTransform(translationX: -ax, y: -ay))
            .concatenating(p._transform.affineTransform)
            .concatenating(CGAffineTransform(translationX: p._position.x, y: p._position.y))
        // Local y-down → oriented bounds space of `p`.
        let toSelf: CGAffineTransform = p._isGeometryFlipped
            ? CGAffineTransform(translationX: p._bounds.minX, y: p._bounds.minY)
            : CGAffineTransform(scaleX: 1, y: -1).concatenating(CGAffineTransform(translationX: p._bounds.minX, y: p._bounds.maxY))
        // Parent's oriented bounds space → parent local y-down.
        let fromParent: CGAffineTransform = parentFlipped
            ? CGAffineTransform(translationX: -parentBounds.minX, y: -parentBounds.minY)
            : CGAffineTransform(scaleX: 1, y: -1).concatenating(CGAffineTransform(translationX: -parentBounds.minX, y: parentBounds.maxY))
        return toSelf.concatenating(m).concatenating(fromParent)
    }

    /// Sets `ctx` (points, bottom-left origin, `size` extent) up as this layer's oriented bounds space.
    private func _enterBoundsSpace(_ ctx: CGContext, p: CALayer) {
        if p._isGeometryFlipped {
            ctx.translateBy(x: 0, y: p._bounds.height)
            ctx.scaleBy(x: 1, y: -1)
        }
        ctx.translateBy(x: -p._bounds.minX, y: -p._bounds.minY)
    }

    @MainActor
    private func _appendNodes(to scene: inout _CALayerScene, parent: Int?, parentFlipped: Bool, parentBounds: CGRect, time: CFTimeInterval, frame: Int) {
        hasPresentation = true
        let p = animations.isEmpty ? self : _presentation(at: time)
        guard !p._isHidden, p._opacity > 0 else { return }
        if _needsLayout { _needsLayout = false; layoutSublayers() }
        let transform = CALayer._nodeTransform(p, parentFlipped: parentFlipped, parentBounds: parentBounds)
        let index = scene.nodes.count
        var node = _CALayerSceneNode(id: CALayer._nodeID(self, part: 0), parent: parent, transform: transform, size: p._bounds.size,
                                     opacity: p._opacity, clipsToBounds: p._masksToBounds, cornerRadius: p._cornerRadius,
                                     maskedCorners: p.maskedCorners, content: nil, name: name)

        if _needsFlattening {
            // One surface for the whole subtree, drawn by the software compositor.
            let version = _subtreeAnimates ? frame : _treeVersion
            node.content = _CALayerSceneContent(version: version) { [self] ctx in
                _enterBoundsSpace(ctx, p: p)
                render(in: ctx)
            }
            node.clipsToBounds = false       // the compositor already applied masksToBounds
            node.opacity = 1                 // and the opacity
            scene.nodes.append(node)
            return
        }

        let hasOwnContent = p._backgroundColor != nil || _contents != nil || delegate != nil || !(type(of: self) == CALayer.self || self is CATransformLayer)
        if hasOwnContent {
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
            s._appendNodes(to: &scene, parent: index, parentFlipped: p._isGeometryFlipped, parentBounds: p._bounds, time: time, frame: frame)
        }
        for extra in CALayer._sceneExtraChildren?(self) ?? [] {
            extra._appendNodes(to: &scene, parent: index, parentFlipped: p._isGeometryFlipped, parentBounds: p._bounds, time: time, frame: frame)
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
