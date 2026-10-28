import AppKit
import SwiftUI

struct NativePromptEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let accessibilityLabel: String
    let minimumHeight: CGFloat
    let maximumHeight: CGFloat

    func makeCoordinator() -> PromptEditorDelegate {
        PromptEditorDelegate(text: $text, focused: $focused)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PromptTextView(frame: .zero)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.drawsBackground = false
        textView.font = Self.editorFont
        textView.textColor = .labelColor
        textView.defaultParagraphStyle = Self.paragraphStyle
        textView.typingAttributes = Self.typingAttributes
        textView.textContainerInset = NSSize(width: RefinerDesign.editorInset, height: RefinerDesign.editorInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text
        textView.delegate = context.coordinator
        let delegate = context.coordinator
        textView.onFocusChange = { [weak delegate] in delegate?.focusChanged($0) }
        textView.setAccessibilityLabel(accessibilityLabel)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.focused = $focused
        guard let textView = scrollView.documentView as? PromptTextView else { return }
        textView.setAccessibilityLabel(accessibilityLabel)
        if textView.string != text {
            textView.string = text
            textView.undoManager?.removeAllActions()
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.scrollToBeginningOfDocument(nil)
        }
        textView.typingAttributes = Self.typingAttributes
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        let width = max(proposal.width ?? 520, 160)
        // Reserve room for the system scrollbar as well as the editor's insets.
        let textWidth = max(100, width - RefinerDesign.editorInset * 2 - 16)
        let measuredText = (text.isEmpty ? " " : text) + "\u{200B}"
        let bounds = NSAttributedString(string: measuredText, attributes: Self.typingAttributes)
            .boundingRect(with: NSSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude),
                          options: [.usesLineFragmentOrigin, .usesFontLeading])
        let height = min(maximumHeight, max(minimumHeight, ceil(bounds.height) + RefinerDesign.editorInset * 2 + 2))
        return CGSize(width: width, height: height)
    }

    private static var editorFont: NSFont { .preferredFont(forTextStyle: .body) }

    private static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        return style
    }

    private static var typingAttributes: [NSAttributedString.Key: Any] {
        [.font: editorFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraphStyle]
    }
}
