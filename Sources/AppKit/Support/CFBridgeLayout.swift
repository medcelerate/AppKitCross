// A layout guard for NSObject subclasses on Windows and Linux (ADR-0030).
//
// swift-corelibs-foundation's NSObject has no instance variables, so CoreFoundation reads
// a Swift object's CF type ID from its first stored word (bits 8-17 of CFRuntimeBase's
// _cfinfoa). When that word decodes to type 0 (NotAType), CFEqual and CFHash do not
// dispatch to Swift and halt: CFAttributedString traps comparing two such values in
// adjacent runs (two distinct black NSColors, or two attachments' run delegates side by
// side). Classes that end up as attribute values declare this as their first stored
// property so the type ID is never 0; CF then sees a Swift object and calls isEqual/hash.
//
// A first word holding a pointer is worse than 0: the type ID comes from the heap address,
// so the trap is intermittent (one run in many, depending on where an object landed). The
// CoreText string NSLayoutManager builds holds CTFont, CGColor and CTParagraphStyle values,
// so those (and CTTextTab, CTFontDescriptor, CTRunDelegate) carry the same word in the
// CoreText and CoreGraphics modules, and CGColor is an NSObject so it is not boxed (a
// box's first word is the boxed object's address). CFBridgeLayoutTests reads the word of
// every attribute value class: add a new one there.

#if !canImport(Darwin)
/// A CF info word with a non-zero type ID that no CF class has (the last table slot).
let _swiftObjectCFInfo: UInt64 = 0x3FF << 8
#endif
