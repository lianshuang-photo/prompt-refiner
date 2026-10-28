import RefinerCore
import SwiftUI

struct SettingsAdvancedView: View {
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: RefinerDesign.sectionSpacing) {
            SettingsSection(title: "模型连接") {
                VStack(alignment: .leading, spacing: RefinerDesign.compactSpacing) {
                    Text("模型").font(.body)
                    TextField("留空使用 Codex 默认模型", text: $settings.model)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("改写模型，留空使用 Codex 默认模型")
                    Text("沿用本机 Codex 登录，改写请求独立于原工程会话。")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                VStack(alignment: .leading, spacing: RefinerDesign.compactSpacing) {
                    Text("Codex 可执行文件").font(.body)
                    TextField("Codex 路径", text: $settings.codexPath)
                        .font(.system(.callout, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Codex 可执行文件路径")
                }
            }

            SettingsSection(title: "增强方式") {
                Picker("增强方式", selection: $settings.rewriteStyle) {
                    ForEach(RewriteStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("增强方式")
                Text(settings.rewriteStyle.summary)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("参考公开方法整理，均由当前 Codex 模型执行。")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Link("公开参考", destination: settings.rewriteStyle.sourceURL)
                        .font(.caption)
                }
            }
        }
    }
}
