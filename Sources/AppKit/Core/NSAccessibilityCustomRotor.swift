// NSAccessibilityCustomRotor (hand-written; ADR-0037).
//
// The rotor, its item results and its search parameters are plain data, as in AppKit: an
// element lists rotors in `accessibilityCustomRotors()` and assistive technology asks the
// rotor's `itemSearchDelegate` for the next or previous item. The port stores and returns
// them (NSView and NSAccessibilityElement keep the list); exposing rotors to UI Automation
// and AT-SPI so a screen reader can navigate them is a follow-up (ROADMAP, ADR-0013).

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor
@available(macOS 10.13, *)
open class NSAccessibilityCustomRotor: NSObject {
    private var _label: String
    private var _type: NSAccessibilityCustomRotor.RotorType
    private weak var _itemSearchDelegate: (any NSAccessibilityCustomRotorItemSearchDelegate)?
    private weak var _itemLoadingDelegate: (any NSAccessibilityElementLoading)?

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/init(label:itemsearchdelegate:)
    /// A custom rotor (`type` is `.custom`) with the given label.
    public init(label: String, itemSearchDelegate: any NSAccessibilityCustomRotorItemSearchDelegate) {
        _label = label
        _type = .custom
        _itemSearchDelegate = itemSearchDelegate
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/init(rotortype:itemsearchdelegate:)
    /// A rotor of a system type; assistive technology names it, so `label` starts empty.
    public init(rotorType: NSAccessibilityCustomRotor.RotorType, itemSearchDelegate: any NSAccessibilityCustomRotorItemSearchDelegate) {
        _label = ""
        _type = rotorType
        _itemSearchDelegate = itemSearchDelegate
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/itemloadingdelegate
    /// Weak, as in AppKit.
    open var itemLoadingDelegate: (any NSAccessibilityElementLoading)? {
        get { _itemLoadingDelegate }
        set { _itemLoadingDelegate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/itemsearchdelegate
    /// Weak, as in AppKit: the app keeps its delegate alive.
    open var itemSearchDelegate: (any NSAccessibilityCustomRotorItemSearchDelegate)? {
        get { _itemSearchDelegate }
        set { _itemSearchDelegate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/label
    open var label: String {
        get { _label }
        set { _label = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/type
    open var type: NSAccessibilityCustomRotor.RotorType {
        get { _type }
        set { _type = newValue }
    }
}

@available(macOS 10.13, *)
extension NSAccessibilityCustomRotor {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/itemresult
    @available(macOS 10.13, *)
    open class ItemResult: NSObject {
        private var _customLabel: String?
        private let _itemLoadingToken: NSAccessibilityLoadingToken?
        private let _targetElement: (any NSAccessibilityElementProtocol)?
        private var _targetRange = NSRange(location: 0, length: 0)

        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/itemresult/init(itemloadingtoken:customlabel:)
        /// A result for an element that is not loaded yet; the rotor's `itemLoadingDelegate`
        /// turns the token into the element.
        public init(itemLoadingToken: NSAccessibilityLoadingToken, customLabel: String) {
            _itemLoadingToken = itemLoadingToken
            _customLabel = customLabel
            _targetElement = nil
            super.init()
        }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/itemresult/init(targetelement:)
        public init(targetElement: any NSAccessibilityElementProtocol) {
            _targetElement = targetElement
            _itemLoadingToken = nil
            _customLabel = nil
            super.init()
        }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/itemresult/customlabel
        open var customLabel: String? {
            get { _customLabel }
            set { _customLabel = newValue }
        }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/itemresult/itemloadingtoken
        open var itemLoadingToken: NSAccessibilityLoadingToken? { _itemLoadingToken }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/itemresult/targetelement
        open var targetElement: (any NSAccessibilityElementProtocol)? { _targetElement }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/itemresult/targetrange
        /// A text range inside the target element ({0, 0}, as AppKit zero-fills it, until set).
        open var targetRange: NSRange {
            get { _targetRange }
            set { _targetRange = newValue }
        }
    }
}

@available(macOS 10.13, *)
extension NSAccessibilityCustomRotor {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/rotortype
    @available(macOS 10.13, *)
    public enum RotorType: Int, Sendable, Equatable, Hashable {
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/rotortype/annotation
        case annotation = 2
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/rotortype/any
        case any = 1
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/rotortype/audiograph
        case audiograph = 21
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/rotortype/boldtext
        case boldText = 3
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/rotortype/custom
        case custom = 0
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/rotortype/heading
        case heading = 4
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/rotortype/headinglevel1
        case headingLevel1 = 5
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/rotortype/headinglevel2
        case headingLevel2 = 6
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/rotortype/headinglevel3
        case headingLevel3 = 7
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/rotortype/headinglevel4
        case headingLevel4 = 8
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/rotortype/headinglevel5
        case headingLevel5 = 9
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/rotortype/headinglevel6
        case headingLevel6 = 10
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/rotortype/image
        case image = 11
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/rotortype/italictext
        case italicText = 12
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/rotortype/landmark
        case landmark = 13
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/rotortype/link
        case link = 14
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/rotortype/list
        case list = 15
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/rotortype/misspelledword
        case misspelledWord = 16
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/rotortype/table
        case table = 17
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/rotortype/textfield
        case textField = 18
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/rotortype/underlinedtext
        case underlinedText = 19
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/rotortype/visitedlink
        case visitedLink = 20
    }
}

@available(macOS 10.13, *)
extension NSAccessibilityCustomRotor {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/searchdirection
    @available(macOS 10.13, *)
    public enum SearchDirection: Int, Sendable, Equatable, Hashable {
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/searchdirection/next
        case next = 1
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/searchdirection/previous
        case previous = 0
    }
}

@available(macOS 10.13, *)
extension NSAccessibilityCustomRotor {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/searchparameters
    /// What assistive technology asks a rotor's search delegate: the item to start from (nil
    /// for the first search), the direction and a filter typed by the user. Fields start
    /// zero-filled as in AppKit (no item, `.previous`, empty filter).
    @available(macOS 10.13, *)
    open class SearchParameters: NSObject {
        private var _currentItem: NSAccessibilityCustomRotor.ItemResult?
        private var _filterString = ""
        private var _searchDirection: NSAccessibilityCustomRotor.SearchDirection = .previous

        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/searchparameters/currentitem
        open var currentItem: NSAccessibilityCustomRotor.ItemResult? {
            get { _currentItem }
            set { _currentItem = newValue }
        }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/searchparameters/filterstring
        open var filterString: String {
            get { _filterString }
            set { _filterString = newValue }
        }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomrotor/searchparameters/searchdirection
        open var searchDirection: NSAccessibilityCustomRotor.SearchDirection {
            get { _searchDirection }
            set { _searchDirection = newValue }
        }
    }
}
