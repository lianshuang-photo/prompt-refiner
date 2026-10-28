import RefinerCore
import SwiftUI

struct ResultView: View {
    @ObservedObject var coordinator: Coordinator

    var body: some View {
        VStack(spacing: 0) {
            AppHeader(title: coordinator.busy ? "正在细化提示词" : "改写结果",
                      subtitle: "可以继续编辑，再回填到原输入框或复制。")
                .padding(RefinerDesign.pageInset)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: RefinerDesign.sectionSpacing) {
                    if coordinator.busy {
                        GenerationPanelView(coordinator: coordinator)
                    } else if let result = coordinator.result {
                        SourceSummaryView(description: coordinator.sourceDescription, details: coordinator.sourceDetails)
                        if !coordinator.resultNote.isEmpty {
                            NoticeBanner(message: coordinator.resultNote, tone: coordinator.noticeTone)
                        }
                        VStack(alignment: .leading, spacing: RefinerDesign.compactSpacing) {
                            HStack {
                                Text("细化后的提示词").font(.headline)
                                Spacer(minLength: 0)
                                Text("可编辑").font(.callout).foregroundStyle(.secondary)
                            }
                            MultilineEditor(text: $coordinator.editedPrompt, placeholder: "改写结果…",
                                            accessibilityLabel: "细化后的提示词，可编辑")
                            if coordinator.editedPrompt.utf16.count > 40_000 {
                                Label("内容超过长度限制，请删减后再应用。", systemImage: "exclamationmark.circle")
                                    .font(.callout).foregroundStyle(.red)
                            }
                        }
                        ResultReviewDetails(suggestions: result.suggestions, assumptions: result.assumptions,
                                            requiresReview: needsReview)
                        OriginalDraftDisclosure(draft: coordinator.originalDraft, copyOriginal: coordinator.copyOriginal)
                    } else {
                        ContentUnavailableView("还没有改写结果", systemImage: "text.badge.star",
                                               description: Text("在原输入框中触发快捷键，或先试写一段文字。"))
                        Button("试写一段…", action: coordinator.showManual)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(RefinerDesign.pageInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            ResultActionBar(coordinator: coordinator, validResult: validResult)
        }
        .background(RefinerDesign.windowBackground)
        .tint(RefinerDesign.accent)
    }

    private var validResult: Bool {
        coordinator.result != nil && !coordinator.busy
            && !coordinator.editedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && coordinator.editedPrompt.utf16.count <= 40_000
    }

    private var needsReview: Bool {
        if coordinator.result?.clarificationNeeded == true { return true }
        switch coordinator.noticeTone {
        case .warning, .error: return true
        case .neutral: return false
        }
    }
}
