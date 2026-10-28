import SwiftUI

struct ToastView: View {
    let message: String
    let actions: Bool
    let allowUndo: Bool
    let view: () -> Void
    let undo: () -> Void

    var body: some View {
        HStack(spacing: RefinerDesign.rowSpacing) {
            Image(systemName: actions ? "checkmark.circle.fill" : "info.circle")
                .font(.title3)
                .foregroundStyle(RefinerDesign.accent)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if actions {
                Button("查看", action: view).buttonStyle(.borderless)
                if allowUndo { Button("撤销", action: undo).buttonStyle(.borderless) }
            }
        }
        .controlSize(.small)
        .padding(RefinerDesign.rowSpacing)
        .frame(maxWidth: .infinity, minHeight: 66)
        .background(.regularMaterial, in: .rect(cornerRadius: RefinerDesign.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: RefinerDesign.cardRadius)
                .stroke(RefinerDesign.separator.opacity(0.5), lineWidth: 1)
        }
        .tint(RefinerDesign.accent)
    }
}
