import AVKit
import SwiftUI
import SwiftData
import UIKit

private let staticMomentDraftText = "今天想把看到的、想到的，都认真留在这里。"

struct FeedView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        sort: [SortDescriptor(\PengyouMoment.publishedAt, order: .reverse)],
        animation: .default
    ) private var moments: [PengyouMoment]
    @Query private var profiles: [UserProfile]

    @State private var isPresentingComposer = false

    private var currentProfile: UserProfile? {
        profiles.first(where: { $0.id == CurrentUserProfileStore.userId })
    }

    private var currentProfileAvatarImage: UIImage? {
        guard let data = currentProfile?.avatarImageData else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                momentsHeader

                LazyVStack(spacing: 0) {
                    if moments.isEmpty {
                        emptyState
                    } else {
                        ForEach(moments) { moment in
                            PengyouMomentCard(
                                moment: moment,
                                currentProfileAvatarImage: currentProfileAvatarImage
                            )
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            Divider()
                                .padding(.leading, 76)
                        }
                    }
                }
                .background(.white)
            }
        }
        .background(Color.white)
        .sheet(isPresented: $isPresentingComposer) {
            PengyouComposerSheet()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingComposer = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
        }
    }

    private var momentsHeader: some View {
        ZStack(alignment: .bottomTrailing) {
            Image("Moments_Background")
                .resizable()
                .scaledToFill()
                .frame(height: momentsHeaderHeight)
                .clipped()

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.orange.opacity(0.92), Color.pink.opacity(0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 72, height: 72)
                .overlay {
                    if let avatar = currentProfileAvatarImage {
                        Image(uiImage: avatar)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        Text("📸")
                            .font(.system(size: 34))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white, lineWidth: 4)
                }
                .padding(.trailing, 18)
                .padding(.bottom, 12)
        }
        .frame(height: momentsHeaderHeight)
        .padding(.bottom, 34)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("还没有朋友圈内容")
                .font(.system(size: 17, weight: .medium))
            Text("等你和鸽们更新第一条动态。")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
    }

    private var momentsHeaderHeight: CGFloat {
        let width = UIScreen.main.bounds.width
        return min(max(width * 0.68, 236), 320)
    }
}

private struct PengyouMomentCard: View {
    let moment: PengyouMoment
    let currentProfileAvatarImage: UIImage?

    @State private var selectedImage: PengyouImageSelection?
    @State private var selectedVideo: PengyouVideoSelection?

    private let imageSpacing: CGFloat = 6

    private var previewImageURLs: [URL] {
        RemoteMediaPolicy.normalizedMediaURLs(moment.mediaUrls)
    }

    private var previewVideoURL: URL? {
        RemoteMediaPolicy.normalizedAssetURL(moment.videoUrl)
    }

    private var imageColumnCount: Int {
        switch previewImageURLs.count {
        case 0, 1:
            return 1
        case 2, 4:
            return 2
        default:
            return 3
        }
    }

    private var imageThumbnailSide: CGFloat {
        switch previewImageURLs.count {
        case 0:
            return 0
        case 1:
            return 220
        case 2, 4:
            return 106
        default:
            return 86
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(imageThumbnailSide), spacing: imageSpacing), count: imageColumnCount)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 8) {
                Text(moment.displayName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(red: 0.24, green: 0.34, blue: 0.56))

                Text(moment.content)
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)

                if !previewImageURLs.isEmpty {
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: imageSpacing) {
                        ForEach(Array(previewImageURLs.enumerated()), id: \.offset) { index, url in
                            Button {
                                selectedImage = PengyouImageSelection(id: "\(moment.id)-\(index)", url: url)
                            } label: {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    case .failure:
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.black.opacity(0.06))
                                            .overlay {
                                                Image(systemName: "photo")
                                                    .foregroundStyle(.secondary)
                                            }
                                    case .empty:
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.black.opacity(0.04))
                                            .overlay {
                                                ProgressView()
                                            }
                                    @unknown default:
                                        Color.black.opacity(0.04)
                                    }
                                }
                                .frame(width: imageThumbnailSide, height: imageThumbnailSide)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let videoURL = previewVideoURL {
                    Button {
                        selectedVideo = PengyouVideoSelection(id: moment.id, url: videoURL)
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.black.opacity(0.82), Color.black.opacity(0.58)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            VStack(spacing: 10) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 38))
                                    .foregroundStyle(.white)

                                Text("播放视频")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.94))
                            }
                        }
                        .frame(width: 220, height: 220)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 6) {
                    Text(moment.locationLabel)
                    Text("·")
                    Text(moment.handle)
                    Text("·")
                    Text(moment.publishedAt, style: .relative)
                }
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fullScreenCover(item: $selectedImage) { selection in
            PengyouImagePreview(selection: selection)
        }
        .fullScreenCover(item: $selectedVideo) { selection in
            PengyouVideoPreview(selection: selection)
        }
    }

    private var avatar: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(avatarColor)
            .frame(width: 48, height: 48)
            .overlay {
                if moment.personaId == CurrentUserProfileStore.userId,
                   let avatar = currentProfileAvatarImage {
                    Image(uiImage: avatar)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else if !moment.avatarName.isEmpty, UIImage(named: moment.avatarName) != nil {
                    Image(moment.avatarName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Text(String(moment.displayName.prefix(1)))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
    }

    private var avatarColor: Color {
        switch moment.personaId {
        case "trump": .orange
        case "musk": Color(red: 0.12, green: 0.15, blue: 0.35)
        case "sam_altman": Color(red: 0.06, green: 0.12, blue: 0.22)
        case "lei_jun": Color(red: 1.00, green: 0.41, blue: 0.00)
        case "justin_sun": Color(red: 0.11, green: 0.74, blue: 0.63)
        case CurrentUserProfileStore.userId: Color(red: 0.92, green: 0.42, blue: 0.29)
        default: .gray
        }
    }
}

private struct PengyouComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    private var currentProfile: UserProfile? {
        profiles.first(where: { $0.id == CurrentUserProfileStore.userId })
    }

    private var currentProfileAvatarImage: UIImage? {
        guard let data = currentProfile?.avatarImageData else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(0.9))
                        .frame(width: 54, height: 54)
                        .overlay {
                            if let avatar = currentProfileAvatarImage {
                                Image(uiImage: avatar)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 54, height: 54)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            } else {
                                Text("我")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(currentProfile?.displayName ?? "我")
                            .font(.system(size: 18, weight: .semibold))
                        Text(currentProfile?.bruhHandle ?? "@me")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                Text("默认内容预览")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(staticMomentDraftText)
                    .font(.system(size: 18))
                    .lineSpacing(6)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 0.97, green: 0.97, blue: 0.98))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text("当前版本先提供快捷发布一条默认动态。")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(20)
            .navigationTitle("发朋友圈")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("发布") {
                        publishStaticMoment()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func publishStaticMoment() {
        let now = Date()
        let postId = "manual-\(UUID().uuidString)"
        let profile = currentProfile ?? CurrentUserProfileStore.fetchOrCreate(in: modelContext)

        modelContext.insert(
            PengyouMoment(
                id: "manual:\(postId)",
                personaId: CurrentUserProfileStore.userId,
                displayName: profile.displayName,
                handle: profile.bruhHandle,
                avatarName: "",
                locationLabel: "我的朋友圈",
                sourceType: "manual",
                exportedAt: now,
                postId: postId,
                content: staticMomentDraftText,
                sourceUrl: nil,
                mediaUrls: [],
                videoUrl: nil,
                publishedAt: now,
                createdAt: now,
                updatedAt: now
            )
        )

        if modelContext.hasChanges {
            try? modelContext.save()
        }
        dismiss()
    }
}

private struct PengyouImageSelection: Identifiable {
    let id: String
    let url: URL
}

private struct PengyouVideoSelection: Identifiable {
    let id: String
    let url: URL
}

private struct PengyouImagePreview: View {
    @Environment(\.dismiss) private var dismiss
    let selection: PengyouImageSelection

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            AsyncImage(url: selection.url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.top, 18)
        }
    }
}

private struct PengyouVideoPreview: View {
    @Environment(\.dismiss) private var dismiss
    let selection: PengyouVideoSelection
    @State private var player: AVPlayer

    init(selection: PengyouVideoSelection) {
        self.selection = selection
        _player = State(initialValue: AVPlayer(url: selection.url))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            VideoPlayer(player: player)
                .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.top, 18)
        }
        .onAppear {
            player.play()
        }
        .onDisappear {
            player.pause()
        }
    }
}

#Preview {
    NavigationStack {
        FeedView()
    }
    .modelContainer(
        for: [
            PengyouMoment.self,
            UserProfile.self,
        ],
        inMemory: true
    )
}
