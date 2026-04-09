import SwiftUI
import UIKit

struct AddBruhView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var pendingNames: Set<String> = []

    @State private var selectedTag = "全部"

    private let candidates: [AddBruhCandidate] = [
        // US (10)
        .init(name: "Taylor Swift", subtitle: "创作歌手", color: Color(red: 0.98, green: 0.80, blue: 0.43), emoji: "🎤", tags: ["美国", "娱乐"], avatarAssetName: "Avatar_Taylor"),
        .init(name: "LeBron James", subtitle: "NBA 球星", color: Color(red: 0.13, green: 0.50, blue: 0.92), emoji: "🏀", tags: ["美国", "体育"]),
        .init(name: "MrBeast", subtitle: "YouTube 创作者", color: Color(red: 0.10, green: 0.73, blue: 0.75), emoji: "🎥", tags: ["美国", "娱乐"]),
        .init(name: "Tim Cook", subtitle: "Apple CEO", color: Color(red: 0.57, green: 0.56, blue: 0.97), emoji: "🍎", tags: ["美国", "科技", "财经"], avatarAssetName: "Avatar_Tim Cook"),
        .init(name: "Jensen Huang", subtitle: "NVIDIA CEO", color: Color(red: 0.20, green: 0.72, blue: 0.35), emoji: "🖥️", tags: ["美国", "科技", "财经"]),
        .init(name: "Barack Obama", subtitle: "前美国总统", color: Color(red: 0.03, green: 0.71, blue: 0.60), emoji: "🇺🇸", tags: ["美国", "政治"], avatarAssetName: "Avatar_Obama"),
        .init(name: "Dwayne Johnson", subtitle: "演员", color: Color(red: 0.84, green: 0.49, blue: 0.31), emoji: "💪", tags: ["美国", "娱乐"]),
        .init(name: "Emma Chamberlain", subtitle: "内容创作者", color: Color(red: 0.88, green: 0.39, blue: 0.53), emoji: "📱", tags: ["美国", "娱乐"]),
        .init(name: "Lex Fridman", subtitle: "播客主持人", color: Color(red: 0.36, green: 0.40, blue: 0.45), emoji: "🎙️", tags: ["美国", "科技"]),
        .init(name: "Joe Rogan", subtitle: "播客主持人", color: Color(red: 0.56, green: 0.35, blue: 0.22), emoji: "🗣️", tags: ["美国", "娱乐"]),

        // China (20)
        .init(name: "马化腾", subtitle: "腾讯 CEO", color: Color(red: 0.09, green: 0.53, blue: 0.93), emoji: "🐧", tags: ["中国", "科技", "财经"], avatarAssetName: "Avatar_MaHuateng"),
        .init(name: "马云", subtitle: "企业家", color: Color(red: 0.97, green: 0.47, blue: 0.10), emoji: "🧭", tags: ["中国", "财经"], avatarAssetName: "Avatar_JackMa"),
        .init(name: "梁文锋", subtitle: "AI 创业者", color: Color(red: 0.14, green: 0.26, blue: 0.82), emoji: "🧠", tags: ["中国", "科技"]),
        .init(name: "王小川", subtitle: "AI 创业者", color: Color(red: 0.38, green: 0.34, blue: 0.84), emoji: "🤖", tags: ["中国", "科技"]),
        .init(name: "何同学", subtitle: "科技创作者", color: Color(red: 0.11, green: 0.70, blue: 0.69), emoji: "📷", tags: ["中国", "科技", "娱乐"]),
        .init(name: "影视飓风 Tim", subtitle: "视频创作者", color: Color(red: 0.16, green: 0.58, blue: 0.86), emoji: "🎞️", tags: ["中国", "娱乐", "科技"]),
        .init(name: "小杨哥", subtitle: "短视频创作者", color: Color(red: 0.92, green: 0.37, blue: 0.31), emoji: "📣", tags: ["中国", "娱乐"]),
        .init(name: "敬汉卿", subtitle: "视频博主", color: Color(red: 0.74, green: 0.36, blue: 0.64), emoji: "🎬", tags: ["中国", "娱乐"]),
        .init(name: "李子柒", subtitle: "内容创作者", color: Color(red: 0.47, green: 0.66, blue: 0.34), emoji: "🌾", tags: ["中国", "娱乐"]),
        .init(name: "李佳琦", subtitle: "直播主播", color: Color(red: 0.91, green: 0.28, blue: 0.45), emoji: "💄", tags: ["中国", "财经", "娱乐"]),
        .init(name: "薇娅", subtitle: "直播主播", color: Color(red: 0.86, green: 0.26, blue: 0.37), emoji: "🛍️", tags: ["中国", "财经"]),
        .init(name: "董宇辉", subtitle: "主播", color: Color(red: 0.35, green: 0.46, blue: 0.75), emoji: "📚", tags: ["中国", "娱乐"]),
        .init(name: "罗翔", subtitle: "法学教师", color: Color(red: 0.24, green: 0.27, blue: 0.39), emoji: "⚖️", tags: ["中国", "政治"]),
        .init(name: "周鸿祎", subtitle: "360 创始人", color: Color(red: 0.86, green: 0.18, blue: 0.20), emoji: "🛡️", tags: ["中国", "科技"]),
        .init(name: "周杰伦", subtitle: "歌手", color: Color(red: 0.57, green: 0.41, blue: 0.78), emoji: "🎹", tags: ["中国", "娱乐"], avatarAssetName: "Avatar_ZhouJielun"),
        .init(name: "易烊千玺", subtitle: "演员 / 歌手", color: Color(red: 0.52, green: 0.60, blue: 0.66), emoji: "⭐️", tags: ["中国", "娱乐"]),
        .init(name: "贾玲", subtitle: "导演 / 演员", color: Color(red: 0.95, green: 0.41, blue: 0.42), emoji: "🎬", tags: ["中国", "娱乐"]),
        .init(name: "何炅", subtitle: "主持人", color: Color(red: 0.91, green: 0.56, blue: 0.23), emoji: "🎤", tags: ["中国", "娱乐"]),
        .init(name: "撒贝宁", subtitle: "主持人", color: Color(red: 0.89, green: 0.70, blue: 0.22), emoji: "🧩", tags: ["中国", "娱乐"]),
        .init(name: "王冰冰", subtitle: "主持人", color: Color(red: 0.99, green: 0.55, blue: 0.63), emoji: "🎙️", tags: ["中国", "娱乐"]),
    ]

    private var allTags: [String] {
        let tags = Set(candidates.flatMap(\.tags))
        let preferredOrder = ["中国", "美国", "政治", "娱乐", "体育", "财经", "科技"]
        let ordered = preferredOrder.filter(tags.contains)
        let extras = tags.subtracting(preferredOrder).sorted()
        return ["全部"] + ordered + extras
    }

    private var filteredCandidates: [AddBruhCandidate] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return candidates.filter { candidate in
            let matchTag = selectedTag == "全部" || candidate.tags.contains(selectedTag)
            let matchSearch: Bool
            if keyword.isEmpty {
                matchSearch = true
            } else {
                matchSearch = candidate.name.lowercased().contains(keyword)
                    || candidate.subtitle.lowercased().contains(keyword)
                    || candidate.tags.joined(separator: " ").lowercased().contains(keyword)
            }
            return matchTag && matchSearch
        }
    }

    private var featuredCandidates: [AddBruhCandidate] {
        sectionedCandidates.featured
    }

    private var moreCandidates: [AddBruhCandidate] {
        sectionedCandidates.popular
    }

    private var sectionedCandidates: (featured: [AddBruhCandidate], popular: [AddBruhCandidate]) {
        let china = filteredCandidates.filter { $0.tags.contains("中国") }
        let us = filteredCandidates.filter { $0.tags.contains("美国") }

        var chinaIndex = 0
        var usIndex = 0

        let featuredCount = min(5, china.count + us.count)
        let featured = buildBalancedSection(
            totalCount: featuredCount,
            china: china,
            us: us,
            chinaIndex: &chinaIndex,
            usIndex: &usIndex
        )

        let remainingCount = min(25, (china.count - chinaIndex) + (us.count - usIndex))
        let popular = buildBalancedSection(
            totalCount: remainingCount,
            china: china,
            us: us,
            chinaIndex: &chinaIndex,
            usIndex: &usIndex
        )

        return (featured, popular)
    }

    private func buildBalancedSection(
        totalCount: Int,
        china: [AddBruhCandidate],
        us: [AddBruhCandidate],
        chinaIndex: inout Int,
        usIndex: inout Int
    ) -> [AddBruhCandidate] {
        guard totalCount > 0 else { return [] }

        let chinaRemaining = china.count - chinaIndex
        let usRemaining = us.count - usIndex

        var targetChina = min(Int(round(Double(totalCount) * (2.0 / 3.0))), chinaRemaining)
        var targetUS = min(totalCount - targetChina, usRemaining)

        if targetChina + targetUS < totalCount {
            let shortfall = totalCount - targetChina - targetUS
            let extraChina = min(shortfall, chinaRemaining - targetChina)
            targetChina += extraChina
            targetUS += shortfall - extraChina
        }

        var pickedChina = 0
        var pickedUS = 0
        var result: [AddBruhCandidate] = []
        result.reserveCapacity(totalCount)

        while result.count < totalCount && (pickedChina < targetChina || pickedUS < targetUS) {
            if pickedChina < targetChina {
                result.append(china[chinaIndex + pickedChina])
                pickedChina += 1
            }
            if pickedChina < targetChina {
                result.append(china[chinaIndex + pickedChina])
                pickedChina += 1
            }
            if pickedUS < targetUS {
                result.append(us[usIndex + pickedUS])
                pickedUS += 1
            }
        }

        chinaIndex += pickedChina
        usIndex += pickedUS

        return Array(result.prefix(totalCount))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                searchField
                    .padding(.top, 8)

                categoryChips

                sectionTitle("热门推荐")
                    .padding(.top, 4)
                cards(for: featuredCandidates)

                sectionTitle("人气榜")
                    .padding(.top, 4)
                cards(for: moreCandidates)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.messagesBackground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    AppBackIcon()
                }
                .buttonStyle(.plain)
            }
        }
        .enableUnifiedSwipeBack()
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.30))

            TextField("按姓名搜索...", text: $searchText)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.68))
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(allTags, id: \.self) { tag in
                    Button {
                        selectedTag = tag
                    } label: {
                        Text(tag)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(selectedTag == tag ? .white : Color.black.opacity(0.46))
                            .padding(.horizontal, 26)
                            .frame(height: 44)
                            .background(selectedTag == tag ? Color(red: 0.84, green: 0.15, blue: 0.24) : Color.white.opacity(0.52))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.34))
            .tracking(1.5)
    }

    private func cards(for candidates: [AddBruhCandidate]) -> some View {
        Group {
            if candidates.isEmpty {
                Text("没有匹配的鸽们，换个 tag 或关键词试试")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 10) {
                    ForEach(candidates) { candidate in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(candidate.color)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    if let avatarAssetName = candidate.avatarAssetName,
                                       UIImage(named: avatarAssetName) != nil {
                                        Image(avatarAssetName)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 44, height: 44)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    } else {
                                        Text(candidate.emoji)
                                            .font(.system(size: 24))
                                    }
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.name)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Color.black.opacity(0.88))
                                Text(candidate.subtitle)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(Color.black.opacity(0.36))
                                    .lineLimit(2)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(candidate.tags, id: \.self) { tag in
                                            Button {
                                                selectedTag = tag
                                            } label: {
                                                Text(tag)
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundStyle(selectedTag == tag ? .white : Color.black.opacity(0.48))
                                                    .padding(.horizontal, 8)
                                                    .frame(height: 20)
                                                    .background(selectedTag == tag ? Color(red: 0.84, green: 0.15, blue: 0.24) : Color.black.opacity(0.06))
                                                    .clipShape(Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }

                            Spacer(minLength: 0)

                            let isPending = pendingNames.contains(candidate.name)
                            Button {
                                pendingNames.insert(candidate.name)
                            } label: {
                                Text(isPending ? "等待中" : "+ 添加")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(isPending ? Color(red: 0.47, green: 0.48, blue: 0.52) : Color(red: 0.83, green: 0.16, blue: 0.26))
                                    .padding(.horizontal, 18)
                                    .frame(height: 38)
                                    .background(isPending ? Color(red: 0.88, green: 0.88, blue: 0.90) : Color(red: 0.94, green: 0.86, blue: 0.84))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .disabled(isPending)
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                }
            }
        }
    }
}

private struct AddBruhCandidate: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let color: Color
    let emoji: String
    let tags: [String]
    let avatarAssetName: String?

    init(
        name: String,
        subtitle: String,
        color: Color,
        emoji: String,
        tags: [String],
        avatarAssetName: String? = nil
    ) {
        self.name = name
        self.subtitle = subtitle
        self.color = color
        self.emoji = emoji
        self.tags = tags
        self.avatarAssetName = avatarAssetName
    }
}

#Preview {
    NavigationStack {
        AddBruhView()
    }
}
