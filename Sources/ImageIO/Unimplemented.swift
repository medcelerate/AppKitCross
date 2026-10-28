// Every ImageIO member that cannot be implemented over the platform codecs yet calls
// this, so a missing feature fails loudly with the symbol name instead of misbehaving.

@inline(never)
func unimplemented(_ symbol: String = #function, file: StaticString = #fileID, line: UInt = #line) -> Never {
    fatalError("ImageIO: `\(symbol)` is not implemented yet", file: file, line: line)
}
