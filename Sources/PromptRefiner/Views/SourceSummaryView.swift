import SwiftUI

struct SourceSummaryView: View {
    let description: String
    let details: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: RefinerDesign.compactSpacing) {
            Label(description.isEmpty ? "本次输入" : description, systemImage: "rectangle.and.text.magnifyingglass")
                .font(.callout)
                .bold()
                .fixedSize(horizontal: false, vertical: true)
            if !details.isEmpty {
                Text(details.joined(separator: "\n"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
