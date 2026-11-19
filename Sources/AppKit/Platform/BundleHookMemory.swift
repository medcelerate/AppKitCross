// What the Bundle hooks (ADR-0045, Support/BundleHooks.swift) need from the system: a
// Foundation symbol's address and a write to a read-only page of Foundation's class metadata.
// POSIX here (dlsym, mprotect); Windows in Win32/Win32BundleHookMemory.swift.

import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

#if !os(Windows)
/// The address of an exported symbol of the loaded Foundation.
func _platformFoundationSymbol(_ name: String) -> UnsafeRawPointer? {
    guard let handle = dlopen(nil, RTLD_NOW) else { return nil }
    return dlsym(handle, name).map { UnsafeRawPointer($0) }
}

/// Stores a pointer into a (possibly read-only) metadata slot. The page stays writable: it
/// holds Swift class metadata, which the runtime may update itself.
func _platformStorePointer(_ value: UnsafeRawPointer, at slot: UnsafeMutableRawPointer) -> Bool {
    let page = Int(sysconf(Int32(_SC_PAGESIZE)))
    guard page > 0, let start = UnsafeMutableRawPointer(bitPattern: Int(bitPattern: slot) & ~(page - 1)) else { return false }
    let length = (Int(bitPattern: slot) + MemoryLayout<UnsafeRawPointer>.size) - Int(bitPattern: start) > page ? 2 * page : page
    guard mprotect(start, length, PROT_READ | PROT_WRITE) == 0 else { return false }
    slot.storeBytes(of: value, as: UnsafeRawPointer.self)
    return true
}
#endif
