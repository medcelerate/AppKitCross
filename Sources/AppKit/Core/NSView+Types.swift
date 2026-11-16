// NSView's nested types (hand-written; moved here from the generated NSView+Types.swift,
// ADR-0037). apigen never emits a nested type that Sources/AppKit/Core declares, so with every
// nested type of NSView declared here the generator writes no Generated/NSView+Types.swift.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(QuartzCore)
import QuartzCore
#endif
#if canImport(CoreText)
import CoreText
#endif

extension NSView {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/backgroundstyle
    public enum BackgroundStyle: Int, Sendable, Equatable, Hashable {
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/backgroundstyle/emphasized
        case emphasized = 1
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/backgroundstyle/lowered
        case lowered = 3
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/backgroundstyle/normal
        case normal = 0
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/backgroundstyle/raised
        case raised = 2
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/backgroundstyle/dark
        static public var dark: NSView.BackgroundStyle { NSView.BackgroundStyle(rawValue: 1)! }
        // SKIPPED (constrained extension): func hash(into hasher: inout Hasher)
        // SKIPPED (constrained extension): var hashValue: Int { get }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/backgroundstyle/light
        static public var light: NSView.BackgroundStyle { NSView.BackgroundStyle(rawValue: 0)! }
    }
}

extension NSView {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/autoresizingmask
    public struct AutoresizingMask: OptionSet, Sendable, Equatable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/autoresizingmask/height
        static public var height: NSView.AutoresizingMask { NSView.AutoresizingMask(rawValue: 16) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/autoresizingmask/maxxmargin
        static public var maxXMargin: NSView.AutoresizingMask { NSView.AutoresizingMask(rawValue: 4) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/autoresizingmask/maxymargin
        static public var maxYMargin: NSView.AutoresizingMask { NSView.AutoresizingMask(rawValue: 32) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/autoresizingmask/minxmargin
        static public var minXMargin: NSView.AutoresizingMask { NSView.AutoresizingMask(rawValue: 1) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/autoresizingmask/minymargin
        static public var minYMargin: NSView.AutoresizingMask { NSView.AutoresizingMask(rawValue: 8) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/autoresizingmask/none
        static public var none: NSView.AutoresizingMask { NSView.AutoresizingMask(rawValue: 0) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/autoresizingmask/width
        static public var width: NSView.AutoresizingMask { NSView.AutoresizingMask(rawValue: 2) }
    }
}

extension NSView {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layercontentsredrawpolicy
    public enum LayerContentsRedrawPolicy: Int, Sendable, Equatable, Hashable {
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layercontentsredrawpolicy/beforeviewresize
        case beforeViewResize = 3
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layercontentsredrawpolicy/crossfade
        case crossfade = 4
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layercontentsredrawpolicy/duringviewresize
        case duringViewResize = 2
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layercontentsredrawpolicy/never
        case never = 0
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layercontentsredrawpolicy/onsetneedsdisplay
        case onSetNeedsDisplay = 1
        // SKIPPED (constrained extension): func hash(into hasher: inout Hasher)
        // SKIPPED (constrained extension): var hashValue: Int { get }
    }
}

extension NSView {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layercontentsplacement
    public enum LayerContentsPlacement: Int, Sendable, Equatable, Hashable {
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layercontentsplacement/bottom
        case bottom = 8
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layercontentsplacement/bottomleft
        case bottomLeft = 9
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layercontentsplacement/bottomright
        case bottomRight = 7
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layercontentsplacement/center
        case center = 3
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layercontentsplacement/left
        case left = 10
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layercontentsplacement/right
        case right = 6
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layercontentsplacement/scaleaxesindependently
        case scaleAxesIndependently = 0
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layercontentsplacement/scaleproportionallytofill
        case scaleProportionallyToFill = 2
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layercontentsplacement/scaleproportionallytofit
        case scaleProportionallyToFit = 1
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layercontentsplacement/top
        case top = 4
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layercontentsplacement/topleft
        case topLeft = 11
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layercontentsplacement/topright
        case topRight = 5
        // SKIPPED (constrained extension): func hash(into hasher: inout Hasher)
        // SKIPPED (constrained extension): var hashValue: Int { get }
    }
}

extension NSView {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/trackingrecttag
    public typealias TrackingRectTag = Int
}

extension NSView {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/tooltiptag
    public typealias ToolTipTag = Int
}

extension NSView {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/fullscreenmodeoptionkey
    public struct FullScreenModeOptionKey: RawRepresentable, Hashable, Equatable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }

        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/fullscreenmodeoptionkey/fullscreenmodeallscreens
        static public var fullScreenModeAllScreens: NSView.FullScreenModeOptionKey { NSView.FullScreenModeOptionKey(rawValue: "NSFullScreenModeAllScreens") }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/fullscreenmodeoptionkey/fullscreenmodeapplicationpresentationoptions
        static public var fullScreenModeApplicationPresentationOptions: NSView.FullScreenModeOptionKey { NSView.FullScreenModeOptionKey(rawValue: "NSFullScreenModeApplicationPresentationOptions") }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/fullscreenmodeoptionkey/fullscreenmodesetting
        static public var fullScreenModeSetting: NSView.FullScreenModeOptionKey { NSView.FullScreenModeOptionKey(rawValue: "NSFullScreenModeSetting") }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/fullscreenmodeoptionkey/fullscreenmodewindowlevel
        static public var fullScreenModeWindowLevel: NSView.FullScreenModeOptionKey { NSView.FullScreenModeOptionKey(rawValue: "NSFullScreenModeWindowLevel") }
    }
}

extension NSView {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/definitionoptionkey
    public struct DefinitionOptionKey: RawRepresentable, Hashable, Equatable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }

        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/definitionoptionkey/presentationtype
        static public var presentationType: NSView.DefinitionOptionKey { NSView.DefinitionOptionKey(rawValue: "NSDefinitionPresentationTypeKey") }
    }
}

extension NSView {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/definitionpresentationtype
    public struct DefinitionPresentationType: RawRepresentable, Hashable, Equatable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }

        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/definitionpresentationtype/dictionaryapplication
        static public var dictionaryApplication: NSView.DefinitionPresentationType { NSView.DefinitionPresentationType(rawValue: "NSDefinitionPresentationTypeDictionaryApplication") }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/definitionpresentationtype/overlay
        static public var overlay: NSView.DefinitionPresentationType { NSView.DefinitionPresentationType(rawValue: "NSDefinitionPresentationTypeOverlay") }
    }
}

// MARK: - Layout regions (macOS 26)

@available(macOS 26.0, *)
extension NSView {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layoutregion
    /// A region of a view used for layout: its safe area or its layout margins, optionally
    /// adapted for a window's rounded corners along one axis. The port has no corner
    /// adaptation (no window corner radius is reported), so `cornerAdaptation` is recorded
    /// and compared but does not change the region's geometry.
    @available(macOS 26.0, *)
    public struct LayoutRegion: Hashable, Equatable {
        internal enum _Kind: Hashable { case safeArea, margins }
        internal let _kind: _Kind
        internal let _cornerAdaptation: NSView.LayoutRegion.AdaptivityAxis?

        internal init(_kind: _Kind, _cornerAdaptation: NSView.LayoutRegion.AdaptivityAxis?) {
            self._kind = _kind
            self._cornerAdaptation = _cornerAdaptation
        }

        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layoutregion/==(_:_:)
        public static func == (a: NSView.LayoutRegion, b: NSView.LayoutRegion) -> Bool {
            a._kind == b._kind && a._cornerAdaptation == b._cornerAdaptation
        }
        public func hash(into hasher: inout Hasher) {
            hasher.combine(_kind)
            hasher.combine(_cornerAdaptation)
        }
        public var hashValue: Int {
            var h = Hasher()
            hash(into: &h)
            return h.finalize()
        }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layoutregion/margins(corneradaptation:)
        public static func margins(cornerAdaptation: NSView.LayoutRegion.AdaptivityAxis? = nil) -> NSView.LayoutRegion {
            NSView.LayoutRegion(_kind: .margins, _cornerAdaptation: cornerAdaptation)
        }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layoutregion/safearea(corneradaptation:)
        public static func safeArea(cornerAdaptation: NSView.LayoutRegion.AdaptivityAxis? = nil) -> NSView.LayoutRegion {
            NSView.LayoutRegion(_kind: .safeArea, _cornerAdaptation: cornerAdaptation)
        }
    }
}

@available(macOS 26.0, *)
extension NSView.LayoutRegion {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layoutregion/adaptivityaxis
    @available(macOS 26.0, *)
    public enum AdaptivityAxis: Equatable, Hashable {
        case horizontal
        case vertical
    }
}

// MARK: - Invalidating property wrapper (macOS 12)

@available(macOS 12.0, *)
extension NSView {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidating
    /// Stores a value in an NSView subclass and, when a new value differs from the old one,
    /// runs the invalidation (display, layout, constraints, intrinsic size, restorable state)
    /// on the enclosing view. Works through the enclosing-instance subscript, so it is only
    /// usable on properties of NSView subclasses, as in AppKit.
    @available(macOS 12.0, *)
    @propertyWrapper public struct Invalidating<Value, InvalidationType> where Value : Equatable, InvalidationType : NSViewInvalidating {
        internal var value: Value
        internal let invalidation: InvalidationType

        // wrappedValue is unavailable in the SDK: the wrapper is reached through the
        // enclosing-instance subscript below, never directly.
        @available(*, unavailable, message: "@NSView.Invalidating is only available on properties of NSView subclasses")
        public var wrappedValue: Value {
            get { fatalError("@NSView.Invalidating is only available on properties of NSView subclasses") }
            set { fatalError("@NSView.Invalidating is only available on properties of NSView subclasses") }
        }

        @MainActor
        public static subscript<EnclosingSelf: NSView>(
            _enclosingInstance view: EnclosingSelf,
            wrapped wrappedKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Value>,
            storage storageKeyPath: ReferenceWritableKeyPath<EnclosingSelf, NSView.Invalidating<Value, InvalidationType>>
        ) -> Value {
            get { view[keyPath: storageKeyPath].value }
            set {
                let old = view[keyPath: storageKeyPath].value
                view[keyPath: storageKeyPath].value = newValue
                if old != newValue {
                    view[keyPath: storageKeyPath].invalidation.invalidate(view: view)
                }
            }
        }

        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidating/init(wrappedvalue:_:)
        public init(wrappedValue: Value, _ invalidation: InvalidationType) { self.value = wrappedValue; self.invalidation = invalidation }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidating/init(wrappedvalue:_:_:)
        public init<InvalidationType1, InvalidationType2>(wrappedValue: Value, _ invalidation1: InvalidationType1, _ invalidation2: InvalidationType2) where InvalidationType == NSView.Invalidations.Tuple<InvalidationType1, InvalidationType2>, InvalidationType1 : NSViewInvalidating, InvalidationType2 : NSViewInvalidating { self.init(wrappedValue: wrappedValue, NSView.Invalidations.Tuple(invalidation1, invalidation2)) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidating/init(wrappedvalue:_:_:_:)
        public init<InvalidationType1, InvalidationType2, InvalidationType3>(wrappedValue: Value, _ invalidation1: InvalidationType1, _ invalidation2: InvalidationType2, _ invalidation3: InvalidationType3) where InvalidationType == NSView.Invalidations.Tuple<NSView.Invalidations.Tuple<InvalidationType1, InvalidationType2>, InvalidationType3>, InvalidationType1 : NSViewInvalidating, InvalidationType2 : NSViewInvalidating, InvalidationType3 : NSViewInvalidating { self.init(wrappedValue: wrappedValue, NSView.Invalidations.Tuple(NSView.Invalidations.Tuple(invalidation1, invalidation2), invalidation3)) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidating/init(wrappedvalue:_:_:_:_:)
        public init<InvalidationType1, InvalidationType2, InvalidationType3, InvalidationType4>(wrappedValue: Value, _ invalidation1: InvalidationType1, _ invalidation2: InvalidationType2, _ invalidation3: InvalidationType3, _ invalidation4: InvalidationType4) where InvalidationType == NSView.Invalidations.Tuple<NSView.Invalidations.Tuple<InvalidationType1, InvalidationType2>, NSView.Invalidations.Tuple<InvalidationType3, InvalidationType4>>, InvalidationType1 : NSViewInvalidating, InvalidationType2 : NSViewInvalidating, InvalidationType3 : NSViewInvalidating, InvalidationType4 : NSViewInvalidating { self.init(wrappedValue: wrappedValue, NSView.Invalidations.Tuple(NSView.Invalidations.Tuple(invalidation1, invalidation2), NSView.Invalidations.Tuple(invalidation3, invalidation4))) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidating/init(wrappedvalue:_:_:_:_:_:)
        public init<InvalidationType1, InvalidationType2, InvalidationType3, InvalidationType4, InvalidationType5>(wrappedValue: Value, _ invalidation1: InvalidationType1, _ invalidation2: InvalidationType2, _ invalidation3: InvalidationType3, _ invalidation4: InvalidationType4, _ invalidation5: InvalidationType5) where InvalidationType == NSView.Invalidations.Tuple<NSView.Invalidations.Tuple<NSView.Invalidations.Tuple<InvalidationType1, InvalidationType2>, NSView.Invalidations.Tuple<InvalidationType3, InvalidationType4>>, InvalidationType5>, InvalidationType1 : NSViewInvalidating, InvalidationType2 : NSViewInvalidating, InvalidationType3 : NSViewInvalidating, InvalidationType4 : NSViewInvalidating, InvalidationType5 : NSViewInvalidating { self.init(wrappedValue: wrappedValue, NSView.Invalidations.Tuple(NSView.Invalidations.Tuple(NSView.Invalidations.Tuple(invalidation1, invalidation2), NSView.Invalidations.Tuple(invalidation3, invalidation4)), invalidation5)) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidating/init(wrappedvalue:_:_:_:_:_:_:)
        public init<InvalidationType1, InvalidationType2, InvalidationType3, InvalidationType4, InvalidationType5, InvalidationType6>(wrappedValue: Value, _ invalidation1: InvalidationType1, _ invalidation2: InvalidationType2, _ invalidation3: InvalidationType3, _ invalidation4: InvalidationType4, _ invalidation5: InvalidationType5, _ invalidation6: InvalidationType6) where InvalidationType == NSView.Invalidations.Tuple<NSView.Invalidations.Tuple<NSView.Invalidations.Tuple<InvalidationType1, InvalidationType2>, NSView.Invalidations.Tuple<InvalidationType3, InvalidationType4>>, NSView.Invalidations.Tuple<InvalidationType5, InvalidationType6>>, InvalidationType1 : NSViewInvalidating, InvalidationType2 : NSViewInvalidating, InvalidationType3 : NSViewInvalidating, InvalidationType4 : NSViewInvalidating, InvalidationType5 : NSViewInvalidating, InvalidationType6 : NSViewInvalidating { self.init(wrappedValue: wrappedValue, NSView.Invalidations.Tuple(NSView.Invalidations.Tuple(NSView.Invalidations.Tuple(invalidation1, invalidation2), NSView.Invalidations.Tuple(invalidation3, invalidation4)), NSView.Invalidations.Tuple(invalidation5, invalidation6))) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidating/init(wrappedvalue:_:_:_:_:_:_:_:)
        public init<InvalidationType1, InvalidationType2, InvalidationType3, InvalidationType4, InvalidationType5, InvalidationType6, InvalidationType7>(wrappedValue: Value, _ invalidation1: InvalidationType1, _ invalidation2: InvalidationType2, _ invalidation3: InvalidationType3, _ invalidation4: InvalidationType4, _ invalidation5: InvalidationType5, _ invalidation6: InvalidationType6, _ invalidation7: InvalidationType7) where InvalidationType == NSView.Invalidations.Tuple<NSView.Invalidations.Tuple<NSView.Invalidations.Tuple<InvalidationType1, InvalidationType2>, NSView.Invalidations.Tuple<InvalidationType3, InvalidationType4>>, NSView.Invalidations.Tuple<NSView.Invalidations.Tuple<InvalidationType5, InvalidationType6>, InvalidationType7>>, InvalidationType1 : NSViewInvalidating, InvalidationType2 : NSViewInvalidating, InvalidationType3 : NSViewInvalidating, InvalidationType4 : NSViewInvalidating, InvalidationType5 : NSViewInvalidating, InvalidationType6 : NSViewInvalidating, InvalidationType7 : NSViewInvalidating { self.init(wrappedValue: wrappedValue, NSView.Invalidations.Tuple(NSView.Invalidations.Tuple(NSView.Invalidations.Tuple(invalidation1, invalidation2), NSView.Invalidations.Tuple(invalidation3, invalidation4)), NSView.Invalidations.Tuple(NSView.Invalidations.Tuple(invalidation5, invalidation6), invalidation7))) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidating/init(wrappedvalue:_:_:_:_:_:_:_:_:)
        public init<InvalidationType1, InvalidationType2, InvalidationType3, InvalidationType4, InvalidationType5, InvalidationType6, InvalidationType7, InvalidationType8>(wrappedValue: Value, _ invalidation1: InvalidationType1, _ invalidation2: InvalidationType2, _ invalidation3: InvalidationType3, _ invalidation4: InvalidationType4, _ invalidation5: InvalidationType5, _ invalidation6: InvalidationType6, _ invalidation7: InvalidationType7, _ invalidation8: InvalidationType8) where InvalidationType == NSView.Invalidations.Tuple<NSView.Invalidations.Tuple<NSView.Invalidations.Tuple<InvalidationType1, InvalidationType2>, NSView.Invalidations.Tuple<InvalidationType3, InvalidationType4>>, NSView.Invalidations.Tuple<NSView.Invalidations.Tuple<InvalidationType5, InvalidationType6>, NSView.Invalidations.Tuple<InvalidationType7, InvalidationType8>>>, InvalidationType1 : NSViewInvalidating, InvalidationType2 : NSViewInvalidating, InvalidationType3 : NSViewInvalidating, InvalidationType4 : NSViewInvalidating, InvalidationType5 : NSViewInvalidating, InvalidationType6 : NSViewInvalidating, InvalidationType7 : NSViewInvalidating, InvalidationType8 : NSViewInvalidating { self.init(wrappedValue: wrappedValue, NSView.Invalidations.Tuple(NSView.Invalidations.Tuple(NSView.Invalidations.Tuple(invalidation1, invalidation2), NSView.Invalidations.Tuple(invalidation3, invalidation4)), NSView.Invalidations.Tuple(NSView.Invalidations.Tuple(invalidation5, invalidation6), NSView.Invalidations.Tuple(invalidation7, invalidation8)))) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidating/init(wrappedvalue:_:_:_:_:_:_:_:_:_:)
        public init<InvalidationType1, InvalidationType2, InvalidationType3, InvalidationType4, InvalidationType5, InvalidationType6, InvalidationType7, InvalidationType8, InvalidationType9>(wrappedValue: Value, _ invalidation1: InvalidationType1, _ invalidation2: InvalidationType2, _ invalidation3: InvalidationType3, _ invalidation4: InvalidationType4, _ invalidation5: InvalidationType5, _ invalidation6: InvalidationType6, _ invalidation7: InvalidationType7, _ invalidation8: InvalidationType8, _ invalidation9: InvalidationType9) where InvalidationType == NSView.Invalidations.Tuple<NSView.Invalidations.Tuple<NSView.Invalidations.Tuple<NSView.Invalidations.Tuple<InvalidationType1, InvalidationType2>, NSView.Invalidations.Tuple<InvalidationType3, InvalidationType4>>, NSView.Invalidations.Tuple<NSView.Invalidations.Tuple<InvalidationType5, InvalidationType6>, NSView.Invalidations.Tuple<InvalidationType7, InvalidationType8>>>, InvalidationType9>, InvalidationType1 : NSViewInvalidating, InvalidationType2 : NSViewInvalidating, InvalidationType3 : NSViewInvalidating, InvalidationType4 : NSViewInvalidating, InvalidationType5 : NSViewInvalidating, InvalidationType6 : NSViewInvalidating, InvalidationType7 : NSViewInvalidating, InvalidationType8 : NSViewInvalidating, InvalidationType9 : NSViewInvalidating { self.init(wrappedValue: wrappedValue, NSView.Invalidations.Tuple(NSView.Invalidations.Tuple(NSView.Invalidations.Tuple(NSView.Invalidations.Tuple(invalidation1, invalidation2), NSView.Invalidations.Tuple(invalidation3, invalidation4)), NSView.Invalidations.Tuple(NSView.Invalidations.Tuple(invalidation5, invalidation6), NSView.Invalidations.Tuple(invalidation7, invalidation8))), invalidation9)) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidating/init(wrappedvalue:_:_:_:_:_:_:_:_:_:_:)
        public init<InvalidationType1, InvalidationType2, InvalidationType3, InvalidationType4, InvalidationType5, InvalidationType6, InvalidationType7, InvalidationType8, InvalidationType9, InvalidationType10>(wrappedValue: Value, _ invalidation1: InvalidationType1, _ invalidation2: InvalidationType2, _ invalidation3: InvalidationType3, _ invalidation4: InvalidationType4, _ invalidation5: InvalidationType5, _ invalidation6: InvalidationType6, _ invalidation7: InvalidationType7, _ invalidation8: InvalidationType8, _ invalidation9: InvalidationType9, _ invalidation10: InvalidationType10) where InvalidationType == NSView.Invalidations.Tuple<NSView.Invalidations.Tuple<NSView.Invalidations.Tuple<NSView.Invalidations.Tuple<InvalidationType1, InvalidationType2>, NSView.Invalidations.Tuple<InvalidationType3, InvalidationType4>>, NSView.Invalidations.Tuple<NSView.Invalidations.Tuple<InvalidationType5, InvalidationType6>, NSView.Invalidations.Tuple<InvalidationType7, InvalidationType8>>>, NSView.Invalidations.Tuple<InvalidationType9, InvalidationType10>>, InvalidationType1 : NSViewInvalidating, InvalidationType2 : NSViewInvalidating, InvalidationType3 : NSViewInvalidating, InvalidationType4 : NSViewInvalidating, InvalidationType5 : NSViewInvalidating, InvalidationType6 : NSViewInvalidating, InvalidationType7 : NSViewInvalidating, InvalidationType8 : NSViewInvalidating, InvalidationType9 : NSViewInvalidating, InvalidationType10 : NSViewInvalidating { self.init(wrappedValue: wrappedValue, NSView.Invalidations.Tuple(NSView.Invalidations.Tuple(NSView.Invalidations.Tuple(NSView.Invalidations.Tuple(invalidation1, invalidation2), NSView.Invalidations.Tuple(invalidation3, invalidation4)), NSView.Invalidations.Tuple(NSView.Invalidations.Tuple(invalidation5, invalidation6), NSView.Invalidations.Tuple(invalidation7, invalidation8))), NSView.Invalidations.Tuple(invalidation9, invalidation10))) }
    }
}

// MARK: - Invalidations (macOS 12)

@available(macOS 12.0, *)
extension NSView {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidations
    @available(macOS 12.0, *)
    public enum Invalidations {
    }
}

/// Runs `body` on the main actor. NSViewInvalidating.invalidate(view:) is not main-actor
/// isolated in the SDK's Swift interface, but every caller (the property wrapper's
/// enclosing-instance subscript) runs on the main thread with the view.
@inline(__always)
private func _onMain(_ body: @MainActor () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(body)
    } else {
        DispatchQueue.main.sync { MainActor.assumeIsolated(body) }
    }
}

@available(macOS 12.0, *)
extension NSView.Invalidations {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidations/constraints
    @available(macOS 12.0, *)
    public struct Constraints: NSViewInvalidating {
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidations/constraints/init()
        public init() { }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidations/constraints/invalidate(view:)
        public func invalidate(view: NSView) { _onMain { view.needsUpdateConstraints = true } }
    }
}

@available(macOS 12.0, *)
extension NSView.Invalidations {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidations/display
    @available(macOS 12.0, *)
    public struct Display: NSViewInvalidating {
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidations/display/init()
        public init() { }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidations/display/invalidate(view:)
        public func invalidate(view: NSView) { _onMain { view.needsDisplay = true } }
    }
}

@available(macOS 12.0, *)
extension NSView.Invalidations {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidations/intrinsiccontentsize
    @available(macOS 12.0, *)
    public struct IntrinsicContentSize: NSViewInvalidating {
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidations/intrinsiccontentsize/init()
        public init() { }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidations/intrinsiccontentsize/invalidate(view:)
        public func invalidate(view: NSView) { _onMain { view.invalidateIntrinsicContentSize() } }
    }
}

@available(macOS 12.0, *)
extension NSView.Invalidations {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidations/layout
    @available(macOS 12.0, *)
    public struct Layout: NSViewInvalidating {
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidations/layout/init()
        public init() { }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidations/layout/invalidate(view:)
        public func invalidate(view: NSView) { _onMain { view.needsLayout = true } }
    }
}

@available(macOS 12.0, *)
extension NSView.Invalidations {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidations/restorablestate
    @available(macOS 12.0, *)
    public struct RestorableState: NSViewInvalidating {
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidations/restorablestate/init()
        public init() { }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidations/restorablestate/invalidate(view:)
        public func invalidate(view: NSView) { _onMain { view.invalidateRestorableState() } }
    }
}

@available(macOS 12.0, *)
extension NSView.Invalidations {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidations/tuple
    @available(macOS 12.0, *)
    public struct Tuple<Invalidation1, Invalidation2>: NSViewInvalidating where Invalidation1 : NSViewInvalidating, Invalidation2 : NSViewInvalidating {
        internal let invalidation1: Invalidation1
        internal let invalidation2: Invalidation2
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidations/tuple/init(_:_:)
        public init(_ invalidation1: Invalidation1, _ invalidation2: Invalidation2) {
            self.invalidation1 = invalidation1
            self.invalidation2 = invalidation2
        }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidations/tuple/invalidate(view:)
        public func invalidate(view: NSView) {
            invalidation1.invalidate(view: view)
            invalidation2.invalidate(view: view)
        }
    }
}
