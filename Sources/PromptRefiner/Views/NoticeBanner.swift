import SwiftUI

struct NoticeBanner: View {
    let message: String
    let tone: NoticeTone

    var body: some View {
        Label {
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.primary)
        .padding(RefinerDesign.rowSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: .rect(cornerRadius: RefinerDesign.editorRadius))
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch tone {
        case .neutral: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "exclamationmark.circle"
        }
    }

    private var color: Color {
        switch tone {
        case .neutral: RefinerDesign.accent
        case .warning: .orange
        case .error: .red
        }
    }
}
