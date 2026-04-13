import SwiftUI

struct SettingsScreen: View {
    @AppStorage private var useHomeScreenMode: Bool

    init(
        userDefaults: UserDefaults = .standard,
        appEnvironment: AppEnvironment = .current
    ) {
        let scopedDefaults = ScopedUserDefaultsStore(
            userDefaults: userDefaults,
            appEnvironment: appEnvironment
        )
        _useHomeScreenMode = AppStorage(
            wrappedValue: true,
            scopedDefaults.key("useHomeScreenMode"),
            store: userDefaults
        )
    }

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
