// What Apple's CoreGraphics gives a file that imports only it (or one of its submodules):
// CGFloat and the geometry types, which swift-corelibs-foundation defines in Foundation.
@_exported import Foundation
// On Apple platforms `import Foundation` brings URLSession along; on Windows and Linux
// swift-corelibs-foundation keeps it in FoundationNetworking, which code written for Apple's
// SDKs never imports (NetworkImage, the loader behind swift-markdown-ui). Re-exporting it
// from CoreGraphics, which every such file imports through AppKit, SwiftUI or ImageIO,
// gives them the Foundation they were written against.
#if canImport(FoundationNetworking)
@_exported import FoundationNetworking
#endif
