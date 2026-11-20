// Support for stubs: a member of Apple's OSLog surface the port declares but does not
// model fails loudly with its name instead of misbehaving.

/// Terminates with a message naming the unimplemented OSLog symbol.
@inline(never)
func unimplemented(_ symbol: String = #function, file: StaticString = #fileID, line: UInt = #line) -> Never {
    fatalError("AppKitCross: `\(symbol)` is not implemented yet", file: file, line: line)
}
