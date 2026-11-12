// CTParagraphStyle (CTParagraphStyle.h): a bag of typed settings read back by specifier.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct CTParagraphStyleSetting {
    public var spec: CTParagraphStyleSpecifier
    public var valueSize: Int
    public var value: UnsafeRawPointer
    public init(spec: CTParagraphStyleSpecifier, valueSize: Int, value: UnsafeRawPointer) {
        self.spec = spec
        self.valueSize = valueSize
        self.value = value
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/coretext/ctparagraphstyle
public final class CTParagraphStyle: NSObject {
    /// Raw bytes per specifier, exactly as supplied (so reads return what was written).
    private var values: [CTParagraphStyleSpecifier: [UInt8]] = [:]
    private var objects: [CTParagraphStyleSpecifier: AnyObject] = [:]

    init(settings: [CTParagraphStyleSetting]) {
        super.init()
        for s in settings {
            if s.spec == .tabStops {
                objects[s.spec] = s.value.load(as: AnyObject.self)
            } else {
                values[s.spec] = Array(UnsafeRawBufferPointer(start: s.value, count: s.valueSize))
            }
        }
    }

    private init(copying other: CTParagraphStyle) {
        values = other.values
        objects = other.objects
    }

    func copy() -> CTParagraphStyle { CTParagraphStyle(copying: self) }

    /// The `tabStops` value as supplied (a CFArray of CTTextTab).
    var tabStopsObject: AnyObject? { objects[.tabStops] }

    func load<T>(_ spec: CTParagraphStyleSpecifier, as type: T.Type) -> T? {
        guard let bytes = values[spec], bytes.count >= MemoryLayout<T>.size else { return nil }
        return bytes.withUnsafeBytes { $0.loadUnaligned(as: T.self) }
    }

    func read(_ spec: CTParagraphStyleSpecifier, size: Int, into buffer: UnsafeMutableRawPointer) -> Bool {
        if spec == .tabStops {
            guard let o = objects[spec] else { return false }
            buffer.storeBytes(of: o, as: AnyObject.self)
            return true
        }
        guard let bytes = values[spec], bytes.count >= size else { return false }
        bytes.withUnsafeBytes { buffer.copyMemory(from: $0.baseAddress!, byteCount: size) }
        return true
    }

    // Typed accessors used by the framesetter.
    var alignment: CTTextAlignment { load(.alignment, as: UInt8.self).flatMap(CTTextAlignment.init(rawValue:)) ?? .natural }
    var lineBreakMode: CTLineBreakMode { load(.lineBreakMode, as: UInt8.self).flatMap(CTLineBreakMode.init(rawValue:)) ?? .byWordWrapping }
    var baseWritingDirection: CTWritingDirection { load(.baseWritingDirection, as: Int8.self).flatMap(CTWritingDirection.init(rawValue:)) ?? .natural }
    var firstLineHeadIndent: CGFloat { load(.firstLineHeadIndent, as: CGFloat.self) ?? 0 }
    var headIndent: CGFloat { load(.headIndent, as: CGFloat.self) ?? 0 }
    var tailIndent: CGFloat { load(.tailIndent, as: CGFloat.self) ?? 0 }
    var lineHeightMultiple: CGFloat { load(.lineHeightMultiple, as: CGFloat.self) ?? 0 }
    var maximumLineHeight: CGFloat { load(.maximumLineHeight, as: CGFloat.self) ?? 0 }
    var minimumLineHeight: CGFloat { load(.minimumLineHeight, as: CGFloat.self) ?? 0 }
    var lineSpacing: CGFloat { load(.lineSpacing, as: CGFloat.self) ?? 0 }
    var lineSpacingAdjustment: CGFloat { load(.lineSpacingAdjustment, as: CGFloat.self) ?? 0 }
    var minimumLineSpacing: CGFloat { load(.minimumLineSpacing, as: CGFloat.self) ?? 0 }
    var maximumLineSpacing: CGFloat { load(.maximumLineSpacing, as: CGFloat.self) ?? 0 }
    var paragraphSpacing: CGFloat { load(.paragraphSpacing, as: CGFloat.self) ?? 0 }
    var paragraphSpacingBefore: CGFloat { load(.paragraphSpacingBefore, as: CGFloat.self) ?? 0 }
    var defaultTabInterval: CGFloat { load(.defaultTabInterval, as: CGFloat.self) ?? 0 }
}

public func CTParagraphStyleGetTypeID() -> CFTypeID { 3 }

public func CTParagraphStyleCreate(_ settings: UnsafePointer<CTParagraphStyleSetting>?, _ settingCount: Int) -> CTParagraphStyle {
    guard let settings, settingCount > 0 else { return CTParagraphStyle(settings: []) }
    return CTParagraphStyle(settings: Array(UnsafeBufferPointer(start: settings, count: settingCount)))
}

public func CTParagraphStyleCreateCopy(_ paragraphStyle: CTParagraphStyle) -> CTParagraphStyle { paragraphStyle.copy() }

public func CTParagraphStyleGetValueForSpecifier(_ paragraphStyle: CTParagraphStyle, _ spec: CTParagraphStyleSpecifier, _ valueBufferSize: Int, _ valueBuffer: UnsafeMutableRawPointer) -> Bool {
    if paragraphStyle.read(spec, size: valueBufferSize, into: valueBuffer) { return true }
    // Unset specifiers yield their defaults, as on Apple platforms.
    switch spec {
    case .alignment: valueBuffer.storeBytes(of: CTTextAlignment.natural.rawValue, as: UInt8.self)
    case .lineBreakMode: valueBuffer.storeBytes(of: CTLineBreakMode.byWordWrapping.rawValue, as: UInt8.self)
    case .baseWritingDirection: valueBuffer.storeBytes(of: CTWritingDirection.natural.rawValue, as: Int8.self)
    case .lineBoundsOptions: valueBuffer.storeBytes(of: UInt(0), as: UInt.self)
    case .tabStops: return false
    default: valueBuffer.storeBytes(of: CGFloat(0), as: CGFloat.self)
    }
    return true
}
