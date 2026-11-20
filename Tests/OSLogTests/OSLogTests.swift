import XCTest
import Foundation
#if canImport(OSLogPortable)
@testable import OSLogPortable
#else
@testable import OSLog
#endif

private struct Gadget: CustomStringConvertible {
    var description: String { "gadget-7" }
}

private struct Boom: Error, CustomStringConvertible {
    var description: String { "boom" }
}

final class OSLogTests: XCTestCase {
    private var saved: _OSLogConfiguration!

    override func setUp() {
        super.setUp()
        saved = _OSLogTestHooks.configuration
        _OSLogTestHooks.configuration = _OSLogConfiguration(minimumRank: 2, revealPrivate: false)
    }

    override func tearDown() {
        _OSLogTestHooks.configuration = saved
        super.tearDown()
    }

    private func render(_ message: OSLogMessage, reveal: Bool = false) -> String {
        _OSLogFormatter.render(message: message, revealPrivate: reveal)
    }

    func testLiteralAndScalarsArePublicByDefault() {
        let rate = 48000.0
        let channels: UInt32 = 2
        let status: Int32 = -50
        XCTAssertEqual(render("plain"), "plain")
        XCTAssertEqual(render("rate \(rate) ch \(channels) st \(status) n \(7)"), "rate 48000.000000 ch 2 st -50 n 7")
        XCTAssertEqual(render("ok \(true)"), "ok true")
    }

    func testPrivacyRedaction() {
        let name = "Built-in Output"
        XCTAssertEqual(render("dev \(name)"), "dev <private>")
        XCTAssertEqual(render("dev \(name, privacy: .public)"), "dev Built-in Output")
        XCTAssertEqual(render("n \(42, privacy: .private)"), "n <private>")
        XCTAssertEqual(render("n \(42, privacy: .sensitive)"), "n <private>")
        XCTAssertEqual(render("g \(Gadget())"), "g <private>")
        XCTAssertEqual(render("g \(Gadget(), privacy: .public)"), "g gadget-7")
        XCTAssertEqual(render("e \(Boom() as Error)"), "e <private>")
        XCTAssertEqual(render("e \(Boom() as Error, privacy: .public)"), "e boom")
        XCTAssertEqual(render("dev \(name)", reveal: true), "dev Built-in Output")
        let masked = render("dev \(name, privacy: .private(mask: .hash))")
        XCTAssertTrue(masked.hasPrefix("dev <mask.hash: '"), masked)
        XCTAssertEqual(masked, render("dev \(name, privacy: .private(mask: .hash))"))
    }

    func testAlignment() {
        XCTAssertEqual(render("[\("ab", align: .right(columns: 5), privacy: .public)]"), "[   ab]")
        XCTAssertEqual(render("[\("ab", align: .left(columns: 5), privacy: .public)]"), "[ab   ]")
        XCTAssertEqual(render("[\(12, align: .right(columns: 4))]"), "[  12]")
        XCTAssertEqual(render("[\("toolong", align: .left(columns: 3), privacy: .public)]"), "[toolong]")
    }

    func testIntegerFormats() {
        XCTAssertEqual(render("\(255, format: .hex)"), "ff")
        XCTAssertEqual(render("\(255, format: .hex(includePrefix: true, uppercase: true))"), "0XFF")
        XCTAssertEqual(render("\(255, format: .hex(includePrefix: true))"), "0xff")
        XCTAssertEqual(render("\(10, format: .hex(minDigits: 4))"), "000a")
        XCTAssertEqual(render("\(Int32(-1), format: .hex)"), "ffffffff")
        XCTAssertEqual(render("\(UInt8(8), format: .octal(includePrefix: true))"), "010")
        XCTAssertEqual(render("\(5, format: .decimal(explicitPositiveSign: true, minDigits: 3))"), "+005")
        XCTAssertEqual(render("\(-5, format: .decimal(minDigits: 3))"), "-005")
    }

    func testFloatFormats() {
        let x = 3.14159
        XCTAssertEqual(render("\(x, format: .fixed(precision: 2))"), "3.14")
        XCTAssertEqual(render("\(x, format: .fixed(precision: 0))"), "3")
        XCTAssertEqual(render("\(Float(1.5), format: .fixed(precision: 1, explicitPositiveSign: true))"), "+1.5")
        XCTAssertEqual(render("\(1234.5, format: .exponential(precision: 2))"), "1.23e+03")
        XCTAssertEqual(render("\(1234.5, format: .exponential(precision: 2, uppercase: true))"), "1.23E+03")
        XCTAssertEqual(render("\(0.5, format: .hybrid)"), "0.5")
    }

    func testBoolFormats() {
        XCTAssertEqual(render("\(true, format: .truth) \(false, format: .truth)"), "true false")
        XCTAssertEqual(render("\(true, format: .answer) \(false, format: .answer)"), "YES NO")
    }

    func testOtherOverloads() {
        XCTAssertEqual(render("\(Int.self, privacy: .public)"), "Int")
        let object = NSString(string: "obj")
        XCTAssertEqual(render("\(object, privacy: .public)"), "obj")
        let bytes: [UInt8] = [0xde, 0xad, 0xbe, 0xef]
        bytes.withUnsafeBytes { buffer in
            XCTAssertEqual(render("\(buffer, privacy: .public)"), "deadbeef")
        }
        let uuid = UUID()
        withUnsafeBytes(of: uuid.uuid) { buffer in
            XCTAssertEqual(render("\(buffer, format: .uuid, privacy: .public)"), uuid.uuidString)
        }
    }

    func testLevelGatingAndLaziness() {
        let log = Logger(subsystem: "live.clockworks.sibyl", category: "audio")
        var evaluations = 0
        func expensive() -> Int { evaluations += 1; return 1 }
        let lines = _OSLogTestHooks.capture {
            log.debug("d \(expensive())")
            log.info("i \(expensive())")
            log.trace("t \(expensive())")
            log.notice("n \(expensive())")
            log.warning("w")
            log.error("e")
            log.critical("c")
            log.fault("f")
            log.log("l")
            log.log(level: .info, "li")
        }
        XCTAssertEqual(evaluations, 1, "debug/info/trace interpolations must not run when hidden")
        XCTAssertEqual(lines.count, 6)
        XCTAssertTrue(lines[0].hasSuffix("[live.clockworks.sibyl:audio] NOTICE n 1"), lines[0])
        XCTAssertTrue(lines[1].hasSuffix("ERROR w"))
        XCTAssertTrue(lines[3].hasSuffix("FAULT c"))
        XCTAssertTrue(lines[5].hasSuffix("NOTICE l"))

        _OSLogTestHooks.configuration = _OSLogConfiguration(minimumRank: 0, revealPrivate: false)
        let all = _OSLogTestHooks.capture {
            log.debug("d \(expensive())")
            log.info("i")
        }
        XCTAssertEqual(evaluations, 2)
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all[0].hasSuffix("DEBUG d 1"))
        XCTAssertTrue(all[1].hasSuffix("INFO i"))

        _OSLogTestHooks.configuration = _OSLogConfiguration(minimumRank: 3, revealPrivate: false)
        XCTAssertEqual(_OSLogTestHooks.capture { log.notice("n"); log.error("e") }.count, 1)
    }

    func testLineShape() {
        let line = _OSLogFormatter.line("hello", type: .default, log: OSLog(subsystem: "s", category: "c"))
        let parts = line.split(separator: " ")
        XCTAssertEqual(parts.count, 5, line)
        XCTAssertNotNil(ISO8601DateFormatter().date(from: String(parts[0]).replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)), line)
        XCTAssertTrue(parts[1].hasSuffix("[\(ProcessInfo.processInfo.processIdentifier)]"))
        XCTAssertEqual(parts[2], "[s:c]")
        XCTAssertEqual(parts[3], "NOTICE")
        XCTAssertEqual(parts[4], "hello")
    }

    func testDisabledLogAndOSLogObjects() {
        let lines = _OSLogTestHooks.capture {
            Logger(OSLog.disabled).fault("never")
            Logger().notice("plain")
            Logger(OSLog(subsystem: "a", category: .pointsOfInterest)).error("poi")
        }
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].hasSuffix(" NOTICE plain"), lines[0])
        XCTAssertFalse(lines[0].contains("[:"), "no subsystem bracket for Logger()")
        XCTAssertTrue(lines[1].contains("[a:PointsOfInterest] ERROR poi"))
        XCTAssertFalse(OSLog.disabled.isEnabled(type: .fault))
        XCTAssertTrue(OSLog.default.isEnabled(type: .error))
        XCTAssertFalse(OSLog.default.isEnabled(type: .debug))
    }

    func testOSLogFunctions() {
        let log = OSLog(subsystem: "s", category: "c")
        let lines = _OSLogTestHooks.capture {
            os_log("count %d name %@ pub %{public}@ hex %x", log: log, type: .error, 3, "secret", "shown", 255)
            os_log(.fault, log: log, "fault %{private}d", 9)
            os_log("debug hidden", log: log, type: .debug)
            os_log(.default, log: log, "message \(5)")
        }
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasSuffix("ERROR count 3 name <private> pub shown hex ff"), lines[0])
        XCTAssertTrue(lines[1].hasSuffix("FAULT fault <private>"), lines[1])
        XCTAssertTrue(lines[2].hasSuffix("NOTICE message 5"), lines[2])
        XCTAssertEqual(_OSLogFormatter.renderFormat("%{public}s %%", ["x"], revealPrivate: false), "x %")
    }

    func testEnvironmentParsing() {
        XCTAssertEqual(_OSLogConfiguration.rank(of: .debug), 0)
        XCTAssertEqual(_OSLogConfiguration.rank(of: .default), 2)
        XCTAssertEqual(_OSLogConfiguration.rank(of: .fault), 4)
        XCTAssertGreaterThan(OSLogMessage("a \(1) b \("x")").bufferSize, OSLogMessage("a").bufferSize)
    }
}
