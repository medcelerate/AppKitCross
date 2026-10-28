// Minimal COM helpers for calling Direct2D through its C vtables from Swift.
//
// Every Direct2D interface is a C struct whose first member is `lpVtbl`, a pointer to a
// table of function pointers; the first parameter of each function is the interface
// pointer itself. This file keeps that boilerplate in one place.

#if os(Windows)
import WinSDK

public struct COMError: Error, CustomStringConvertible {
    public let hr: HRESULT
    public let call: String
    public var description: String { "\(call) failed: HRESULT 0x\(String(UInt32(bitPattern: hr), radix: 16))" }
}

@inline(__always)
func check(_ hr: HRESULT, _ call: String) throws {
    if hr < 0 { throw COMError(hr: hr, call: call) }
}

/// Owns a COM interface pointer and releases it when deallocated.
final class COMObject<T> {
    let pointer: UnsafeMutablePointer<T>
    private let release: () -> Void

    init(_ pointer: UnsafeMutablePointer<T>, release: @escaping () -> Void) {
        self.pointer = pointer
        self.release = release
    }
    deinit { release() }
}

extension IID {
    /// {06152247-6f50-465a-9245-118bfd3b6041}
    static let d2d1Factory = IID(Data1: 0x0615_2247, Data2: 0x6f50, Data3: 0x465a,
                                 Data4: (0x92, 0x45, 0x11, 0x8b, 0xfd, 0x3b, 0x60, 0x41))
}

@inline(__always)
func d2dColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> D2D1_COLOR_F {
    D2D1_COLOR_F(r: Float(r), g: Float(g), b: Float(b), a: Float(a))
}

@inline(__always)
func d2dPoint(_ p: CGPoint) -> D2D1_POINT_2F { D2D1_POINT_2F(x: Float(p.x), y: Float(p.y)) }

@inline(__always)
func d2dRect(_ r: CGRect) -> D2D1_RECT_F {
    D2D1_RECT_F(left: Float(r.minX), top: Float(r.minY), right: Float(r.maxX), bottom: Float(r.maxY))
}

@inline(__always)
func d2dMatrix(_ t: CGAffineTransform) -> D2D1_MATRIX_3X2_F {
    var m = D2D1_MATRIX_3X2_F()
    m.m11 = Float(t.a); m.m12 = Float(t.b)
    m.m21 = Float(t.c); m.m22 = Float(t.d)
    m.dx = Float(t.tx); m.dy = Float(t.ty)
    return m
}
#endif
