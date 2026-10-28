// Support for stubs. Every not-yet-implemented AppKit member calls one of these so
// that a missing feature fails loudly with the symbol name instead of misbehaving.

/// Terminates with a message naming the unimplemented AppKit symbol.
@inline(never)
public func unimplemented(_ symbol: String = #function, file: StaticString = #fileID, line: UInt = #line) -> Never {
    fatalError("AppKitWin: `\(symbol)` is not implemented yet", file: file, line: line)
}

/// Default body for an optional protocol requirement whose AppKit default behaviour is
/// not yet modelled. Optional requirements that return `Void` or an optional have
/// harmless defaults; the remaining ones end up here until a hand-written protocol
/// extension provides the real AppKit default.
@inline(never)
public func unimplementedOptionalRequirement(_ symbol: String = #function, file: StaticString = #fileID, line: UInt = #line) -> Never {
    fatalError("AppKitWin: optional requirement `\(symbol)` has no default yet", file: file, line: line)
}
