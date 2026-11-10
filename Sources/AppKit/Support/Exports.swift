// Apple's AppKit re-exports Foundation and the graphics frameworks; client code expects
// `import AppKit` to bring NSRect, Notification, CGContext and friends into scope.
@_exported import Foundation
#if canImport(CoreGraphics)
@_exported import CoreGraphics
#endif
#if canImport(QuartzCore)
@_exported import QuartzCore
#endif
#if canImport(CoreText)
@_exported import CoreText
#endif
// `import AppKit` also brings ImageIO (CGImageSource and the C API) and Core Image into
// scope on macOS; the port's ImageIO stands in on Windows and Linux, Core Image has no
// counterpart there (CIImage, CIFilter stay unavailable).
#if canImport(ImageIO)
@_exported import ImageIO
#endif
#if canImport(CoreImage)
@_exported import CoreImage
#endif
