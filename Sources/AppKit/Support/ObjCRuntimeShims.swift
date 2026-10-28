// Types the AppKit API surface borrows from the Objective-C runtime that Foundation on
// Windows does not provide. Selectors are plain names here; dispatch goes through
// NSResponder.tryToPerform and the target/action registry rather than objc_msgSend.

#if !canImport(ObjectiveC)
public struct Selector: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let name: String
    public init(_ name: String) { self.name = name }
    public init(stringLiteral value: String) { self.name = value }
    public var description: String { name }
}

public func NSStringFromSelector(_ sel: Selector) -> String { sel.name }
public func NSSelectorFromString(_ name: String) -> Selector { Selector(name) }
#endif
