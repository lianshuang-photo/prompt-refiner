import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var coordinator: Coordinator
    @State private var selectedTab: SettingsTab

    init(settings: Settings, coordinator: Coordinator, initialTab: SettingsTab = .general) {
        self.settings = settings
        self.coordinator = coordinator
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: RefinerDesign.sectionSpacing) {
                AppHeader(title: "提示词细化", subtitle: "把想法写清楚，留在原来的输入框。")
                Picker("设置分类", selection: $selectedTab) {
                    Text("常规").tag(SettingsTab.general)
                    Text("高级").tag(SettingsTab.advanced)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(RefinerDesign.pageInset)

            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: RefinerDesign.sectionSpacing) {
                    if selectedTab == .general {
                        SettingsGeneralView(settings: settings, coordinator: coordinator)
                    } else {
                        SettingsAdvancedView(settings: settings)
                    }
                }
                .padding(RefinerDesign.pageInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            HStack(spacing: RefinerDesign.rowSpacing) {
                Text(coordinator.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("试写一段…", action: coordinator.showManual)
                    .disabled(coordinator.busy)
            }
            .padding(.horizontal, RefinerDesign.pageInset)
            .padding(.vertical, RefinerDesign.rowSpacing)
        }
        .background(RefinerDesign.windowBackground)
        .tint(RefinerDesign.accent)
    }
}
