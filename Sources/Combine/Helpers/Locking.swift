//
//  Locking.swift
//  Combine (ported from OpenCombine)
//
//  Created by Sergej Jaskiewicz on 11.06.2019.
//
//  AppKitCross: OpenCombine implements these locks in a C++ helper target over
//  os_unfair_lock / pthread / std::mutex. This port is only built with corelibs
//  Foundation (Windows and Linux), where `NSLock` and `NSRecursiveLock` are thin
//  wrappers over SRWLOCK / pthread mutexes, so the locks are plain Swift here and the
//  C++ target is gone. The allocate/deallocate API shape is kept so the rest of the
//  sources are unchanged from upstream.

import Foundation

internal struct __UnfairLock { // swiftlint:disable:this type_name

    private let lock_: NSLock

    private init() { lock_ = NSLock() }

    internal static func allocate() -> UnfairLock { return .init() }

    internal func lock() { lock_.lock() }

    internal func unlock() { lock_.unlock() }

    /// `NSLock` does not expose its owner; upstream only checks this on Darwin.
    internal func assertOwner() {}

    internal func deallocate() {}
}

internal struct __UnfairRecursiveLock { // swiftlint:disable:this type_name

    private let lock_: NSRecursiveLock

    private init() { lock_ = NSRecursiveLock() }

    internal static func allocate() -> UnfairRecursiveLock { return .init() }

    internal func lock() { lock_.lock() }

    internal func unlock() { lock_.unlock() }

    internal func deallocate() {}
}

internal typealias UnfairLock = __UnfairLock
internal typealias UnfairRecursiveLock = __UnfairRecursiveLock
