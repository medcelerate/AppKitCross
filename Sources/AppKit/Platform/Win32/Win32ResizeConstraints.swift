// NSWindow aspect ratios and resize increments during a user resize (ADR-0036):
// WM_SIZING hands over the proposed window rectangle in pixels, and the edge being
// dragged; the moving edges are adjusted so the content keeps to the constraints.

#if os(Windows)
import WinSDK
import Foundation

extension Win32Window {
    func setResizeConstraints(_ constraints: PlatformResizeConstraints) { resizeConstraints = constraints }

    /// Adjusts the proposed rectangle in place; nil lets DefWindowProc carry on when
    /// nothing constrains the resize.
    func handleSizing(edge: Int32, rect: UnsafeMutablePointer<RECT>?) -> LRESULT? {
        guard let rect, !resizeConstraints.isUnconstrained else { return nil }
        let r = rect.pointee
        let frame = NSRect(x: 0, y: 0, width: CGFloat(r.right - r.left) / scale, height: CGFloat(r.bottom - r.top) / scale)
        let content = contentRect(forFrameRect: frame)
        let extra = NSSize(width: frame.width - content.width, height: frame.height - content.height)
        let heightOnly = edge == WMSZ_TOP || edge == WMSZ_BOTTOM
        let c = resizeConstraints.constrain(contentSize: content.size, frameExtra: extra, heightEdgeOnly: heightOnly)
        let w = Int32(((c.width + extra.width) * scale).rounded()), h = Int32(((c.height + extra.height) * scale).rounded())
        // The edges the user holds move; the opposite ones stay.
        switch edge {
        case WMSZ_LEFT, WMSZ_TOPLEFT, WMSZ_BOTTOMLEFT: rect.pointee.left = r.right - w
        default: rect.pointee.right = r.left + w
        }
        switch edge {
        case WMSZ_TOP, WMSZ_TOPLEFT, WMSZ_TOPRIGHT: rect.pointee.top = r.bottom - h
        default: rect.pointee.bottom = r.top + h
        }
        return 1
    }
}
#endif
