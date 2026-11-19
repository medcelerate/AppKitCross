// The Bundle hooks' system calls on Windows (ADR-0045): Foundation.dll's exported symbol and
// a VirtualProtect around the vtable write (the old protection is put back).

#if os(Windows)
import Foundation
import WinSDK

func _platformFoundationSymbol(_ name: String) -> UnsafeRawPointer? {
    let module = "Foundation.dll".withCString(encodedAs: UTF16.self) { GetModuleHandleW($0) }
    guard let module, let proc = GetProcAddress(module, name) else { return nil }
    return unsafeBitCast(proc, to: UnsafeRawPointer.self)
}

func _platformStorePointer(_ value: UnsafeRawPointer, at slot: UnsafeMutableRawPointer) -> Bool {
    var old: DWORD = 0
    let size = SIZE_T(MemoryLayout<UnsafeRawPointer>.size)
    guard VirtualProtect(slot, size, DWORD(PAGE_READWRITE), &old) else { return false }
    slot.storeBytes(of: value, as: UnsafeRawPointer.self)
    var ignored: DWORD = 0
    _ = VirtualProtect(slot, size, old, &ignored)
    return true
}
#endif
