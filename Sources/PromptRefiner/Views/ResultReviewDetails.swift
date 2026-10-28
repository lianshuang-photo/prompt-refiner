import SwiftUI

struct ResultReviewDetails: View {
    let suggestions: [String]
    let assumptions: [String]
    let requiresReview: Bool
    @State private var suggestionsExpanded = false
    @State private var assumptionsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: RefinerDesign.rowSpacing) {
            if !assumptions.isEmpty {
                DisclosureGroup(isExpanded: $assumptionsExpanded) {
                    Text(assumptions.map { "• \($0)" }.joined(separator: "\n\n"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineSpacing(4)
                        .padding(.top, RefinerDesign.compactSpacing)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label {
                        Text("\(requiresReview ? "需要确认的理解" : "上下文理解") · \(assumptions.count)")
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: requiresReview ? "exclamationmark.triangle" : "info.circle")
                            .foregroundStyle(requiresReview ? Color.orange : Color.secondary)
                            .accessibilityHidden(true)
                    }
                    .font(.callout)
                }
            }
            if !suggestions.isEmpty {
                DisclosureGroup(isExpanded: $suggestionsExpanded) {
                    Text(suggestions.map { "• \($0)" }.joined(separator: "\n\n"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineSpacing(4)
                        .padding(.top, RefinerDesign.compactSpacing)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("补充建议 · \(suggestions.count)", systemImage: "lightbulb")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: assumptions) { _, _ in assumptionsExpanded = false }
        .onChange(of: suggestions) { _, _ in suggestionsExpanded = false }
    }
}
