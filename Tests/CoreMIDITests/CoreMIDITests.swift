import XCTest
#if canImport(CoreMIDIPortable)
@testable import CoreMIDIPortable
#else
@testable import CoreMIDI
#endif
final class CoreMIDIPlaceholderTests: XCTestCase { func testPlaceholder() {} }
