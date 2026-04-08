import AVKit
import SwiftUI
import SwiftData

struct FeedCard: View {
    @Environment(\.modelContext) private var modelContext

    let post: PersonaPost
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

    private var previewImageURLs: [URL] {
        Array(post.mediaUrls.prefix(9)).compactMap(URL.init(string:))
    }

    private var previewVideoURL: URL? {
        guard let raw = post.videoUrl else { return nil }
        return URL(string: raw)
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
                Text(contact?.name ?? post.personaId)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(red: 0.24, green: 0.34, blue: 0.56))

                Text(post.content)
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)

                imageGrid

                HStack(spacing: 6) {
                    Text(locationText)
                    Text("·")
                    Text(post.publishedAt, style: .relative)
                }
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

                interactionBar
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await loadInteractionsIfNeeded()
        }
        .fullScreenCover(isPresented: $isPresentingImagePreview) {
            FeedImagePreview(
                urls: previewImageURLs,
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
                Text(String((contact?.name ?? post.personaId).prefix(1)))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }
    }

    private var avatarColor: Color {
        switch post.personaId {
        case "trump": .orange
        case "musk": Color(red: 0.12, green: 0.15, blue: 0.35)
        case "zuckerberg": .purple
        default: .gray
        }
    }

    @ViewBuilder
    private var imageGrid: some View {
        if !previewImageURLs.isEmpty {
            realImageGrid(urls: previewImageURLs)
        }
    }

    private func realImageGrid(urls: [URL]) -> some View {
        Group {
            if urls.count == 1 {
                imageThumbnail(url: urls[0], index: 0)
                    .frame(width: imageThumbnailSide, height: imageThumbnailSide)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(imageThumbnailSide), spacing: imageSpacing), count: imageColumnCount),
                    spacing: imageSpacing
                ) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        imageThumbnail(url: url, index: index)
                            .frame(width: imageThumbnailSide, height: imageThumbnailSide)
                    }
                }
                .frame(width: imageGridWidth, alignment: .leading)
            }
        }
    }

    private func imageThumbnail(url: URL, index: Int) -> some View {
        Button {
            if previewVideoURL != nil {
                isPresentingVideoPreview = true
            } else {
                selectedImageIndex = index
                isPresentingImagePreview = true
            }
        } label: {
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
        if post.sourceType == "xiaohongshu" {
            return "中国"
        }

        if let location = contact?.locationLabel, !location.isEmpty {
            return location
        }

        switch post.personaId {
        case "trump": return "海湖庄园"
        case "musk": return "X HQ"
        case "zuckerberg": return "Meta Park"
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
        hasLoadedInteractions = true
        isLoadingInteractions = true
        interactionError = nil

        do {
            let state = try await interactionService.loadInteractions(for: post, modelContext: modelContext)
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
        guard !text.isEmpty, !isSendingComment else { return }

        commentDraft = ""
        interactionError = nil
        isSendingComment = true

        Task {
            do {
                let state = try await interactionService.sendViewerComment(
                    for: post,
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
                if let state = try? interactionService.interactionState(for: post.id, modelContext: modelContext) {
                    likes = state.likes
                    comments = state.comments
                    isLiked = state.likes.contains(where: { $0.authorId == "viewer" })
                }
            }
            isSendingComment = false
        }
    }

    private func toggleLike() {
        let targetState = !isLiked
        interactionError = nil
        isUpdatingLike = true

        Task {
            do {
                let state = try await interactionService.setViewerLike(
                    for: post,
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
}

private struct FeedImagePreview: View {
    let urls: [URL]
    let selectedIndex: Int
    @Binding var isPresented: Bool

    @State private var currentIndex: Int = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                    ZoomablePreviewImage(url: url)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .always : .never))

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
            currentIndex = min(max(selectedIndex, 0), max(urls.count - 1, 0))
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
    let url: URL

    var body: some View {
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
