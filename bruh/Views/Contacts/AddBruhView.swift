import SwiftUI

struct AddBruhView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var pendingNames: Set<String> = []

    private let categories = ["全部", "科技", "娱乐", "体育"]
    @State private var selectedCategory = "全部"

    private let trending: [AddBruhCandidate] = [
        .init(name: "Barack Obama", subtitle: "第44任美国总统", color: Color(red: 0.03, green: 0.71, blue: 0.60), emoji: "👨🏿"),
        .init(name: "Tucker Carlson", subtitle: "媒体主持人", color: Color(red: 1.0, green: 0.42, blue: 0.29), emoji: "👱"),
        .init(name: "Tim Cook", subtitle: "苹果 CEO", color: Color(red: 0.58, green: 0.56, blue: 0.97), emoji: "🧑🏻"),
    ]

    private let popular: [AddBruhCandidate] = [
        .init(name: "Taylor Swift", subtitle: "创作歌手", color: Color(red: 0.97, green: 0.79, blue: 0.42), emoji: "👩🏻"),
        .init(name: "Kanye West", subtitle: "说唱歌手 / 设计师", color: Color(red: 0.91, green: 0.49, blue: 0.34), emoji: "👨🏿"),
        .init(name: "LeBron James", subtitle: "NBA 传奇球星", color: Color(red: 0.08, green: 0.54, blue: 0.91), emoji: "👨🏿"),
        .init(name: "Alexandria Ocasio-Cortez", subtitle: "美国众议员", color: Color(red: 0.88, green: 0.24, blue: 0.62), emoji: "👩🏽"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                searchField
                    .padding(.top, 8)

                categoryChips

                sectionTitle("热门推荐")
                    .padding(.top, 4)
                cards(for: trending)

                sectionTitle("人气榜")
                    .padding(.top, 4)
                cards(for: popular)
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
                ForEach(categories, id: \.self) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        Text(category)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(selectedCategory == category ? .white : Color.black.opacity(0.46))
                            .padding(.horizontal, 26)
                            .frame(height: 44)
                            .background(selectedCategory == category ? Color(red: 0.84, green: 0.15, blue: 0.24) : Color.white.opacity(0.52))
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
        VStack(spacing: 10) {
            ForEach(candidates) { candidate in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(candidate.color)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Text(candidate.emoji)
                                .font(.system(size: 24))
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.name)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.88))
                        Text(candidate.subtitle)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color.black.opacity(0.36))
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

private struct AddBruhCandidate: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let color: Color
    let emoji: String
}

#Preview {
    NavigationStack {
        AddBruhView()
    }
}
