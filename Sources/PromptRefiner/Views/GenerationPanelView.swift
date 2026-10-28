import SwiftUI

struct GenerationPanelView: View {
    @ObservedObject var coordinator: Coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: RefinerDesign.rowSpacing) {
            HStack(spacing: RefinerDesign.rowSpacing) {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("细化进行中")
                Text(coordinator.progressStage.isEmpty ? "正在细化提示词" : coordinator.progressStage)
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(elapsedLabel)
                    .font(.callout).foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityLabel("已用时 \(coordinator.elapsedSeconds) 秒")
                Button("取消", action: coordinator.cancel)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("取消本次改写，保留原稿。")
            }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(progressText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(height: 1).id("progress-tail")
                    }
                }
                .scrollIndicators(.hidden)
                .frame(height: 104)
                .onChange(of: coordinator.progressLines) { _, _ in
                    scrollToLatest(using: proxy)
                }
                .onAppear { scrollToLatest(using: proxy) }
            }
            HStack(spacing: RefinerDesign.compactSpacing) {
                Label("原稿保留中", systemImage: "text.alignleft")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(coordinator.sourceDescription)
                    .font(.callout).foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(RefinerDesign.rowSpacing + 4)
        .background(.regularMaterial, in: .rect(cornerRadius: RefinerDesign.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: RefinerDesign.cardRadius)
                .stroke(RefinerDesign.separator.opacity(0.5), lineWidth: 1)
        }
        .tint(RefinerDesign.accent)
    }

    private var elapsedLabel: String {
        let seconds = max(0, coordinator.elapsedSeconds)
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private var progressText: String {
        if coordinator.progressLines.isEmpty { return coordinator.progressStage }
        return coordinator.progressLines.suffix(5).joined(separator: "\n")
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        if reduceMotion { proxy.scrollTo("progress-tail", anchor: .bottom) }
        else {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo("progress-tail", anchor: .bottom)
            }
        }
    }
}
