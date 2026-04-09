import SwiftUI
import SwiftData
import UIKit

struct FeedView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("demo.moments.pinned.enabled") private var demoPinnedMomentsEnabled = true
    @State private var isRefreshing = false
    @State private var hasLoadedInitially = false

    @Query(
        sort: \ContentDelivery.sortDate,
        order: .reverse,
        animation: .default
    ) private var deliveries: [ContentDelivery]
    @Query private var events: [ContentEvent]
    @Query private var sourceItems: [SourceItem]

    @Query private var contacts: [Contact]
    private let demoPinnedLegacyPostId = "demo_moments_groupchat"

    private var feedService = FeedService()
    private var currentProfileAvatarImage: UIImage? {
        guard let data = CurrentUserProfileStore.avatarImageData() else { return nil }
        return UIImage(data: data)
    }

    private var acceptedPersonaIds: Set<String> {
        Set(
            contacts
                .filter { $0.relationshipStatusValue == .accepted }
                .compactMap(\.linkedPersonaId)
        )
    }

    private var visibleEntries: [FeedEntry] {
        let eventsById: [String: ContentEvent] = Dictionary(
            uniqueKeysWithValues: events.map { ($0.id, $0) }
        )
        let sourceItemsById: [String: SourceItem] = Dictionary(
            uniqueKeysWithValues: sourceItems.map { ($0.id, $0) }
        )

        var entries: [FeedEntry] = []

        for delivery in deliveries {
            let isDemoPinnedEntry =
                delivery.legacyPostId == demoPinnedLegacyPostId
                || delivery.id == "delivery:feed:\(demoPinnedLegacyPostId)"

            if demoPinnedMomentsEnabled, !isDemoPinnedEntry {
                continue
            }

            guard delivery.channelValue == .feed,
                  delivery.isVisible else {
                continue
            }

            if !isDemoPinnedEntry, !acceptedPersonaIds.contains(delivery.personaId ?? "") {
                continue
            }

            let event = eventsById[delivery.eventId]
            let sourceItem = event?.sourceReferenceIds
                .compactMap { sourceItemsById[$0] }
                .first
            let personaId = delivery.personaId ?? event?.primaryPersonaId ?? ""

            entries.append(
                FeedEntry(
                    delivery: delivery,
                    event: event,
                    sourceItem: sourceItem,
                    contact: contacts.first(where: { $0.linkedPersonaId == personaId })
                )
            )
        }

        return entries.sorted { $0.delivery.sortDate > $1.delivery.sortDate }
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
                            Text("鸽们还没发日常")
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
                                event: entry.event,
                                sourceItem: entry.sourceItem,
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
            Image("Moments_Background")
                .resizable()
                .scaledToFill()
                .frame(height: momentsHeaderHeight)
                .clipped()

            Text(isRefreshing ? "同步中..." : "")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 18)
                .padding(.bottom, 12)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.84, green: 0.81, blue: 0.73))
                .frame(width: 72, height: 72)
                .overlay {
                    if let avatar = currentProfileAvatarImage {
                        Image(uiImage: avatar)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        Text("😎")
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

    private var momentsHeaderHeight: CGFloat {
        let width = UIScreen.main.bounds.width
        return min(max(width * 0.68, 236), 320)
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
    let event: ContentEvent?
    let sourceItem: SourceItem?
    let contact: Contact?

    var id: String { delivery.id }
}

#Preview {
    NavigationStack {
        FeedView()
    }
    .modelContainer(
        for: [
            ContentDelivery.self,
            ContentEvent.self,
            SourceItem.self,
            Contact.self,
            FeedLike.self,
            FeedComment.self,
        ],
        inMemory: true
    )
}
