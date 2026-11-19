import XCTest
#if canImport(NetworkPortable)
@testable import NetworkPortable
#else
@testable import Network
#endif
final class NetworkPlaceholderTests: XCTestCase { func testPlaceholder() {} }
