import XCTest
import Foundation
@testable import AppKit

/// ADR-0044: `appleOnly` in tools/apigen/config.json lists types and members that exist only
/// on macOS. The generator stubs them with appleOnlyUnavailable() instead of unimplemented(),
/// and docs/API-COVERAGE.md counts the two apart. These tests check the checked-in tree
/// against the config (the generator itself also refuses an entry missing from the full
/// symbol-graph inventory, which is git-ignored and so not available here).
final class AppleOnlyGeneratorTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private struct Config {
        var appleOnly: [String]
        var reasons: [String: String]
        var handwritten: Set<String>
        var skipTypes: Set<String>
        var pending: Set<String>
    }

    private func config() throws -> Config {
        let url = root.appendingPathComponent("tools/apigen/config.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("sources not next to the tests") }
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return Config(appleOnly: obj["appleOnly"] as? [String] ?? [],
                      reasons: obj["appleOnlyReasons"] as? [String: String] ?? [:],
                      handwritten: Set(obj["handwritten"] as? [String] ?? []),
                      skipTypes: Set(obj["skipTypes"] as? [String] ?? []),
                      pending: Set(obj["pending"] as? [String] ?? []))
    }

    /// Top-level type name and, for a member entry ("NSHelpManager.registerBooks(in:)"), the member.
    private func split(_ entry: String) -> (owner: String, member: String?) {
        guard let dot = entry.firstIndex(of: ".") else { return (entry, nil) }
        return (String(entry[..<dot]), String(entry[entry.index(after: dot)...]))
    }

    /// Non-comment lines (CRLF-safe: "\r\n" is one Character in Swift).
    private func codeLines(_ url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    private func occurrences(of needle: String, in lines: [String]) -> Int {
        lines.reduce(0) { $0 + $1.components(separatedBy: needle).count - 1 }
    }

    private func swiftFiles(_ dir: URL) -> [URL] {
        let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)
        return (e?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
    }

    func testEntriesAreGeneratedTypesNotOwnedElsewhere() throws {
        let c = try config()
        XCTAssertFalse(c.appleOnly.isEmpty)
        XCTAssertEqual(Set(c.appleOnly).count, c.appleOnly.count, "appleOnly has duplicates")
        XCTAssertEqual(Set(c.reasons.keys), Set(c.appleOnly), "every appleOnly entry needs exactly one reason")
        for entry in c.appleOnly {
            XCTAssertFalse((c.reasons[entry] ?? "").isEmpty, "\(entry) has no reason")
            let (owner, member) = split(entry)
            XCTAssertFalse(c.handwritten.contains(owner), "\(entry) is owned by Core (handwritten); mark Core stubs in Core")
            XCTAssertFalse(c.skipTypes.contains(owner), "\(entry) is also in skipTypes")
            XCTAssertFalse(c.pending.contains(owner), "\(entry) is also pending")
            // The generator emits one file per inventory type, so a missing file means the
            // entry names a type that is not in the inventory (or is not generated).
            let file = root.appendingPathComponent("Sources/AppKit/Generated/\(owner).swift")
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "\(entry): no Generated/\(owner).swift")
            if let member, FileManager.default.fileExists(atPath: file.path) {
                let base = member.components(separatedBy: "(")[0]
                let decl = try codeLines(file).filter { $0.contains("appleOnlyUnavailable()") && $0.contains(" \(base)") }
                XCTAssertFalse(decl.isEmpty, "\(entry): no Apple-only declaration in Generated/\(owner).swift")
            }
        }
    }

    func testAppleOnlyTypesHaveNoOrdinaryStubs() throws {
        let c = try config()
        let generated = root.appendingPathComponent("Sources/AppKit/Generated")
        let wholeTypes = Set(c.appleOnly.filter { !$0.contains(".") })
        let memberOwners = Set(c.appleOnly.filter { $0.contains(".") }.map { split($0).owner })
        for f in swiftFiles(generated) {
            let name = f.deletingPathExtension().lastPathComponent
            let lines = try codeLines(f)
            if wholeTypes.contains(name) {
                XCTAssertEqual(occurrences(of: "unimplemented()", in: lines), 0, "\(name) is Apple-only but has unimplemented()")
                XCTAssertEqual(occurrences(of: "unimplementedOptionalRequirement()", in: lines), 0, name)
            } else if !memberOwners.contains(name) {
                XCTAssertEqual(occurrences(of: "appleOnlyUnavailable(", in: lines), 0, "\(name) is not listed in appleOnly")
            }
        }
    }

    /// The "Stub call sites" table in docs/API-COVERAGE.md matches the tree, so the honest
    /// still-to-do number cannot drift from the sources (rerun the generator after edits).
    func testCoverageReportCountsMatchTheTree() throws {
        _ = try config()
        func count(_ dir: String) throws -> (Int, Int) {
            var u = 0, a = 0
            for f in swiftFiles(root.appendingPathComponent(dir)) {
                let lines = try codeLines(f)
                u += occurrences(of: "unimplemented(", in: lines)
                a += occurrences(of: "appleOnlyUnavailable(", in: lines)
            }
            return (u, a)
        }
        let report = try String(contentsOf: root.appendingPathComponent("docs/API-COVERAGE.md"), encoding: .utf8)
        for (dir, label) in [("Sources/AppKit/Generated", "`Sources/AppKit/Generated`"), ("Sources/AppKit/Core", "`Sources/AppKit/Core`")] {
            let (u, a) = try count(dir)
            XCTAssertTrue(report.contains("| \(label) | \(u) | \(a) |"),
                          "docs/API-COVERAGE.md is stale for \(dir): expected \(u) unimplemented, \(a) Apple-only; run python3 tools/apigen/apigen.py")
        }
    }
}
