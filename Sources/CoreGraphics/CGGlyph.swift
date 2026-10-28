// Glyph index types (CGFont.h on Apple platforms).

public typealias CGFontIndex = UInt16
public typealias CGGlyph = CGFontIndex

public let kCGFontIndexMax: CGFontIndex = 65534
public let kCGFontIndexInvalid: CGFontIndex = 65535
public let kCGGlyphMax: CGGlyph = kCGFontIndexMax
