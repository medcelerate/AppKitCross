import AppKit
import SwiftUI

/// Raw markdown editor: an NSTextView so we get real text editing (undo, find bar,
/// multi-cursor-free but native behaviour) plus programmatic syntax highlighting,
/// which SwiftUI's TextEditor can't do.
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 16, height: 18)
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .controlAccentColor
        textView.font = MDFont.make(size: fontSize, mono: true)
        textView.string = text

        context.coordinator.textView = textView
        context.coordinator.lastText = text
        context.coordinator.lastFontSize = fontSize
        context.coordinator.highlight()

        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        var needsHighlight = false

        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            needsHighlight = true
        }

        if context.coordinator.lastFontSize != fontSize {
            context.coordinator.lastFontSize = fontSize
            textView.font = MDFont.make(size: fontSize, mono: true)
            needsHighlight = true
        }

        if needsHighlight {
            context.coordinator.lastText = text
            context.coordinator.highlight()
        }
    }

    // AppKitCross: `@MainActor` added. Apple's AppKit is imported from Objective-C, so a
    // main-actor property read from this nonisolated class (`textView?.textStorage`) is
    // only a warning there; the port's Swift AppKit makes it an error (see README).
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextEditor
        weak var textView: NSTextView?
        var lastText: String = ""
        var lastFontSize: CGFloat = 0

        init(_ parent: MarkdownTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            lastText = textView.string
            parent.text = textView.string
            highlight()
        }

        func highlight() {
            guard let storage = textView?.textStorage else { return }
            MarkdownHighlighter.apply(to: storage, fontSize: lastFontSize)
        }
    }
}
