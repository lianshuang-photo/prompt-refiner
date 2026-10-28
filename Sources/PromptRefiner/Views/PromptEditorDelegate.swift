import AppKit
import SwiftUI

@MainActor final class PromptEditorDelegate: NSObject, NSTextViewDelegate {
    var text: Binding<String>
    var focused: Binding<Bool>

    init(text: Binding<String>, focused: Binding<Bool>) {
        self.text = text
        self.focused = focused
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        text.wrappedValue = textView.string
    }

    func focusChanged(_ isFocused: Bool) {
        focused.wrappedValue = isFocused
    }
}
