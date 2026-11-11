// NSDiffableDataSourceSnapshot
// Hand-written (ADR-0029). Seeded from the generated stub.
//
// A value type: sections in order, each with its items in order. Identifiers are compared by
// their Hashable conformance, and each must be unique in the whole snapshot (an item may not
// appear in two sections); breaking that, or naming an identifier the snapshot does not hold as
// an anchor, is a precondition failure, as on macOS. Reload marks are carried to `apply` and
// cleared by it (`snapshot()` hands back a snapshot without them).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot
@available(macOS 10.15, *)
public struct NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType> where SectionIdentifierType : Hashable, ItemIdentifierType : Hashable {
    private var _sections: [SectionIdentifierType] = []
    private var _items: [SectionIdentifierType: [ItemIdentifierType]] = [:]
    private var _sectionOfItem: [ItemIdentifierType: SectionIdentifierType] = [:]
    internal var _reloadedItems = Set<ItemIdentifierType>()
    internal var _reloadedSections = Set<SectionIdentifierType>()

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot/init()
    public init() { }

    // MARK: Reading

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot/numberofitems
    public var numberOfItems: Int { _sectionOfItem.count }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot/numberofsections
    public var numberOfSections: Int { _sections.count }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot/sectionidentifiers
    public var sectionIdentifiers: [SectionIdentifierType] { _sections }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot/itemidentifiers
    public var itemIdentifiers: [ItemIdentifierType] { _sections.flatMap { _items[$0] ?? [] } }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot/numberofitems(insection:)
    public func numberOfItems(inSection identifier: SectionIdentifierType) -> Int {
        _requireSection(identifier, "count the items of")
        return _items[identifier]?.count ?? 0
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot/itemidentifiers(insection:)
    public func itemIdentifiers(inSection identifier: SectionIdentifierType) -> [ItemIdentifierType] {
        _requireSection(identifier, "read the items of")
        return _items[identifier] ?? []
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot/sectionidentifier(containingitem:)
    public func sectionIdentifier(containingItem identifier: ItemIdentifierType) -> SectionIdentifierType? { _sectionOfItem[identifier] }
    /// The item's index in `itemIdentifiers` (across all sections).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot/indexofitem(_:)
    public func indexOfItem(_ identifier: ItemIdentifierType) -> Int? {
        guard let section = _sectionOfItem[identifier] else { return nil }
        var offset = 0
        for s in _sections {
            if s == section { return _items[s].flatMap { $0.firstIndex(of: identifier) }.map { offset + $0 } }
            offset += _items[s]?.count ?? 0
        }
        return nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot/indexofsection(_:)
    public func indexOfSection(_ identifier: SectionIdentifierType) -> Int? { _items[identifier] == nil ? nil : _sections.firstIndex(of: identifier) }

    // MARK: Items

    /// Appends to `sectionIdentifier`, or to the last section when it is nil.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot/appenditems(_:tosection:)
    public mutating func appendItems(_ identifiers: [ItemIdentifierType], toSection sectionIdentifier: SectionIdentifierType? = nil) {
        let section: SectionIdentifierType
        if let sectionIdentifier {
            _requireSection(sectionIdentifier, "append items to")
            section = sectionIdentifier
        } else {
            guard let last = _sections.last else {
                preconditionFailure("NSDiffableDataSourceSnapshot: there are currently no sections in the snapshot. Add a section before appending items.")
            }
            section = last
        }
        _claim(identifiers, for: section)
        _items[section, default: []].append(contentsOf: identifiers)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot/insertitems(_:beforeitem:)
    public mutating func insertItems(_ identifiers: [ItemIdentifierType], beforeItem beforeIdentifier: ItemIdentifierType) {
        _insertItems(identifiers, at: beforeIdentifier, after: false)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot/insertitems(_:afteritem:)
    public mutating func insertItems(_ identifiers: [ItemIdentifierType], afterItem afterIdentifier: ItemIdentifierType) {
        _insertItems(identifiers, at: afterIdentifier, after: true)
    }
    /// Identifiers the snapshot does not hold are ignored.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot/deleteitems(_:)
    public mutating func deleteItems(_ identifiers: [ItemIdentifierType]) {
        var bySection: [SectionIdentifierType: Set<ItemIdentifierType>] = [:]
        for id in identifiers {
            guard let s = _sectionOfItem.removeValue(forKey: id) else { continue }
            bySection[s, default: []].insert(id)
            _reloadedItems.remove(id)
        }
        for (s, gone) in bySection { _items[s]?.removeAll { gone.contains($0) } }
    }
    /// Removes every item and every section.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot/deleteallitems()
    public mutating func deleteAllItems() {
        _sections = []
        _items = [:]
        _sectionOfItem = [:]
        _reloadedItems = []
        _reloadedSections = []
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot/moveitem(_:beforeitem:)
    public mutating func moveItem(_ identifier: ItemIdentifierType, beforeItem toIdentifier: ItemIdentifierType) {
        _moveItem(identifier, to: toIdentifier, after: false)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot/moveitem(_:afteritem:)
    public mutating func moveItem(_ identifier: ItemIdentifierType, afterItem toIdentifier: ItemIdentifierType) {
        _moveItem(identifier, to: toIdentifier, after: true)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot/reloaditems(_:)
    public mutating func reloadItems(_ identifiers: [ItemIdentifierType]) {
        for id in identifiers {
            precondition(_sectionOfItem[id] != nil, "NSDiffableDataSourceSnapshot: invalid item identifier specified for reload: \(id)")
            _reloadedItems.insert(id)
        }
    }

    // MARK: Sections

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot/appendsections(_:)
    public mutating func appendSections(_ identifiers: [SectionIdentifierType]) {
        _claimSections(identifiers)
        _sections.append(contentsOf: identifiers)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot/insertsections(_:beforesection:)
    public mutating func insertSections(_ identifiers: [SectionIdentifierType], beforeSection toIdentifier: SectionIdentifierType) {
        _insertSections(identifiers, at: toIdentifier, after: false)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot/insertsections(_:aftersection:)
    public mutating func insertSections(_ identifiers: [SectionIdentifierType], afterSection toIdentifier: SectionIdentifierType) {
        _insertSections(identifiers, at: toIdentifier, after: true)
    }
    /// Deletes the sections and their items; identifiers the snapshot does not hold are ignored.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot/deletesections(_:)
    public mutating func deleteSections(_ identifiers: [SectionIdentifierType]) {
        let gone = Set(identifiers)
        for s in gone {
            guard let items = _items.removeValue(forKey: s) else { continue }
            for id in items { _sectionOfItem[id] = nil; _reloadedItems.remove(id) }
            _reloadedSections.remove(s)
        }
        _sections.removeAll { gone.contains($0) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot/movesection(_:beforesection:)
    public mutating func moveSection(_ identifier: SectionIdentifierType, beforeSection toIdentifier: SectionIdentifierType) {
        _moveSection(identifier, to: toIdentifier, after: false)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot/movesection(_:aftersection:)
    public mutating func moveSection(_ identifier: SectionIdentifierType, afterSection toIdentifier: SectionIdentifierType) {
        _moveSection(identifier, to: toIdentifier, after: true)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdiffabledatasourcesnapshot/reloadsections(_:)
    public mutating func reloadSections(_ identifiers: [SectionIdentifierType]) {
        for s in identifiers {
            _requireSection(s, "reload")
            _reloadedSections.insert(s)
        }
    }

    // MARK: Internals

    /// The snapshot as a data source reads it: sections in order with their items.
    internal var _contents: [(section: SectionIdentifierType, items: [ItemIdentifierType])] {
        _sections.map { ($0, _items[$0] ?? []) }
    }
    internal func _items(at sectionIndex: Int) -> [ItemIdentifierType] { _items[_sections[sectionIndex]] ?? [] }

    /// The same contents without reload marks.
    internal var _withoutReloads: Self {
        var s = self
        s._reloadedItems = []
        s._reloadedSections = []
        return s
    }

    private func _requireSection(_ s: SectionIdentifierType, _ what: String) {
        precondition(_items[s] != nil, "NSDiffableDataSourceSnapshot: cannot \(what) section \(s): it is not in the snapshot")
    }

    private mutating func _claim(_ identifiers: [ItemIdentifierType], for section: SectionIdentifierType) {
        var batch = Set<ItemIdentifierType>()
        for id in identifiers {
            precondition(batch.insert(id).inserted && _sectionOfItem[id] == nil,
                         "NSDiffableDataSourceSnapshot: supplied item identifiers are not unique. Duplicate identifier: \(id)")
        }
        for id in identifiers { _sectionOfItem[id] = section }
    }

    private mutating func _claimSections(_ identifiers: [SectionIdentifierType]) {
        var batch = Set<SectionIdentifierType>()
        for s in identifiers {
            precondition(batch.insert(s).inserted && _items[s] == nil,
                         "NSDiffableDataSourceSnapshot: supplied section identifiers are not unique. Duplicate identifier: \(s)")
        }
        for s in identifiers { _items[s] = [] }
    }

    private mutating func _insertItems(_ identifiers: [ItemIdentifierType], at anchor: ItemIdentifierType, after: Bool) {
        guard let section = _sectionOfItem[anchor], let i = _items[section]?.firstIndex(of: anchor) else {
            preconditionFailure("NSDiffableDataSourceSnapshot: invalid item identifier specified for insert \(after ? "after" : "before"): \(anchor) is not in the snapshot")
        }
        _claim(identifiers, for: section)
        _items[section]!.insert(contentsOf: identifiers, at: after ? i + 1 : i)
    }

    private mutating func _moveItem(_ identifier: ItemIdentifierType, to anchor: ItemIdentifierType, after: Bool) {
        precondition(identifier != anchor, "NSDiffableDataSourceSnapshot: identifier for move cannot be the same as the anchor: \(identifier)")
        guard let from = _sectionOfItem[identifier] else {
            preconditionFailure("NSDiffableDataSourceSnapshot: invalid item identifier specified for move: \(identifier) is not in the snapshot")
        }
        guard let to = _sectionOfItem[anchor] else {
            preconditionFailure("NSDiffableDataSourceSnapshot: invalid anchor item identifier specified for move: \(anchor) is not in the snapshot")
        }
        _items[from]!.removeAll { $0 == identifier }
        let i = _items[to]!.firstIndex(of: anchor)!
        _items[to]!.insert(identifier, at: after ? i + 1 : i)
        _sectionOfItem[identifier] = to
    }

    private mutating func _insertSections(_ identifiers: [SectionIdentifierType], at anchor: SectionIdentifierType, after: Bool) {
        guard _items[anchor] != nil, let i = _sections.firstIndex(of: anchor) else {
            preconditionFailure("NSDiffableDataSourceSnapshot: invalid section identifier specified for insert \(after ? "after" : "before"): \(anchor) is not in the snapshot")
        }
        _claimSections(identifiers)
        _sections.insert(contentsOf: identifiers, at: after ? i + 1 : i)
    }

    private mutating func _moveSection(_ identifier: SectionIdentifierType, to anchor: SectionIdentifierType, after: Bool) {
        precondition(identifier != anchor, "NSDiffableDataSourceSnapshot: section identifier for move cannot be the same as the anchor: \(identifier)")
        _requireSection(identifier, "move")
        _requireSection(anchor, "move relative to")
        _sections.removeAll { $0 == identifier }
        let i = _sections.firstIndex(of: anchor)!
        _sections.insert(identifier, at: after ? i + 1 : i)
    }
}
