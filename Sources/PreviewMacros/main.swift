// The compiler plugin behind `#Preview` and `@Previewable` (ADR-0049).
//
// Apple's `#Preview` expands through Xcode's PreviewsMacros plugin, which ships with Xcode
// and not with the open-source toolchains, so sources containing `#Preview { … }` do not
// compile on Windows or Linux. This executable is a compiler plugin with no dependencies:
// it speaks the compiler's plugin protocol (8-byte little-endian length, then a JSON
// message, on stdin and stdout) directly instead of linking swift-syntax.
//
// `#Preview(args) { body }` expands to a never-called function holding
// `Preview._make<Kind>(args) { body }`, so the body is still type-checked as on macOS (an
// error in it points at the app's source), and nothing runs: the port has no preview canvas.
// `@Previewable` expands to nothing; its variable stays a local of the body.

import Foundation

let input = FileHandle.standardInput
let output = FileHandle.standardOutput

func readExactly(_ count: Int) -> Data? {
    var data = Data()
    while data.count < count {
        let chunk = input.readData(ofLength: count - data.count)
        if chunk.isEmpty { return nil }
        data.append(chunk)
    }
    return data
}

func send(_ message: [String: Any]) {
    guard let json = try? JSONSerialization.data(withJSONObject: message) else { return }
    var length = UInt64(json.count).littleEndian
    output.write(Data(bytes: &length, count: 8))
    output.write(json)
}

func result(_ source: String?, error: String? = nil, location: [String: Any]? = nil) -> [String: Any] {
    var diagnostics: [[String: Any]] = []
    if let error, let location {
        diagnostics.append([
            "message": error, "severity": "error",
            "position": ["fileName": location["fileName"] ?? "", "offset": location["offset"] ?? 0],
            "highlights": [Any](), "notes": [Any](), "fixIts": [Any](),
        ])
    }
    return ["expandMacroResult": ["expandedSource": source.map { $0 as Any } ?? NSNull(), "diagnostics": diagnostics]]
}

/// The expansion's source without the comments and whitespace before the `#` (the
/// compiler sends the leading trivia too).
func withoutLeadingTrivia(_ text: String) -> String {
    var rest = Substring(text)
    while true {
        rest = rest.drop { $0.isWhitespace }
        if rest.hasPrefix("//") {
            rest = rest.drop { $0 != "\n" && $0 != "\r" }
        } else if rest.hasPrefix("/*"), let end = rest.range(of: "*/") {
            rest = rest[end.upperBound...]
        } else {
            return String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

/// The expansion of one `#Preview`: a function named the way swift-syntax's
/// `makeUniqueName("preview")` would name it, so the compiler accepts it at file scope.
func expandPreview(_ request: [String: Any]) -> [String: Any] {
    let macro = request["macro"] as? [String: Any] ?? [:]
    let syntax = request["syntax"] as? [String: Any] ?? [:]
    let location = syntax["location"] as? [String: Any]
    let discriminator = request["discriminator"] as? String ?? ""
    let kind = macro["typeName"] as? String ?? "SwiftUIView"
    let name = macro["name"] as? String ?? "Preview"
    let source = withoutLeadingTrivia(syntax["source"] as? String ?? "")
    guard source.hasPrefix("#" + name) else {
        return result(nil, error: "#\(name): unexpected macro expansion source", location: location)
    }
    let arguments = source.dropFirst(name.count + 1)
    let function = discriminator + "7preview" + "fMu_"
    return result("""
    @MainActor private func \(function)() -> Preview {
        Preview._make\(kind)\(arguments)
    }
    """)
}

while let header = readExactly(8) {
    let length = header.withUnsafeBytes { Int(UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self))) }
    guard let body = readExactly(length),
          let message = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { break }
    if let request = message["getCapability"] as? [String: Any] {
        let version = ((request["capability"] as? [String: Any])?["protocolVersion"] as? Int) ?? 1
        send(["getCapabilityResult": ["capability": ["protocolVersion": min(version, 7), "features": [String]()]]])
    } else if let request = message["expandFreestandingMacro"] as? [String: Any] {
        send(expandPreview(request))
    } else if message["expandAttachedMacro"] != nil {
        send(result(""))                                // @Previewable
    } else {
        send(result(nil))
    }
}
