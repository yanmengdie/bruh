import SwiftUI
import SwiftData
import UIKit

struct ContactTagsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Contact.name, order: .forward)]) private var contacts: [Contact]
    @Query(sort: [SortDescriptor(\Persona.inviteOrder, order: .forward)]) private var personas: [Persona]

    @State private var searchText = ""
    @State private var selectedTag = "全部"

    private let preferredTags = ["中国", "美国", "政治", "娱乐", "体育", "财经", "科技"]

    private var acceptedFriends: [TaggedFriendCandidate] {
        contacts
            .filter { $0.relationshipStatusValue == .accepted }
            .compactMap { contact in
                guard let personaId = contact.linkedPersonaId,
                      let persona = personas.first(where: { $0.id == personaId }) else {
                    return nil
                }

                let tags = tags(for: persona)
                guard !tags.isEmpty else { return nil }

                return TaggedFriendCandidate(
                    id: contact.id,
                    name: contact.name,
                    subtitle: persona.subtitle,
                    avatarName: contact.avatarName,
                    fallbackEmoji: avatarEmoji(for: personaId),
                    color: AppTheme.color(from: contact.themeColorHex, fallback: .blue),
                    tags: tags
                )
            }
    }

    private var allTags: [String] {
        let existing = Set(acceptedFriends.flatMap(\.tags))
        return ["全部"] + preferredTags.filter(existing.contains)
    }

    private var filteredFriends: [TaggedFriendCandidate] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return acceptedFriends.filter { friend in
            let matchTag = selectedTag == "全部" || friend.tags.contains(selectedTag)
            let matchSearch: Bool
            if keyword.isEmpty {
                matchSearch = true
            } else {
                matchSearch = friend.name.lowercased().contains(keyword)
                    || friend.subtitle.lowercased().contains(keyword)
                    || friend.tags.joined(separator: " ").lowercased().contains(keyword)
            }
            return matchTag && matchSearch
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                searchField
                    .padding(.top, 8)

                categoryChips

                sectionTitle("已添加鸽们")
                    .padding(.top, 4)

                cards
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

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.30))

            TextField("按姓名或标签搜索...", text: $searchText)
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

    private var cards: some View {
        Group {
            if filteredFriends.isEmpty {
                Text("没有匹配的已添加鸽们，换个 tag 或关键词试试")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 10) {
                    ForEach(filteredFriends) { friend in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(friend.color.opacity(0.22))
                                .frame(width: 44, height: 44)
                                .overlay {
                                    if !friend.avatarName.isEmpty, UIImage(named: friend.avatarName) != nil {
                                        Image(friend.avatarName)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 44, height: 44)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    } else {
                                        Text(friend.fallbackEmoji)
                                            .font(.system(size: 24))
                                    }
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(friend.name)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Color.black.opacity(0.88))
                                Text(friend.subtitle)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(Color.black.opacity(0.36))
                                    .lineLimit(2)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(friend.tags, id: \.self) { tag in
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

                            Text("好友")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color(red: 0.47, green: 0.48, blue: 0.52))
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .background(Color(red: 0.88, green: 0.88, blue: 0.90))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private func tags(for persona: Persona) -> [String] {
        var result: [String] = []

        if let country = countryTag(for: persona) {
            result.append(country)
        }

        for domain in persona.domains {
            switch domain {
            case "politics":
                result.append("政治")
            case "entertainment", "social", "creator", "fashion", "consumer":
                result.append("娱乐")
            case "sports":
                result.append("体育")
            case "finance", "trade", "crypto":
                result.append("财经")
            case "tech", "ai", "ev", "space":
                result.append("科技")
            default:
                continue
            }
        }

        let deduped = Array(NSOrderedSet(array: result)) as? [String] ?? result
        return preferredTags.filter { deduped.contains($0) }
    }

    private func countryTag(for persona: Persona) -> String? {
        let chinaPersonaIds: Set<String> = ["zhang_peng", "lei_jun", "luo_yonghao", "justin_sun", "papi"]
        let usPersonaIds: Set<String> = ["trump", "musk", "zuckerberg", "sam_altman", "kim_kardashian"]

        if chinaPersonaIds.contains(persona.id) { return "中国" }
        if usPersonaIds.contains(persona.id) { return "美国" }

        let lowerLocation = persona.locationLabel.lowercased()
        if lowerLocation.contains("beijing")
            || lowerLocation.contains("shanghai")
            || lowerLocation.contains("shenzhen")
            || lowerLocation.contains("hong kong")
            || lowerLocation.contains("china") {
            return "中国"
        }

        if lowerLocation.contains("united states")
            || lowerLocation.contains("san francisco")
            || lowerLocation.contains("los angeles")
            || lowerLocation.contains("x hq")
            || lowerLocation.contains("meta") {
            return "美国"
        }

        return nil
    }

    private func avatarEmoji(for personaId: String) -> String {
        switch personaId {
        case "trump": return "🧔🏻"
        case "musk": return "🧑🏻‍🚀"
        case "sam_altman": return "🧑🏻‍💻"
        case "lei_jun": return "📱"
        case "luo_yonghao": return "🎤"
        case "justin_sun": return "🧑‍💼"
        case "papi": return "🎬"
        default: return "😎"
        }
    }
}

private struct TaggedFriendCandidate: Identifiable {
    let id: UUID
    let name: String
    let subtitle: String
    let avatarName: String
    let fallbackEmoji: String
    let color: Color
    let tags: [String]
}

#Preview {
    NavigationStack {
        ContactTagsView()
    }
}
