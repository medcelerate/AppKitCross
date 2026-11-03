// Conformance between pasteboard type identifiers, for matching dragged types against
// registered ones without AppKit depending on UniformTypeIdentifiers: the uniform types
// pasteboards commonly carry and their parents.

import Foundation

public enum _NSPasteboardTypeConformance {
    /// Parents of the common types (each conforms to all of its parents, transitively).
    private static let parents: [String: [String]] = [
        "public.utf8-plain-text": ["public.plain-text"],
        "public.utf16-plain-text": ["public.plain-text"],
        "public.utf16-external-plain-text": ["public.plain-text"],
        "public.plain-text": ["public.text"],
        "public.rtf": ["public.text"],
        "public.html": ["public.text"],
        "public.text": ["public.data", "public.content"],
        "public.file-url": ["public.url"],
        "public.url": ["public.data"],
        "public.png": ["public.image"],
        "public.jpeg": ["public.image"],
        "public.tiff": ["public.image"],
        "com.compuserve.gif": ["public.image"],
        "public.image": ["public.data", "public.content"],
        "public.json": ["public.text"],
        "public.data": ["public.item"],
        "public.content": ["public.item"],
    ]

    /// True when `type` is `other` or conforms to it.
    public static func conforms(_ type: String, to other: String) -> Bool {
        if type == other { return true }
        var seen: Set<String> = []
        var queue = parents[type] ?? []
        while let t = queue.first {
            queue.removeFirst()
            if t == other { return true }
            if seen.insert(t).inserted { queue += parents[t] ?? [] }
        }
        return false
    }
}
