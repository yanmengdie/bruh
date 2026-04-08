import SwiftUI
import SwiftData

struct FeedView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isRefreshing = false
    @State private var hasLoadedInitially = false

    @Query(
        sort: \ContentDelivery.sortDate,
        order: .reverse,
        animation: .default
    ) private var deliveries: [ContentDelivery]

    @Query private var posts: [PersonaPost]

    @Query private var contacts: [Contact]

    private var feedService = FeedService()

    private var acceptedPersonaIds: Set<String> {
        Set(
            contacts
                .filter { $0.relationshipStatusValue == .accepted }
                .compactMap(\.linkedPersonaId)
        )
    }

    private var visibleEntries: [FeedEntry] {
        let postsByLegacyId: [String: PersonaPost] = Dictionary(
            uniqueKeysWithValues: posts.map { ($0.id, $0) }
        )

        let postsByEventId: [String: PersonaPost] = posts.reduce(into: [:]) { result, post in
            guard let eventId = post.contentEventId else { return }
            result[eventId] = post
        }

        var entries: [FeedEntry] = []

        for delivery in deliveries {
            guard delivery.channelValue == .feed,
                  delivery.isVisible,
                  acceptedPersonaIds.contains(delivery.personaId ?? "") else {
                continue
            }

            let matchedPost = delivery.legacyPostId.flatMap { postsByLegacyId[$0] }
                ?? postsByEventId[delivery.eventId]
            let personaId = delivery.personaId ?? matchedPost?.personaId ?? ""

            entries.append(
                FeedEntry(
                    delivery: delivery,
                    post: matchedPost,
                    contact: contacts.first(where: { $0.linkedPersonaId == personaId })
                )
            )
        }

        return entries
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                momentsHeader

                LazyVStack(spacing: 0) {
                    if visibleEntries.isEmpty, !isRefreshing {
                        VStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                            Text("还没有朋友圈内容")
                                .font(.system(size: 17, weight: .medium))
                            Text("下拉或稍等片刻同步最新动态")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(visibleEntries) { entry in
                            FeedCard(
                                delivery: entry.delivery,
                                post: entry.post,
                                contact: entry.contact
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
        .refreshable {
            await refresh()
        }
        .task {
            guard !hasLoadedInitially else { return }
            hasLoadedInitially = true
            await refresh()
        }
        .background(Color.white)
    }

    private var momentsHeader: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [
                    Color(red: 0.45, green: 0.43, blue: 0.88),
                    Color(red: 0.57, green: 0.45, blue: 0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 280)
            .overlay(alignment: .bottom) {
                Text("我的朋友圈")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 26)
            }

            HStack(alignment: .bottom, spacing: 10) {
                Text(isRefreshing ? "同步中..." : "今天也有新鲜事")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.bottom, 8)

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
                        Image(systemName: "person.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(.white)
                            .frame(width: 18, height: 18)
                            .overlay {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.gray)
                            }
                            .offset(x: 4, y: 4)
                    }
            }
            .padding(.trailing, 18)
            .offset(y: 28)
        }
        .padding(.bottom, 34)
    }

    private func refresh() async {
        isRefreshing = true
        do {
            let count = try await feedService.refreshFeed(modelContext: modelContext)
            print("Feed refreshed: \(count) new posts")
        } catch {
            print("Feed refresh failed: \(error.localizedDescription)")
        }
        isRefreshing = false
    }
}

private struct FeedEntry: Identifiable {
    let delivery: ContentDelivery
    let post: PersonaPost?
    let contact: Contact?

    var id: String { delivery.id }
}
