// NSSortDescriptor on every Foundation: Apple's descriptors carry a key string (key-value
// coding) or a key path; swift-corelibs-foundation has only key paths, and its `key` and
// `init(key:ascending:)` are unavailable. The table compares and re-creates descriptors
// through these helpers so the same code builds everywhere.

import Foundation

extension NSSortDescriptor {
    /// What the descriptor sorts by, comparable across descriptors: the key path, or on
    /// Apple's Foundation the key string when no key path was given.
    var _sortIdentity: AnyHashable? {
        if let kp = keyPath { return AnyHashable(kp) }
        #if canImport(Darwin)
        return key.map { AnyHashable($0) }
        #else
        return nil
        #endif
    }

    /// The same descriptor with a new direction.
    func _with(ascending: Bool) -> NSSortDescriptor {
        if ascending == self.ascending { return self }
        #if canImport(Darwin)
        if keyPath != nil, let reversed = reversedSortDescriptor as? NSSortDescriptor { return reversed }
        return NSSortDescriptor(key: key, ascending: ascending)
        #else
        return NSSortDescriptor(keyPath: keyPath!, ascending: ascending)
        #endif
    }
}
