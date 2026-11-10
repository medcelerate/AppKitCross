// NSToolbarDelegate: the toolbar's source of items and identifiers.
//
// `toolbarDefaultItemIdentifiers` and `toolbarAllowedItemIdentifiers` are required in
// AppKit; the other requirements are `@optional` there and carry the defaults AppKit
// assumes when a delegate leaves them out (no selectable items, no immovable items, every
// insertion allowed, no item for an unknown identifier).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbardelegate
public protocol NSToolbarDelegate: NSObjectProtocol {
    @MainActor func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem?
    @available(macOS 13.0, *)
    @MainActor func toolbar(_ toolbar: NSToolbar, itemIdentifier: NSToolbarItem.Identifier, canBeInsertedAt index: Int) -> Bool
    @MainActor func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier]
    @MainActor func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier]
    @available(macOS 10.10, *)
    @MainActor func toolbarDidRemoveItem(_ notification: Notification)
    @available(macOS 13.0, *)
    @MainActor func toolbarImmovableItemIdentifiers(_ toolbar: NSToolbar) -> Set<NSToolbarItem.Identifier>
    @MainActor func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier]
    @available(macOS 10.10, *)
    @MainActor func toolbarWillAddItem(_ notification: Notification)
}

// Optional requirements (ObjC `@optional`), modelled as defaulted requirements.
extension NSToolbarDelegate {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbardelegate/toolbar(_:itemforitemidentifier:willbeinsertedintotoolbar:)
    @MainActor public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? { return nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbardelegate/toolbar(_:itemidentifier:canbeinsertedat:)
    @available(macOS 13.0, *)
    @MainActor public func toolbar(_ toolbar: NSToolbar, itemIdentifier: NSToolbarItem.Identifier, canBeInsertedAt index: Int) -> Bool { return true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbardelegate/toolbaralloweditemidentifiers(_:)
    @MainActor public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { unimplementedOptionalRequirement() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbardelegate/toolbardefaultitemidentifiers(_:)
    @MainActor public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { unimplementedOptionalRequirement() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbardelegate/toolbardidremoveitem(_:)
    @available(macOS 10.10, *)
    @MainActor public func toolbarDidRemoveItem(_ notification: Notification) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbardelegate/toolbarimmovableitemidentifiers(_:)
    @available(macOS 13.0, *)
    @MainActor public func toolbarImmovableItemIdentifiers(_ toolbar: NSToolbar) -> Set<NSToolbarItem.Identifier> { [] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbardelegate/toolbarselectableitemidentifiers(_:)
    @MainActor public func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbardelegate/toolbarwilladditem(_:)
    @available(macOS 10.10, *)
    @MainActor public func toolbarWillAddItem(_ notification: Notification) { }
}
