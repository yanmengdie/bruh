import SwiftUI

struct SettingsScreen: View {
    @AppStorage("useHomeScreenMode") private var useHomeScreenMode = true

    var body: some View {
        List {
            Section("Display Mode") {
                Toggle("Use HomeScreen Mode", isOn: $useHomeScreenMode)
            }

            Label("通知设置", systemImage: "bell.badge")
            Label("内容偏好", systemImage: "slider.horizontal.3")
            Label("关于 Bruh", systemImage: "info.circle")
        }
        .navigationTitle("设置")
    }
}
