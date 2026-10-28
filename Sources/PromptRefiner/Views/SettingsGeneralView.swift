import SwiftUI

struct SettingsGeneralView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var coordinator: Coordinator

    var body: some View {
        VStack(alignment: .leading, spacing: RefinerDesign.sectionSpacing) {
            SettingsPermissionsView()

            SettingsSection(title: "使用方式") {
                HStack(alignment: .center, spacing: RefinerDesign.rowSpacing) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("全局快捷键").font(.body)
                        Text("有选区时只细化选中文字。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: RefinerDesign.compactSpacing)
                    ShortcutRecorder(label: settings.shortcutLabel, recorded: recordShortcut)
                        .frame(width: 190, height: 28)
                        .accessibilityLabel("设置全局快捷键")
                        .help("点击后按下新的组合键，按 Esc 取消。")
                }
                Divider()
                SettingToggleRow(title: "直接回填", explanation: "原稿未变化且无需确认时回填；其他情况保留结果卡片。", isOn: $settings.autoApply)
                Divider()
                LoginItemRow()
            }

            SettingsSection(title: "上下文与细化") {
                SettingToggleRow(title: "使用当前窗口截图", explanation: "仅触发时截图，随本次请求交给模型。", isOn: $settings.captureWindow)
                Divider()
                SettingToggleRow(title: "结合原会话与工程", explanation: "匹配当前会话后读取相关内容，并允许 Codex 在对应工程内只读查找。", isOn: $settings.useConversation)
                Divider()
                LabeledContent("细化速度") {
                    Picker("细化速度", selection: $settings.effort) {
                        Text("快速").tag("low")
                        Text("更细致").tag("medium")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 190)
                }
            }
        }
    }

    private func recordShortcut(keyCode: UInt32, modifiers: UInt32, label: String) {
        settings.keyCode = keyCode
        settings.modifiers = modifiers
        settings.shortcutLabel = label
        coordinator.updateHotkey()
    }
}
