// Client-side window decorations: the geometry a backend needs when the window system
// draws no frame around a toplevel (Wayland compositors without xdg-decoration, or ones
// that answer "client side"). The surface is the window's frame plus a shadow margin on
// every side; the title band sits at the top of the frame and the content below it.
// Everything here is pure geometry in points so it is testable on every platform; the
// drawing happens in `NSWindow` (the band and its buttons) and the backend (shadow and
// border), the moves and resizes go to the compositor.
//
// Coordinates: "surface" points have their origin at the top-left of the surface, y
// down (what a Wayland pointer reports); "window" points are AppKit window coordinates
// (origin at the frame's bottom-left, y up), in which the content view sits at (0, 0)
// and the band above it.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Who decorates a toplevel.
enum ClientSideDecorationMode: Equatable {
    /// Nothing: borderless windows, menus and other pop-ups.
    case none
    /// The window system draws the frame (xdg-decoration granted server side).
    case server
    /// The package draws the frame (the compositor has no xdg-decoration, or answered client side).
    case client

    /// The mode for a window: titled windows get a frame, from the server when it offers one.
    /// `serverSideGranted` is the compositor's answer, nil when it has no decoration protocol.
    static func mode(for styleMask: NSWindow.StyleMask, serverSideGranted: Bool?) -> ClientSideDecorationMode {
        guard styleMask.contains(.titled), !styleMask.contains(.nonactivatingPanel) else { return .none }
        return serverSideGranted == true ? .server : .client
    }
}

/// The edge or corner a resize grabs. Raw values are `xdg_toplevel.resize_edge`.
enum ClientSideDecorationResizeEdge: UInt32, Equatable, CaseIterable {
    case top = 1, bottom = 2, left = 4, topLeft = 5, bottomLeft = 6, right = 8, topRight = 9, bottomRight = 10

    /// XCursor names for the edge, most specific first (the backend takes the first its theme has).
    var cursorNames: [String] {
        switch self {
        case .top, .bottom: return ["ns-resize", "sb_v_double_arrow", "size_ver", "row-resize"]
        case .left, .right: return ["ew-resize", "sb_h_double_arrow", "size_hor", "col-resize"]
        case .topLeft, .bottomRight: return ["nwse-resize", "size_fdiag", "top_left_corner", "bd_double_arrow"]
        case .topRight, .bottomLeft: return ["nesw-resize", "size_bdiag", "top_right_corner", "fd_double_arrow"]
        }
    }
}

/// What a surface point is on.
enum ClientSideDecorationRegion: Equatable {
    /// Transparent shadow that is not a resize handle: the pointer is not on the window.
    case outside
    case resize(ClientSideDecorationResizeEdge)
    /// The package-drawn title band (its buttons are hit-tested by the window itself).
    case titleBar
    case content
}

/// The surface layout of one client-decorated toplevel.
struct ClientSideDecorationLayout: Equatable {
    /// The title band's height: AppKit's 28 points. 0 when the content covers the band
    /// (`fullSizeContentView`), when the mode is not `.client`, and in full screen.
    var titleBarHeight: CGFloat = 0
    /// Transparent margin around the frame for the shadow (and resize handles). 0 when the
    /// compositor tiles, maximises or fullscreens the window: the frame then fills its slot.
    var shadowMargin: CGFloat = 0
    /// The border line drawn just inside the frame.
    var borderWidth: CGFloat = 0
    var cornerRadius: CGFloat = 0
    /// Whether the frame edges and the shadow margin act as resize handles.
    var isResizable = false
    /// The frame (window geometry) in points: title band plus content.
    var frameSize: NSSize

    static let titleBandHeight: CGFloat = 28
    static let defaultShadowMargin: CGFloat = 24
    /// Resize handle depth inside the frame edge, and outside it in the shadow.
    static let innerGrip: CGFloat = 5
    static let outerGrip: CGFloat = 10
    /// How far from a corner an edge hit widens into a corner hit.
    static let cornerGrip: CGFloat = 18

    init(mode: ClientSideDecorationMode, styleMask: NSWindow.StyleMask, contentCoversTitleBar: Bool,
         tiledOrMaximized: Bool, fullScreen: Bool, frameSize: NSSize) {
        self.frameSize = frameSize
        guard mode == .client, !fullScreen else { return }
        titleBarHeight = contentCoversTitleBar ? 0 : ClientSideDecorationLayout.titleBandHeight
        shadowMargin = tiledOrMaximized ? 0 : ClientSideDecorationLayout.defaultShadowMargin
        borderWidth = 1
        cornerRadius = tiledOrMaximized ? 0 : 8
        isResizable = styleMask.contains(.resizable)
    }

    /// A layout with no decorations at all (server-side, borderless).
    init(frameSize: NSSize) { self.frameSize = frameSize }

    /// Content plus band for a content size, and back.
    static func frameSize(forContentSize size: NSSize, titleBarHeight: CGFloat) -> NSSize {
        NSSize(width: size.width, height: size.height + titleBarHeight)
    }
    static func contentSize(forFrameSize size: NSSize, titleBarHeight: CGFloat) -> NSSize {
        NSSize(width: size.width, height: max(0, size.height - titleBarHeight))
    }

    var contentSize: NSSize { ClientSideDecorationLayout.contentSize(forFrameSize: frameSize, titleBarHeight: titleBarHeight) }
    var surfaceSize: NSSize { NSSize(width: frameSize.width + 2 * shadowMargin, height: frameSize.height + 2 * shadowMargin) }
    /// The frame within the surface (`xdg_surface.set_window_geometry`), surface coordinates.
    var windowGeometry: NSRect { NSRect(x: shadowMargin, y: shadowMargin, width: frameSize.width, height: frameSize.height) }
    /// Where pointer input belongs to the window (`wl_surface.set_input_region`): the frame,
    /// widened into the shadow where it resizes.
    var inputRegion: NSRect { isResizable ? windowGeometry.insetBy(dx: -ClientSideDecorationLayout.outerGrip, dy: -ClientSideDecorationLayout.outerGrip) : windowGeometry }
    /// The band in window coordinates (empty when the content covers it).
    var titleBarRect: NSRect { NSRect(x: 0, y: contentSize.height, width: frameSize.width, height: titleBarHeight) }
    var hasDecorations: Bool { borderWidth > 0 || shadowMargin > 0 || titleBarHeight > 0 }

    func windowPoint(fromSurface p: NSPoint) -> NSPoint {
        NSPoint(x: p.x - shadowMargin, y: shadowMargin + frameSize.height - p.y)
    }
    func surfacePoint(fromWindow p: NSPoint) -> NSPoint {
        NSPoint(x: p.x + shadowMargin, y: shadowMargin + frameSize.height - p.y)
    }

    /// Classifies a surface point.
    func hitTest(_ p: NSPoint) -> ClientSideDecorationRegion {
        let f = windowGeometry
        if isResizable {
            guard inputRegion.contains(p) else { return .outside }
            let inner = ClientSideDecorationLayout.innerGrip, corner = ClientSideDecorationLayout.cornerGrip
            var horizontal: Int = p.x < f.minX + inner ? -1 : p.x > f.maxX - inner ? 1 : 0
            var vertical: Int = p.y < f.minY + inner ? -1 : p.y > f.maxY - inner ? 1 : 0
            if horizontal != 0 || vertical != 0 {
                if horizontal == 0 { horizontal = p.x < f.minX + corner ? -1 : p.x > f.maxX - corner ? 1 : 0 }
                if vertical == 0 { vertical = p.y < f.minY + corner ? -1 : p.y > f.maxY - corner ? 1 : 0 }
                var raw: UInt32 = 0
                if vertical < 0 { raw |= ClientSideDecorationResizeEdge.top.rawValue }
                if vertical > 0 { raw |= ClientSideDecorationResizeEdge.bottom.rawValue }
                if horizontal < 0 { raw |= ClientSideDecorationResizeEdge.left.rawValue }
                if horizontal > 0 { raw |= ClientSideDecorationResizeEdge.right.rawValue }
                if let edge = ClientSideDecorationResizeEdge(rawValue: raw) { return .resize(edge) }
            }
        }
        guard f.contains(p) else { return .outside }
        if titleBarHeight > 0, p.y < f.minY + titleBarHeight { return .titleBar }
        return .content
    }
}
