import SwiftUI

struct CompactResultNotice: View {
    let message: String
    let tone: NoticeTone

    var body: some View {
        Label {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(message)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
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
