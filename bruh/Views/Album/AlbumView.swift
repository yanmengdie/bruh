import SwiftUI
import SwiftData

struct AlbumView: View {
    @Query(
        sort: [SortDescriptor(\ContentDelivery.sortDate, order: .reverse)],
        animation: .default
    ) private var deliveries: [ContentDelivery]
    @Query(sort: [SortDescriptor(\Contact.name, order: .forward)]) private var contacts: [Contact]
    @State private var selectedAsset: AlbumAssetSelection?

    private let gridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    private var albumItems: [ContentDelivery] {
        ContentGraphSelectors.visibleAlbumDeliveries(
            from: deliveries,
            contacts: contacts
        )
    }

    private var sections: [AlbumSection] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        let grouped = Dictionary(grouping: albumItems) { item in
            calendar.startOfDay(for: item.sortDate)
        }

        return grouped.keys
            .sorted(by: >)
            .compactMap { day in
                guard let items = grouped[day]?.sorted(by: { $0.sortDate > $1.sortDate }), !items.isEmpty else {
                    return nil
                }

                let title: String
                if day == today {
                    title = "今天"
                } else if day == yesterday {
                    title = "昨天"
                } else {
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "zh_CN")
                    formatter.dateFormat = "M月d日"
                    title = formatter.string(from: day)
                }

                let subtitle = "\(items.count) 张照片"
                return AlbumSection(id: day.formatted(date: .numeric, time: .omitted), title: title, subtitle: subtitle, items: items)
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                topBar
                    .padding(.top, 8)

                if sections.isEmpty {
                    albumEmptyState
                        .padding(.top, 18)
                } else {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            sectionTitle(
                                title: section.title,
                                subtitle: section.subtitle
                            )

                            LazyVGrid(columns: gridColumns, spacing: 2) {
                                ForEach(section.items) { item in
                                    albumTile(for: item)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.messagesBackground)
        .navigationTitle("")
        .onAppear {
            markAlbumAsViewed()
        }
        .onChange(of: latestAlbumTrackingKey) { _, _ in
            guard !albumItems.isEmpty else { return }
            markAlbumAsViewed()
        }
        .fullScreenCover(item: $selectedAsset) { asset in
            AlbumPreviewView(asset: asset)
        }
    }

    private var latestAlbumTrackingKey: String {
        let latestItemId = albumItems.first?.id ?? ""
        let latestSortDate = albumItems.first?.sortDate.timeIntervalSince1970 ?? 0
        return "\(albumItems.count)|\(latestItemId)|\(latestSortDate)"
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            Text("相册")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.9))

            Spacer()
        }
    }

    private func sectionTitle(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.88))

            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.32))
        }
    }

    private var albumEmptyState: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.7))
                .frame(height: 240)
                .overlay {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)
                        Text("还没有相册内容")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.84))
                    }
                }
        }
    }

    private func albumTile(for item: ContentDelivery) -> some View {
        Button {
            guard let imageURLString = item.imageUrl,
                  let url = URL(string: imageURLString) else {
                return
            }
            selectedAsset = AlbumAssetSelection(
                id: item.id,
                url: url,
                caption: item.previewText,
                createdAt: item.sortDate
            )
        } label: {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: URL(string: item.imageUrl ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        RoundedRectangle(cornerRadius: 0, style: .continuous)
                            .fill(Color.black.opacity(0.06))
                            .overlay {
                                Image(systemName: "photo")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.secondary)
                            }
                    case .empty:
                        RoundedRectangle(cornerRadius: 0, style: .continuous)
                            .fill(Color.black.opacity(0.04))
                            .overlay {
                                ProgressView()
                            }
                    @unknown default:
                        Color.black.opacity(0.04)
                    }
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.28)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Text(relativeAlbumTime(item.sortDate))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                    .padding(8)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipped()
        }
        .buttonStyle(.plain)
    }

    private func relativeAlbumTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func markAlbumAsViewed() {
        let scopedDefaults = ScopedUserDefaultsStore()
        scopedDefaults.set(Date().timeIntervalSince1970, for: "lastViewedAlbumAt")
    }
}

private struct AlbumSection: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let items: [ContentDelivery]
}

private struct AlbumAssetSelection: Identifiable {
    let id: String
    let url: URL
    let caption: String
    let createdAt: Date
}

private struct AlbumPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let asset: AlbumAssetSelection

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            AsyncImage(url: asset.url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                case .failure:
                    ContentUnavailableView("图片加载失败", systemImage: "photo")
                        .foregroundStyle(.white)
                case .empty:
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                @unknown default:
                    EmptyView()
                }
            }

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)

                Spacer()

                VStack(alignment: .leading, spacing: 6) {
                    if !asset.caption.isEmpty {
                        Text(asset.caption)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                    }

                    Text(asset.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
        }
    }
}
