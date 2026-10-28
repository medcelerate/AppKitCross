//
//  PlatformHelpers.swift
//  Combine (ported from OpenCombine)
//
//  AppKitWin: the two remaining entry points of OpenCombine's `COpenCombineHelpers`
//  C++ target, in Swift. See Locking.swift for the locks.

import Foundation

#if os(Windows)
import WinSDK
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

private let identifierLock = NSLock()
private var nextIdentifier: UInt64 = 0

/// The process-wide counter behind `CombineIdentifier()`.
internal func __nextCombineIdentifier() -> UInt64 {
    identifierLock.lock()
    defer { identifierLock.unlock() }
    let value = nextIdentifier
    nextIdentifier &+= 1
    return value
}

/// Stops the process in the debugger (`Publishers.Breakpoint`).
internal func __stopInDebugger() {
#if os(Windows)
    DebugBreak()
#else
    raise(SIGTRAP)
#endif
}
