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
