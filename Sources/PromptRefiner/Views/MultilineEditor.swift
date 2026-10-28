import SwiftUI

struct MultilineEditor: View {
    @Binding var text: String
    let placeholder: String
    let accessibilityLabel: String
    var minimumHeight: CGFloat = 110
    var maximumHeight: CGFloat = 320
    @State private var focused = false

    var body: some View {
        NativePromptEditor(text: $text, focused: $focused, accessibilityLabel: accessibilityLabel,
                           minimumHeight: minimumHeight, maximumHeight: maximumHeight)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(RefinerDesign.editorInset)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .background(RefinerDesign.editorBackground, in: .rect(cornerRadius: RefinerDesign.editorRadius))
            .clipShape(.rect(cornerRadius: RefinerDesign.editorRadius))
            .overlay {
                RoundedRectangle(cornerRadius: RefinerDesign.editorRadius)
                    .stroke(focused ? RefinerDesign.accent : RefinerDesign.separator,
                            lineWidth: focused ? 2 : 1)
                    .allowsHitTesting(false)
            }
    }
}
