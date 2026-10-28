import SwiftUI

struct CompactSourceSummary: View {
    let description: String
    let details: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(description.isEmpty ? "本次输入" : description, systemImage: "rectangle.and.text.magnifyingglass")
                .font(.callout)
                .lineLimit(1)
                .help(description)
            Label(conversationStatus, systemImage: "text.bubble")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(conversationStatus)
            if let projectStatus = details.first(where: { $0.hasPrefix("工程：") }) {
                Label(projectStatus, systemImage: "folder")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(projectStatus)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var conversationStatus: String {
        details.first(where: { $0.hasPrefix("会话：") }) ?? "会话：未读取原会话"
    }
}
