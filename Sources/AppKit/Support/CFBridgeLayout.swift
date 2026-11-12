// A layout guard for NSObject subclasses on Windows and Linux (ADR-0030).
//
// swift-corelibs-foundation's NSObject has no instance variables, so CoreFoundation reads
// a Swift object's CF type ID from its first stored word (bits 8-17 of CFRuntimeBase's
// _cfinfoa). When that word decodes to type 0 (NotAType), CFEqual and CFHash do not
// dispatch to Swift and halt: CFAttributedString traps comparing two such values in
// adjacent runs (two distinct black NSColors, or two attachments' run delegates side by
// side). Classes that end up as attribute values declare this as their first stored
// property so the type ID is never 0; CF then sees a Swift object and calls isEqual/hash.

#if !canImport(Darwin)
/// A CF info word with a non-zero type ID that no CF class has (the last table slot).
let _swiftObjectCFInfo: UInt64 = 0x3FF << 8
#endif
