// Cocoa: the umbrella module Mac code imports to get AppKit and Foundation at once.
//
// On macOS `import Cocoa` re-exports AppKit, Foundation and Core Data. This port provides
// no Core Data, so the umbrella re-exports the two it has; code that reaches for a Core
// Data type through `import Cocoa` fails to compile with the missing type named, instead
// of failing at the import. `canImport(Cocoa)` is true on every platform the port builds for.

@_exported import AppKit
@_exported import Foundation
