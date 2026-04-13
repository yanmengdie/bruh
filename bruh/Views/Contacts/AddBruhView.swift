import SwiftUI
import UIKit

struct AddBruhView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage private var pendingNamesStorage: String
    @State private var searchText = ""

    @State private var selectedTag = "全部"
    private let featuredNames = ["马云", "Tim Cook", "吴京", "Kanye West", "Warren Buffett"]
    private let topicTags = ["科技", "财经", "娱乐", "体育", "政治"]
    private let regionTags = ["中国", "美国"]

    private let candidates: [AddBruhCandidate] = [
        // US (10)
        .init(name: "Taylor Swift", subtitle: "创作歌手", color: Color(red: 0.98, green: 0.80, blue: 0.43), emoji: "🎤", tags: ["美国", "娱乐"], avatarAssetName: "Avatar_Taylor"),
        .init(name: "LeBron James", subtitle: "NBA 球星", color: Color(red: 0.13, green: 0.50, blue: 0.92), emoji: "🏀", tags: ["美国", "体育"], avatarAssetName: "Avatar_LebronJames"),
        .init(name: "MrBeast", subtitle: "YouTube 创作者", color: Color(red: 0.10, green: 0.73, blue: 0.75), emoji: "🎥", tags: ["美国", "娱乐"], avatarAssetName: "Avatar_Beast"),
        .init(name: "Tim Cook", subtitle: "Apple CEO", color: Color(red: 0.57, green: 0.56, blue: 0.97), emoji: "🍎", tags: ["美国", "科技", "财经"], avatarAssetName: "Avatar_Tim Cook"),
        .init(name: "黄仁勋", subtitle: "NVIDIA CEO", color: Color(red: 0.20, green: 0.72, blue: 0.35), emoji: "🖥️", tags: ["美国", "科技", "财经"], avatarAssetName: "Avatar_HuangRenxun"),
        .init(name: "Barack Obama", subtitle: "前美国总统", color: Color(red: 0.03, green: 0.71, blue: 0.60), emoji: "🇺🇸", tags: ["美国", "政治"], avatarAssetName: "Avatar_Obama"),
        .init(name: "Speed", subtitle: "直播创作者", color: Color(red: 0.96, green: 0.33, blue: 0.24), emoji: "⚡️", tags: ["美国", "娱乐", "体育"], avatarAssetName: "Avatar_Speed"),
        .init(name: "Kanye West", subtitle: "音乐人 / 设计师", color: Color(red: 0.40, green: 0.34, blue: 0.30), emoji: "🎵", tags: ["美国", "娱乐"], avatarAssetName: "Avatar_Kanye West"),
        .init(name: "Warren Buffett", subtitle: "伯克希尔董事长", color: Color(red: 0.33, green: 0.48, blue: 0.30), emoji: "💰", tags: ["美国", "财经"], avatarAssetName: "Avatar_Buffet"),
        .init(name: "Sundar Pichai", subtitle: "Google CEO", color: Color(red: 0.29, green: 0.55, blue: 0.89), emoji: "🔎", tags: ["美国", "科技"], avatarAssetName: "Avatar_Sundar Pichai"),

        // China (20)
        .init(name: "马化腾", subtitle: "腾讯 CEO", color: Color(red: 0.09, green: 0.53, blue: 0.93), emoji: "🐧", tags: ["中国", "科技", "财经"], avatarAssetName: "Avatar_MaHuateng"),
        .init(name: "马云", subtitle: "企业家", color: Color(red: 0.97, green: 0.47, blue: 0.10), emoji: "🧭", tags: ["中国", "财经"], avatarAssetName: "Avatar_JackMa"),
        .init(name: "梁文锋", subtitle: "AI 创业者", color: Color(red: 0.14, green: 0.26, blue: 0.82), emoji: "🧠", tags: ["中国", "科技"], avatarAssetName: "Avatar_LiangWenfeng"),
        .init(name: "王小川", subtitle: "AI 创业者", color: Color(red: 0.38, green: 0.34, blue: 0.84), emoji: "🤖", tags: ["中国", "科技"], avatarAssetName: "Avatar_WangXiaochuan"),
        .init(name: "何同学", subtitle: "科技创作者", color: Color(red: 0.11, green: 0.70, blue: 0.69), emoji: "📷", tags: ["中国", "科技", "娱乐"], avatarAssetName: "Avatar_HeTongxue"),
        .init(name: "影视飓风 Tim", subtitle: "视频创作者", color: Color(red: 0.16, green: 0.58, blue: 0.86), emoji: "🎞️", tags: ["中国", "娱乐", "科技"], avatarAssetName: "Avatar_Tim"),
        .init(name: "柯洁", subtitle: "围棋世界冠军", color: Color(red: 0.27, green: 0.33, blue: 0.41), emoji: "⚫️", tags: ["中国", "体育"], avatarAssetName: "Avatar_KeJie"),
        .init(name: "刘翔", subtitle: "奥运冠军", color: Color(red: 0.93, green: 0.38, blue: 0.21), emoji: "🏃", tags: ["中国", "体育"], avatarAssetName: "Avatar_LiuXiang"),
        .init(name: "谷爱凌", subtitle: "自由式滑雪运动员", color: Color(red: 0.58, green: 0.41, blue: 0.86), emoji: "⛷️", tags: ["中国", "体育"], avatarAssetName: "Avatar_GuAiling"),
        .init(name: "李佳琦", subtitle: "直播主播", color: Color(red: 0.91, green: 0.28, blue: 0.45), emoji: "💄", tags: ["中国", "财经", "娱乐"], avatarAssetName: "Avatar_Lijiaqi"),
        .init(name: "李彦宏", subtitle: "百度创始人", color: Color(red: 0.16, green: 0.44, blue: 0.86), emoji: "🧭", tags: ["中国", "科技"], avatarAssetName: "Avatar_Liyanhong"),
        .init(name: "董宇辉", subtitle: "主播", color: Color(red: 0.35, green: 0.46, blue: 0.75), emoji: "📚", tags: ["中国", "娱乐"], avatarAssetName: "Avatar_Dongyuhui"),
        .init(name: "罗翔", subtitle: "法学教师", color: Color(red: 0.24, green: 0.27, blue: 0.39), emoji: "⚖️", tags: ["中国", "政治"], avatarAssetName: "Avatar_Luoxiang"),
        .init(name: "吴京", subtitle: "演员 / 导演", color: Color(red: 0.82, green: 0.26, blue: 0.23), emoji: "🎬", tags: ["中国", "娱乐"], avatarAssetName: "Avatar_Wujing"),
        .init(name: "周鸿祎", subtitle: "360 创始人", color: Color(red: 0.86, green: 0.18, blue: 0.20), emoji: "🛡️", tags: ["中国", "科技"], avatarAssetName: "Avatar_Zhouhongyi"),
        .init(name: "周杰伦", subtitle: "歌手", color: Color(red: 0.57, green: 0.41, blue: 0.78), emoji: "🎹", tags: ["中国", "娱乐"], avatarAssetName: "Avatar_ZhouJielun"),
        .init(name: "易烊千玺", subtitle: "演员 / 歌手", color: Color(red: 0.52, green: 0.60, blue: 0.66), emoji: "⭐️", tags: ["中国", "娱乐"], avatarAssetName: "Avatar_Yiyangqianxi"),
        .init(name: "贾玲", subtitle: "导演 / 演员", color: Color(red: 0.95, green: 0.41, blue: 0.42), emoji: "🎬", tags: ["中国", "娱乐"], avatarAssetName: "Avatar_JiaLing"),
    ]

    private var allTags: [String] {
        let tags = Set(candidates.flatMap(\.tags))
        let preferredOrder = ["中国", "美国", "政治", "娱乐", "体育", "财经", "科技"]
        let ordered = preferredOrder.filter(tags.contains)
        let extras = tags.subtracting(preferredOrder).sorted()
        return ["全部"] + ordered + extras
    }

    private var filteredCandidates: [AddBruhCandidate] {
        candidates.filter(matchesCurrentFilter)
    }

    private var pendingNames: Set<String> {
        Set(
            pendingNamesStorage
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private var totalPendingCount: Int {
        pendingNames.count
    }

    private var featuredCandidates: [AddBruhCandidate] {
        featuredNames.compactMap { name in
            filteredCandidates.first(where: { $0.name == name })
        }
    }

    private var moreCandidates: [AddBruhCandidate] {
        let featuredSet = Set(featuredCandidates.map(\.name))
        return filteredCandidates.filter { !featuredSet.contains($0.name) }
    }

    init(
        userDefaults: UserDefaults = .standard,
        appEnvironment: AppEnvironment = .current
    ) {
        let scopedDefaults = ScopedUserDefaultsStore(
            userDefaults: userDefaults,
            appEnvironment: appEnvironment
        )
        _pendingNamesStorage = AppStorage(
            wrappedValue: "",
            scopedDefaults.key("contacts.addBruh.pendingNames"),
            store: userDefaults
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                searchField
                    .padding(.top, 8)

                categoryChips

                recommendationIntro

                if featuredCandidates.isEmpty && moreCandidates.isEmpty {
                    discoveryEmptyState
                        .padding(.top, 4)
                } else {
                    if !featuredCandidates.isEmpty {
                        sectionTitle("先认识这些人")
                            .padding(.top, 4)
                        cards(for: featuredCandidates, section: .featured)
                    }

                    if !moreCandidates.isEmpty {
                        sectionTitle("继续探索")
                            .padding(.top, 4)
                        cards(for: moreCandidates, section: .explore)
                    }
                }
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
                AppBackButton {
                    dismiss()
                }
            }
        }
        .enableUnifiedSwipeBack()
    }

    private var recommendationIntro: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(selectedTag == "全部" ? "先从这些鸽们开始认识" : "先从\(selectedTag)方向开始认识")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.84))

                Text(selectedTag == "全部"
                     ? "点“想认识”后会进入等待中，你可以随时回来继续看。"
                     : "当前按标签优先展示，点“想认识”后会进入等待中。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.48))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if totalPendingCount > 0 {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(totalPendingCount)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color(red: 0.83, green: 0.16, blue: 0.26))
                    Text("等待中")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.45))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(red: 0.98, green: 0.93, blue: 0.91))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        }
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

    private var discoveryEmptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("没有找到匹配的鸽们")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.68))
            Text("换个关键词或标签，再继续看看。")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.42))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.64))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func cards(for candidates: [AddBruhCandidate], section: CandidateSection) -> some View {
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

                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.name)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.88))
                        Text(candidate.subtitle)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color.black.opacity(0.36))
                            .lineLimit(2)

                        Text("说明：\(detailText(for: candidate, section: section))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(red: 0.76, green: 0.20, blue: 0.28))
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
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            updatePendingNames { pendingNames in
                                pendingNames.insert(candidate.name)
                            }
                        }
                    } label: {
                        Text(isPending ? "等待中" : "想认识")
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
                .background(Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.72))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }

    private func matchesCurrentFilter(_ candidate: AddBruhCandidate) -> Bool {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

    private func detailText(for candidate: AddBruhCandidate, section: CandidateSection) -> String {
        if pendingNames.contains(candidate.name) {
            return "已进入等待中，稍后回来继续看看"
        }

        switch section {
        case .featured:
            if selectedTag != "全部", candidate.tags.contains(selectedTag) {
                return "匹配你正在浏览的\(selectedTag)标签"
            }
            if let topicTag = candidate.tags.first(where: { topicTags.contains($0) }) {
                return "适合作为\(topicTag)方向的起点"
            }
            return "适合作为当前探索的起点"
        case .explore:
            if selectedTag != "全部", candidate.tags.contains(selectedTag) {
                return "匹配你正在浏览的\(selectedTag)标签"
            }
            if let topicTag = candidate.tags.first(where: { topicTags.contains($0) }) {
                return "可从\(topicTag)方向继续探索"
            }
            if let regionTag = candidate.tags.first(where: { regionTags.contains($0) }) {
                return "可先从\(regionTag)范围继续筛选"
            }
            return "适合加入候选后再进一步比较"
        }
    }

    private func updatePendingNames(_ update: (inout Set<String>) -> Void) {
        var names = pendingNames
        update(&names)
        pendingNamesStorage = names.sorted().joined(separator: "\n")
    }

    private enum CandidateSection {
        case featured
        case explore
    }
}

private struct AddBruhCandidate: Identifiable {
    let id: String
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
        self.id = name
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
