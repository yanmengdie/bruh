import SwiftUI
import SwiftData

struct FeedCard: View {
    @Environment(\.modelContext) private var modelContext

    let post: PersonaPost
    let persona: Persona?

    @State private var isLiked = false
    @State private var showComments = true
    @State private var likes: [FeedLike] = []
    @State private var comments: [FeedComment] = []
    @State private var commentDraft = ""
    @State private var isLoadingInteractions = false
    @State private var isSendingComment = false
    @State private var isUpdatingLike = false
    @State private var interactionError: String?
    @State private var hasLoadedInteractions = false

    private let interactionService = FeedInteractionService()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 8) {
                Text(persona?.displayName ?? post.personaId)
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
    }

    private var avatar: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(avatarColor)
            .frame(width: 48, height: 48)
            .overlay {
                Text(String((persona?.displayName ?? post.personaId).prefix(1)))
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

    private var imageGrid: some View {
        GeometryReader { proxy in
            let totalSpacing: CGFloat = 12
            let itemWidth = max((proxy.size.width - totalSpacing) / 3, 0)
            let fills: [LinearGradient] = [
                LinearGradient(colors: [Color(red: 0.41, green: 0.73, blue: 0.92), Color(red: 0.49, green: 0.79, blue: 0.95)], startPoint: .top, endPoint: .bottom),
                LinearGradient(colors: [Color(red: 0.45, green: 0.82, blue: 0.42), Color(red: 0.52, green: 0.86, blue: 0.49)], startPoint: .top, endPoint: .bottom),
                LinearGradient(colors: [Color(red: 0.98, green: 0.79, blue: 0.15), Color(red: 1.0, green: 0.7, blue: 0.18)], startPoint: .top, endPoint: .bottom)
            ]

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(fills[index])
                        .frame(width: itemWidth, height: itemWidth)
                        .overlay {
                            Image(systemName: index == 0 ? "figure.golf" : index == 1 ? "flag.fill" : "photo")
                                .font(.system(size: 22))
                                .foregroundStyle(.white.opacity(0.95))
                        }
                }
            }
        }
        .frame(height: 110)
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

            if showComments || isLiked {
                VStack(alignment: .leading, spacing: 6) {
                    if isLoadingInteractions && comments.isEmpty && likes.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在生成朋友圈互动...")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                    } else {
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
                }
                .padding(10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    private var locationText: String {
        switch post.personaId {
        case "trump": return "海湖庄园"
        case "musk": return "X HQ"
        case "zuckerberg": return "Meta Park"
        default: return "新闻现场"
        }
    }

    private var baseLikeCount: Int {
        Int(post.importanceScore * 5200)
    }

    private var displayLikeCount: String {
        String(baseLikeCount + likeNames.count)
    }

    private var likeNames: [String] {
        var names = likes.map(\.authorDisplayName)
        if isLiked {
            names.append("你")
        }

        return Array(NSOrderedSet(array: names)) as? [String] ?? names
    }

    private var likeSummaryText: String {
        if likeNames.isEmpty {
            return isLiked ? "♥ 你觉得很赞" : ""
        }

        let preview = likeNames.prefix(3).joined(separator: ", ")
        return "♥ \(preview) 等 \(displayLikeCount) 人"
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
            interactionError = error.localizedDescription
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
                interactionError = error.localizedDescription
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
                interactionError = error.localizedDescription
            }
            isUpdatingLike = false
        }
    }
}
