import SwiftUI

struct SettingsScreen: View {
    var body: some View {
        List {
            Section("即将开放") {
                placeholderRow(
                    title: "通知",
                    subtitle: "消息提醒、免打扰和通知偏好会统一放在这里。",
                    systemImage: "bell.badge"
                )

                placeholderRow(
                    title: "内容偏好",
                    subtitle: "后续会支持调节人物、消息和朋友圈的内容推荐方向。",
                    systemImage: "slider.horizontal.3"
                )
            }

            Section("关于 Bruh") {
                LabeledContent("版本", value: appVersion)
                if let buildNumber {
                    LabeledContent("构建", value: buildNumber)
                }

                Text("Bruh 把联系人、消息、朋友圈和相册放在同一个关系语境里，当前版本优先保证主链路可用。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    private func placeholderRow(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Text("待开放")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.45))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.06), in: Capsule())
        }
        .padding(.vertical, 2)
    }
}
