import AVKit
import SwiftUI
import SwiftData
import UIKit

struct FeedCard: View {
    @Environment(\.modelContext) private var modelContext

    let delivery: ContentDelivery
    let event: ContentEvent?
    let sourceItem: SourceItem?
    let contact: Contact?

    @State private var isLiked = false
    @State private var showComments = false
    @State private var likes: [FeedLike] = []
    @State private var comments: [FeedComment] = []
    @State private var commentDraft = ""
    @State private var isLoadingInteractions = false
    @State private var isSendingComment = false
    @State private var isUpdatingLike = false
    @State private var interactionError: String?
    @State private var hasLoadedInteractions = false
    @State private var isPresentingImagePreview = false
    @State private var isPresentingVideoPreview = false
    @State private var selectedImageIndex = 0

    private let interactionService = FeedInteractionService()
    private let imageSpacing: CGFloat = 6

    private var previewMediaItems: [FeedMediaItem] {
        Array(delivery.mediaUrls.prefix(9)).compactMap(FeedMediaItem.init(rawValue:))
    }

    private var previewVideoURL: URL? {
        guard let raw = delivery.videoUrl else { return nil }
        return URL(string: raw)
    }

    private var resolvedPersonaId: String {
        delivery.personaId ?? event?.primaryPersonaId ?? "unknown"
    }

    private var displayName: String {
        if delivery.legacyPostId == "demo_moments_groupchat"
            || delivery.id == "delivery:feed:demo_moments_groupchat" {
            return "Elon Musk"
        }
        if delivery.legacyPostId == "demo_moments_kim_brand"
            || delivery.id == "delivery:feed:demo_moments_kim_brand" {
            return "Taylor Swift"
        }
        return contact?.name ?? resolvedPersonaId
    }

    private var bodyText: String {
        let text = delivery.renderedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            return text
        }
        let eventBody = event?.bodyText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !eventBody.isEmpty {
            return eventBody
        }
        return delivery.previewText
    }

    private var interactionTarget: FeedInteractionTarget? {
        let targetId = [
            delivery.legacyPostId,
            delivery.eventId,
            delivery.id,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty }) ?? ""
        let personaId = resolvedPersonaId.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !targetId.isEmpty, !personaId.isEmpty, !content.isEmpty else {
            return nil
        }

        return FeedInteractionTarget(
            id: targetId,
            personaId: personaId,
            postContent: content,
            topic: normalizedValue(event?.category)
        )
    }

    private var canInteract: Bool {
        interactionTarget != nil
    }

    private var imageColumnCount: Int {
        switch previewMediaItems.count {
        case 0, 1:
            return 1
        case 2, 4:
            return 2
        default:
            return 3
        }
    }

    private var imageThumbnailSide: CGFloat {
        switch previewMediaItems.count {
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

    private var imageGridWidth: CGFloat {
        let columns = CGFloat(imageColumnCount)
        guard columns > 0 else { return 0 }
        return columns * imageThumbnailSide + (columns - 1) * imageSpacing
    }

    private var shouldShowInteractionPanel: Bool {
        showComments || isLiked || !likes.isEmpty || !comments.isEmpty || isSendingComment
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 8) {
                Text(displayName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(red: 0.24, green: 0.34, blue: 0.56))

                Text(bodyText)
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)

                imageGrid

                HStack(spacing: 6) {
                    Text(locationText)
                    Text("·")
                    Text(delivery.sortDate, style: .relative)
                }
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

                if canInteract {
                    interactionBar
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await loadInteractionsIfNeeded()
        }
        .fullScreenCover(isPresented: $isPresentingImagePreview) {
            FeedImagePreview(
                items: previewMediaItems,
                selectedIndex: selectedImageIndex,
                isPresented: $isPresentingImagePreview
            )
        }
        .fullScreenCover(isPresented: $isPresentingVideoPreview) {
            if let videoURL = previewVideoURL {
                FeedVideoPreview(
                    url: videoURL,
                    isPresented: $isPresentingVideoPreview
                )
            }
        }
    }

    private var avatar: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(avatarColor)
            .frame(width: 48, height: 48)
            .overlay {
                if let avatarName = avatarAssetName,
                   UIImage(named: avatarName) != nil {
                    Image(avatarName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Text(String(displayName.prefix(1)))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
    }

    private var avatarAssetName: String? {
        if let avatarName = contact?.avatarName, !avatarName.isEmpty {
            return avatarName
        }
        if delivery.legacyPostId == "demo_moments_kim_brand"
            || delivery.id == "delivery:feed:demo_moments_kim_brand" {
            return "Avatar_Taylor"
        }
        return nil
    }

    private var avatarColor: Color {
        switch resolvedPersonaId {
        case "trump": .orange
        case "musk": Color(red: 0.12, green: 0.15, blue: 0.35)
        case "zuckerberg": .purple
        case "sam_altman": Color(red: 0.06, green: 0.12, blue: 0.22)
        case "zhang_peng": Color(red: 0.15, green: 0.39, blue: 0.92)
        case "lei_jun": Color(red: 1.00, green: 0.41, blue: 0.00)
        case "liu_jingkang": Color(red: 0.06, green: 0.62, blue: 0.58)
        case "luo_yonghao": Color(red: 0.50, green: 0.11, blue: 0.11)
        case "justin_sun": Color(red: 0.11, green: 0.74, blue: 0.63)
        case "kim_kardashian": Color(red: 0.72, green: 0.54, blue: 0.42)
        case "papi": Color(red: 0.88, green: 0.11, blue: 0.55)
        default: .gray
        }
    }

    @ViewBuilder
    private var imageGrid: some View {
        if !previewMediaItems.isEmpty {
            realImageGrid(items: previewMediaItems)
        }
    }

    private func realImageGrid(items: [FeedMediaItem]) -> some View {
        Group {
            if items.count == 1 {
                imageThumbnail(item: items[0], index: 0)
                    .frame(width: imageThumbnailSide, height: imageThumbnailSide)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(imageThumbnailSide), spacing: imageSpacing), count: imageColumnCount),
                    spacing: imageSpacing
                ) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        imageThumbnail(item: item, index: index)
                            .frame(width: imageThumbnailSide, height: imageThumbnailSide)
                    }
                }
                .frame(width: imageGridWidth, alignment: .leading)
            }
        }
    }

    private func imageThumbnail(item: FeedMediaItem, index: Int) -> some View {
        Button {
            if previewVideoURL != nil {
                isPresentingVideoPreview = true
            } else {
                selectedImageIndex = index
                isPresentingImagePreview = true
            }
        } label: {
            Group {
                switch item {
                case .localAsset(let assetName):
                    if UIImage(named: assetName) != nil {
                        Image(assetName)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            Color(.systemGray5)
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                        }
                    }
                case .remote(let url):
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            ZStack {
                                Color(.systemGray5)
                                Image(systemName: "photo")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.secondary)
                            }
                        case .empty:
                            ZStack {
                                Color(.systemGray6)
                                ProgressView()
                                    .controlSize(.small)
                            }
                        @unknown default:
                            Color(.systemGray6)
                        }
                    }
                }
            }
            .frame(width: imageThumbnailSide, height: imageThumbnailSide)
            .overlay {
                if previewVideoURL != nil {
                    ZStack {
                        Color.black.opacity(0.18)
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: imageThumbnailSide >= 200 ? 48 : 28))
                            .foregroundStyle(.white)
                    }
                }
            }
            .contentShape(Rectangle())
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var interactionBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()

                HStack(spacing: 0) {
                    Button {
                        toggleLike()
                    } label: {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .foregroundStyle(isLiked ? .red : .secondary)
                            .frame(width: 34, height: 28)
                    }
                    .disabled(isUpdatingLike)

                    Rectangle()
                        .fill(Color.black.opacity(0.08))
                        .frame(width: 0.5, height: 16)

                    Button {
                        showComments.toggle()
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.secondary)
                            .frame(width: 34, height: 28)
                    }
                }
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if shouldShowInteractionPanel {
                VStack(alignment: .leading, spacing: 6) {
                    if !likeSummaryText.isEmpty {
                        Text(likeSummaryText)
                            .font(.system(size: 14))
                            .foregroundStyle(Color(red: 0.24, green: 0.34, blue: 0.56))
                    }

                    if !likeSummaryText.isEmpty && !comments.isEmpty {
                        Rectangle()
                            .fill(Color.black.opacity(0.05))
                            .frame(height: 0.5)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(comments, id: \.id) { comment in
                            VStack(alignment: .leading, spacing: 2) {
                                (
                                    Text(commentPrefix(for: comment))
                                        .fontWeight(.semibold)
                                    + Text(comment.content)
                                )
                                .font(.system(size: 15))
                                .foregroundStyle(.primary)

                                if comment.deliveryState == "failed" {
                                    Text("发送失败，请重试")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }

                    if let interactionError {
                        Text(interactionError)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }

                    HStack(spacing: 8) {
                        TextField("评论一下...", text: $commentDraft, axis: .vertical)
                            .lineLimit(1...3)

                        if isSendingComment {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button("发送") {
                                sendComment()
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .disabled(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .font(.system(size: 14))
                }
                .padding(10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    private var locationText: String {
        if sourceItem?.sourceType == "xiaohongshu" {
            return "中国"
        }

        if let location = contact?.locationLabel, !location.isEmpty {
            return location
        }

        switch resolvedPersonaId {
        case "trump": return "海湖庄园"
        case "musk": return "X HQ"
        case "zuckerberg": return "Meta Park"
        case "sam_altman": return "San Francisco"
        case "zhang_peng": return "北京"
        case "lei_jun": return "北京"
        case "liu_jingkang": return "深圳"
        case "luo_yonghao": return "北京"
        case "justin_sun": return "Hong Kong"
        case "kim_kardashian": return "Los Angeles"
        case "papi": return "上海"
        default: return "中国"
        }
    }

    private var likeNames: [String] {
        var names = likes.map(\.authorDisplayName)
        if isLiked {
            names.append("你")
        }

        return Array(NSOrderedSet(array: names)) as? [String] ?? names
    }

    private var likeSummaryText: String {
        guard !likeNames.isEmpty else { return "" }
        return "♥ \(likeNames.joined(separator: ", "))"
    }

    private func commentPrefix(for comment: FeedComment) -> String {
        let base = "\(comment.authorDisplayName): "
        return comment.inReplyToCommentId == nil ? base : "↳ \(base)"
    }

    private func loadInteractionsIfNeeded() async {
        guard !hasLoadedInteractions else { return }
        guard let interactionTarget else { return }
        hasLoadedInteractions = true
        isLoadingInteractions = true
        interactionError = nil

        do {
            let state = try await interactionService.loadInteractions(for: interactionTarget, modelContext: modelContext)
            likes = state.likes
            comments = state.comments
            isLiked = state.likes.contains(where: { $0.authorId == "viewer" })
        } catch {
            if !shouldIgnoreInteractionError(error) {
                interactionError = error.localizedDescription
            }
        }

        isLoadingInteractions = false
    }

    private func sendComment() {
        let text = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSendingComment, let interactionTarget else { return }

        commentDraft = ""
        interactionError = nil
        isSendingComment = true

        Task {
            do {
                let state = try await interactionService.sendViewerComment(
                    for: interactionTarget,
                    text: text,
                    modelContext: modelContext
                )
                likes = state.likes
                comments = state.comments
                isLiked = state.likes.contains(where: { $0.authorId == "viewer" })
            } catch {
                if !shouldIgnoreInteractionError(error) {
                    interactionError = error.localizedDescription
                }
                if let state = try? interactionService.interactionState(for: interactionTarget.id, modelContext: modelContext) {
                    likes = state.likes
                    comments = state.comments
                    isLiked = state.likes.contains(where: { $0.authorId == "viewer" })
                }
            }
            isSendingComment = false
        }
    }

    private func toggleLike() {
        guard let interactionTarget else { return }
        let targetState = !isLiked
        interactionError = nil
        isUpdatingLike = true

        Task {
            do {
                let state = try await interactionService.setViewerLike(
                    for: interactionTarget,
                    isLiked: targetState,
                    modelContext: modelContext
                )
                likes = state.likes
                comments = state.comments
                isLiked = state.likes.contains(where: { $0.authorId == "viewer" })
            } catch {
                if !shouldIgnoreInteractionError(error) {
                    interactionError = error.localizedDescription
                }
            }
            isUpdatingLike = false
        }
    }

    private func shouldIgnoreInteractionError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return true
        }

        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return message == "cancelled" || message == "canceled"
    }

    private func normalizedValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private struct FeedImagePreview: View {
    let items: [FeedMediaItem]
    let selectedIndex: Int
    @Binding var isPresented: Bool

    @State private var currentIndex: Int = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    ZoomablePreviewImage(item: item)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .always : .never))

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(20)
            }
        }
        .onAppear {
            currentIndex = min(max(selectedIndex, 0), max(items.count - 1, 0))
        }
    }
}

private struct FeedVideoPreview: View {
    let url: URL
    @Binding var isPresented: Bool

    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            Group {
                if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(20)
            }
        }
        .onAppear {
            let player = AVPlayer(url: url)
            self.player = player
            player.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

private struct ZoomablePreviewImage: View {
    let item: FeedMediaItem

    var body: some View {
        Group {
            switch item {
            case .localAsset(let assetName):
                if UIImage(named: assetName) != nil {
                    Image(assetName)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                } else {
                    ContentUnavailableView("图片加载失败", systemImage: "photo")
                        .foregroundStyle(.white)
                }
            case .remote(let url):
                AsyncImage(url: url) { phase in
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
            }
        }
    }
}

private enum FeedMediaItem {
    case remote(URL)
    case localAsset(String)

    init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("asset://") {
            let name = String(trimmed.dropFirst("asset://".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            self = .localAsset(name)
            return
        }
        guard let url = URL(string: trimmed) else { return nil }
        self = .remote(url)
    }
}
