// CTRunDelegate (CTRunDelegate.h) and CTTextTab (CTTextTab.h).
//
// A run delegate reserves space in a line for something the typesetter does not draw
// (a text attachment): its characters advance by the delegate's width, raise the line to
// its ascent and descent, and draw no glyphs. Tab stops position the pen after a tab
// character at the next stop of the paragraph style (or the default interval).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// Apple's are C function pointers; CGFloat is a Swift struct off Darwin and cannot cross a
// C convention, so these are Swift function types. Capture-free closures, as written for
// Apple's, convert to either.
public typealias CTRunDelegateDeallocateCallback = (UnsafeMutableRawPointer) -> Void
public typealias CTRunDelegateGetAscentCallback = (UnsafeMutableRawPointer) -> CGFloat
public typealias CTRunDelegateGetDescentCallback = (UnsafeMutableRawPointer) -> CGFloat
public typealias CTRunDelegateGetWidthCallback = (UnsafeMutableRawPointer) -> CGFloat

public var kCTRunDelegateVersion1: Int { 1 }
public var kCTRunDelegateCurrentVersion: Int { kCTRunDelegateVersion1 }

/// - SeeAlso: https://developer.apple.com/documentation/coretext/ctrundelegatecallbacks
public struct CTRunDelegateCallbacks {
    public var version: CFIndex
    public var dealloc: CTRunDelegateDeallocateCallback
    public var getAscent: CTRunDelegateGetAscentCallback
    public var getDescent: CTRunDelegateGetDescentCallback
    public var getWidth: CTRunDelegateGetWidthCallback
    public init(version: CFIndex, dealloc: @escaping CTRunDelegateDeallocateCallback, getAscent: @escaping CTRunDelegateGetAscentCallback, getDescent: @escaping CTRunDelegateGetDescentCallback, getWidth: @escaping CTRunDelegateGetWidthCallback) {
        self.version = version
        self.dealloc = dealloc
        self.getAscent = getAscent
        self.getDescent = getDescent
        self.getWidth = getWidth
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/coretext/ctrundelegate
public final class CTRunDelegate: NSObject {
    let callbacks: CTRunDelegateCallbacks
    let refCon: UnsafeMutableRawPointer?
    init(callbacks: CTRunDelegateCallbacks, refCon: UnsafeMutableRawPointer?) {
        self.callbacks = callbacks
        self.refCon = refCon
    }
    deinit { if let refCon { callbacks.dealloc(refCon) } }

    /// The callbacks take a non-null reference; a delegate made without one reports zero.
    private static let placeholder = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
    var ascent: CGFloat { max(0, callbacks.getAscent(refCon ?? CTRunDelegate.placeholder)) }
    var descent: CGFloat { max(0, callbacks.getDescent(refCon ?? CTRunDelegate.placeholder)) }
    var width: CGFloat { max(0, callbacks.getWidth(refCon ?? CTRunDelegate.placeholder)) }
}

public func CTRunDelegateGetTypeID() -> CFTypeID { 11 }

public func CTRunDelegateCreate(_ callbacks: UnsafePointer<CTRunDelegateCallbacks>, _ refCon: UnsafeMutableRawPointer?) -> CTRunDelegate? {
    guard callbacks.pointee.version == kCTRunDelegateVersion1 else { return nil }
    return CTRunDelegate(callbacks: callbacks.pointee, refCon: refCon)
}

public func CTRunDelegateGetRefCon(_ runDelegate: CTRunDelegate) -> UnsafeMutableRawPointer {
    runDelegate.refCon ?? UnsafeMutableRawPointer(bitPattern: 0x1)!
}

// MARK: CTTextTab

/// - SeeAlso: https://developer.apple.com/documentation/coretext/cttexttab
public final class CTTextTab: NSObject {
    let alignment: CTTextAlignment
    let location: Double
    let options: CFDictionary?
    init(alignment: CTTextAlignment, location: Double, options: CFDictionary?) {
        self.alignment = alignment
        self.location = location
        self.options = options
    }
    public override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? CTTextTab else { return false }
        return o.alignment == alignment && o.location == location
    }
    public override var hash: Int { Int(location * 64) ^ Int(alignment.rawValue) }
}

public func CTTextTabGetTypeID() -> CFTypeID { 12 }
public func CTTextTabCreate(_ alignment: CTTextAlignment, _ location: Double, _ options: CFDictionary?) -> CTTextTab {
    CTTextTab(alignment: alignment, location: location, options: options)
}
public func CTTextTabGetAlignment(_ tab: CTTextTab) -> CTTextAlignment { tab.alignment }
public func CTTextTabGetLocation(_ tab: CTTextTab) -> Double { tab.location }
public func CTTextTabGetOptions(_ tab: CTTextTab) -> CFDictionary? { tab.options }
public let kCTTabColumnTerminatorsAttributeName: CFString = "NSTabColumnTerminatorsAttributeName"

extension CTParagraphStyle {
    /// The tab stops, sorted by location.
    var textTabs: [CTTextTab] {
        let raw = tabStopsObject
        let tabs: [CTTextTab]
        if let a = raw as? [CTTextTab] { tabs = a }
        else if let a = raw as? NSArray { tabs = a.compactMap { $0 as? CTTextTab } }
        else { tabs = [] }
        return tabs.sorted { $0.location < $1.location }
    }
}
