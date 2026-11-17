// corelibs Foundation's keyed unarchiver records a decoding error (and, with its default
// failure policy, aborts) when `decodeObject(forKey:)` is asked for a key the archive does
// not have; Apple's returns nil. Optional keys go through this. Hand-written support code,
// not AppKit API.

import Foundation

extension NSCoder {
    /// The object for `key`, or nil when the archive has no such key (on every Foundation).
    internal func _decodeObjectIfPresent(forKey key: String) -> Any? {
        containsValue(forKey: key) ? decodeObject(forKey: key) : nil
    }
}
