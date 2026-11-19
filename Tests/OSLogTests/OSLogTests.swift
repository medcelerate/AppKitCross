import XCTest
#if canImport(OSLogPortable)
@testable import OSLogPortable
#else
@testable import OSLog
#endif
final class OSLogPlaceholderTests: XCTestCase { func testPlaceholder() {} }
