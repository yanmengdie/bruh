import SwiftUI

struct SettingsScreen: View {
    @AppStorage("useHomeScreenMode") private var useHomeScreenMode = true

    var body: some View {
        List {
            Section("界面模式") {
                Toggle("使用桌面首页模式", isOn: $useHomeScreenMode)
            }

            Label("通知", systemImage: "bell.badge")
            Label("内容偏好", systemImage: "slider.horizontal.3")
            Label("关于 Bruh", systemImage: "info.circle")
        }
        .navigationTitle("设置")
    }
}
