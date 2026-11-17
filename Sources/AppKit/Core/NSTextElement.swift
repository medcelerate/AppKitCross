// NSTextElement (hand-written; seeded from the generated stub, see tools/apigen)
// One element of a TextKit 2 document (ADR-0040); NSTextContentStorage vends paragraphs.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextelement
@available(macOS 12.0, *)
open class NSTextElement: NSObject {
    private var _elementRange: NSTextRange?
    private weak var _textContentManager: NSTextContentManager?
    internal var _children: [NSTextElement] = []
    internal weak var _parent: NSTextElement?

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextelement/init(textcontentmanager:)
    public init(textContentManager: NSTextContentManager?) {
        _textContentManager = textContentManager
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextelement/elementrange
    open var elementRange: NSTextRange? {
        get { _elementRange }
        set { _elementRange = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextelement/textcontentmanager
    open var textContentManager: NSTextContentManager? {
        get { _textContentManager }
        set { _textContentManager = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextelement/childelements
    @available(macOS 13.0, *)
    open var childElements: [NSTextElement] { _children }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextelement/parent
    @available(macOS 13.0, *)
    open var parent: NSTextElement? { _parent }
    /// Whether the element stands for content of the backing store (every element the
    /// port's content storage vends does).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextelement/isrepresentedelement
    @available(macOS 13.0, *)
    open var isRepresentedElement: Bool { _textContentManager != nil && _elementRange != nil }
}
