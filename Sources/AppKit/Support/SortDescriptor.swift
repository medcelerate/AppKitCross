// NSSortDescriptor on every Foundation: Apple's descriptors carry a key string (key-value
// coding) or an optional key path; swift-corelibs-foundation has only a key path, and its
// `key` and `init(key:ascending:)` are unavailable. The table compares and re-creates
// descriptors through these helpers so the same code builds everywhere.

import Foundation

extension NSSortDescriptor {
    /// What the descriptor sorts by, comparable across descriptors: the key path, or on
    /// Apple's Foundation the key string when no key path was given.
    var _sortIdentity: AnyHashable? {
        #if canImport(Darwin)
        if let kp = keyPath { return AnyHashable(kp) }
        return key.map { AnyHashable($0) }
        #else
        return AnyHashable(keyPath)
        #endif
    }

    /// The same descriptor with a new direction.
    func _with(ascending: Bool) -> NSSortDescriptor {
        if ascending == self.ascending { return self }
        #if canImport(Darwin)
        if keyPath != nil, let reversed = reversedSortDescriptor as? NSSortDescriptor { return reversed }
        return NSSortDescriptor(key: key, ascending: ascending)
        #else
        return reversedSortDescriptor as! NSSortDescriptor
        #endif
    }
}
