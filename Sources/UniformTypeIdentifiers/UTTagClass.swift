// UniformTypeIdentifiers for Windows and Linux (ADR-0009). Tag classes as Apple declares
// them in UTTagClass.h; the raw values are the tag-class identifiers.

public struct UTTagClass: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// `public.filename-extension`: the tag is a filename extension without the dot.
    public static var filenameExtension: UTTagClass { UTTagClass(rawValue: "public.filename-extension") }
    /// `public.mime-type`: the tag is a MIME type such as `image/png`.
    public static var mimeType: UTTagClass { UTTagClass(rawValue: "public.mime-type") }
}
