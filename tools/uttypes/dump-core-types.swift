// Dumps Apple's UTCoreTypes declarations (identifier, direct supertypes, tags, description,
// reference URL, version) as the Swift table behind Sources/UniformTypeIdentifiers.
//
//   swift tools/uttypes/dump-core-types.swift > Sources/UniformTypeIdentifiers/UTCoreTypesTable.swift
//
// Runs on macOS only (it reads Apple's implementation, the specification). The constant
// list is every `public static var` of UTType in the SDK's UniformTypeIdentifiers
// swiftinterface; supertypes those reach that are not constants get rows too so that
// conformance closes over them.
import Foundation
import UniformTypeIdentifiers

@available(macOS 15.2, *)
func main() {

let constants: [(String, UTType)] = [
    ("item", .item), ("content", .content), ("compositeContent", .compositeContent), ("diskImage", .diskImage), ("data", .data), ("directory", .directory), ("resolvable", .resolvable), ("symbolicLink", .symbolicLink), ("executable", .executable), ("mountPoint", .mountPoint), ("aliasFile", .aliasFile), ("urlBookmarkData", .urlBookmarkData), ("url", .url), ("fileURL", .fileURL), ("text", .text), ("plainText", .plainText), ("utf8PlainText", .utf8PlainText), ("utf16ExternalPlainText", .utf16ExternalPlainText), ("utf16PlainText", .utf16PlainText), ("delimitedText", .delimitedText), ("commaSeparatedText", .commaSeparatedText), ("tabSeparatedText", .tabSeparatedText), ("utf8TabSeparatedText", .utf8TabSeparatedText), ("rtf", .rtf), ("html", .html), ("xml", .xml), ("yaml", .yaml), ("css", .css), ("sourceCode", .sourceCode), ("assemblyLanguageSource", .assemblyLanguageSource), ("cSource", .cSource), ("objectiveCSource", .objectiveCSource), ("swiftSource", .swiftSource), ("cPlusPlusSource", .cPlusPlusSource), ("objectiveCPlusPlusSource", .objectiveCPlusPlusSource), ("cHeader", .cHeader), ("cPlusPlusHeader", .cPlusPlusHeader), ("script", .script), ("appleScript", .appleScript), ("osaScript", .osaScript), ("osaScriptBundle", .osaScriptBundle), ("javaScript", .javaScript), ("shellScript", .shellScript), ("perlScript", .perlScript), ("pythonScript", .pythonScript), ("rubyScript", .rubyScript), ("phpScript", .phpScript), ("makefile", .makefile), ("json", .json), ("propertyList", .propertyList), ("xmlPropertyList", .xmlPropertyList), ("binaryPropertyList", .binaryPropertyList), ("pdf", .pdf), ("rtfd", .rtfd), ("flatRTFD", .flatRTFD), ("webArchive", .webArchive), ("image", .image), ("jpeg", .jpeg), ("tiff", .tiff), ("gif", .gif), ("png", .png), ("icns", .icns), ("bmp", .bmp), ("ico", .ico), ("rawImage", .rawImage), ("svg", .svg), ("livePhoto", .livePhoto), ("heif", .heif), ("heic", .heic), ("heics", .heics), ("webP", .webP), ("exr", .exr), ("dng", .dng), ("jpegxl", .jpegxl), ("threeDContent", .threeDContent), ("usd", .usd), ("usdz", .usdz), ("realityFile", .realityFile), ("sceneKitScene", .sceneKitScene), ("arReferenceObject", .arReferenceObject), ("audiovisualContent", .audiovisualContent), ("movie", .movie), ("video", .video), ("audio", .audio), ("quickTimeMovie", .quickTimeMovie), ("mpeg", .mpeg), ("mpeg2Video", .mpeg2Video), ("mpeg2TransportStream", .mpeg2TransportStream), ("mp3", .mp3), ("mpeg4Movie", .mpeg4Movie), ("mpeg4Audio", .mpeg4Audio), ("appleProtectedMPEG4Audio", .appleProtectedMPEG4Audio), ("appleProtectedMPEG4Video", .appleProtectedMPEG4Video), ("avi", .avi), ("aiff", .aiff), ("wav", .wav), ("midi", .midi), ("playlist", .playlist), ("m3uPlaylist", .m3uPlaylist), ("folder", .folder), ("volume", .volume), ("package", .package), ("bundle", .bundle), ("pluginBundle", .pluginBundle), ("spotlightImporter", .spotlightImporter), ("quickLookGenerator", .quickLookGenerator), ("xpcService", .xpcService), ("framework", .framework), ("application", .application), ("applicationBundle", .applicationBundle), ("applicationExtension", .applicationExtension), ("unixExecutable", .unixExecutable), ("exe", .exe), ("systemPreferencesPane", .systemPreferencesPane), ("archive", .archive), ("gzip", .gzip), ("bz2", .bz2), ("zip", .zip), ("appleArchive", .appleArchive), ("tarArchive", .tarArchive), ("spreadsheet", .spreadsheet), ("presentation", .presentation), ("database", .database), ("message", .message), ("contact", .contact), ("vCard", .vCard), ("toDoItem", .toDoItem), ("calendarEvent", .calendarEvent), ("emailMessage", .emailMessage), ("internetLocation", .internetLocation), ("internetShortcut", .internetShortcut), ("font", .font), ("bookmark", .bookmark), ("pkcs12", .pkcs12), ("x509Certificate", .x509Certificate), ("epub", .epub), ("log", .log), ("ahap", .ahap), ("geoJSON", .geoJSON), ("linkPresentationMetadata", .linkPresentationMetadata),
]

var byIdentifier: [String: UTType] = [:]
for (_, t) in constants { byIdentifier[t.identifier] = t }
var queue = constants.map { $0.1 }
while let t = queue.popLast() {
    for s in t.supertypes where byIdentifier[s.identifier] == nil { byIdentifier[s.identifier] = s; queue.append(s) }
}

/// The supertypes of `t` that no other supertype of `t` conforms to.
func directParents(_ t: UTType) -> [String] {
    let all = t.supertypes
    return all.filter { p in !all.contains { s in s != p && s.supertypes.contains(p) } }.map { $0.identifier }.sorted()
}
func lit(_ s: String?) -> String {
    guard let s else { return "nil" }
    return "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}
func list(_ a: [String]) -> String { "[" + a.map { lit($0) }.joined(separator: ", ") + "]" }

print("// Generated by tools/uttypes/dump-core-types.swift from the macOS SDK's UTCoreTypes. Do not edit.")
print("// Columns: identifier, direct supertypes, filename extensions, MIME types, description, reference URL, version.")
print("")
print("let utCoreTypesTable: [UTTypeRecord] = [")
for id in byIdentifier.keys.sorted() {
    let t = byIdentifier[id]!
    let ext = t.tags[.filenameExtension] ?? [], mime = t.tags[.mimeType] ?? []
    print("    UTTypeRecord(\(lit(id)), \(list(directParents(t))), \(list(ext)), \(list(mime)), \(lit(t.localizedDescription)), \(lit(t.referenceURL?.absoluteString)), \(t.version.map(String.init) ?? "nil")),")
}
print("]")
print("")
print("extension UTType {")
for (name, t) in constants {
    print("    public static var \(name): UTType { UTType(coreType: \(lit(t.identifier))) }")
}
print("}")
}
if #available(macOS 15.2, *) { main() } else { fatalError("needs macOS 15.2") }
