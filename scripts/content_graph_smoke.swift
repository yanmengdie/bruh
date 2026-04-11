import Foundation
import SwiftData

@main
struct ContentGraphSmoke {
    static func main() throws {
        let schema = Schema([
            SourceItem.self,
            ContentEvent.self,
            ContentDelivery.self,
            PersonaPost.self,
            PersonaMessage.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let publishedAt = ISO8601DateFormatter().date(from: "2026-04-11T00:00:00Z") ?? .now
        let fetchedAt = ISO8601DateFormatter().date(from: "2026-04-11T00:01:00Z") ?? .now

        let post = PersonaPost(
            id: "post-1",
            personaId: "musk",
            content: "Factory throughput is the real bottleneck.",
            sourceType: "x",
            sourceUrl: "https://x.com/example/1",
            topic: "tech",
            importanceScore: 0.9,
            mediaUrls: [],
            videoUrl: nil,
            publishedAt: publishedAt,
            fetchedAt: fetchedAt,
            isDelivered: true
        )
        context.insert(post)
        ContentGraphStore.syncFeedPost(post, in: context)

        expect(post.contentEventId == "event:feed:post-1", "Expected feed post to link to a content event")
        expect(fetch(SourceItem.self, in: context).count == 1, "Expected one source item after feed sync")
        expect(fetch(ContentEvent.self, in: context).count == 1, "Expected one content event after feed sync")
        expect(fetch(ContentDelivery.self, in: context).count == 1, "Expected one delivery after feed sync")

        post.content = "Factory throughput is still the real bottleneck."
        post.mediaUrls = ["https://example.com/media.jpg"]
        ContentGraphStore.syncFeedPost(post, in: context)
        expect(fetch(ContentEvent.self, in: context).count == 1, "Expected feed sync to update, not duplicate, events")

        let message = PersonaMessage(
            id: "msg-1",
            threadId: "musk",
            personaId: "musk",
            text: "Look at this production line.",
            imageUrl: "https://example.com/image.jpg",
            sourceUrl: "https://example.com/source",
            isIncoming: true,
            createdAt: fetchedAt.addingTimeInterval(60),
            sourcePostIds: ["event-1"],
            isSeedMessage: true
        )
        context.insert(message)
        ContentGraphStore.syncIncomingMessage(message, in: context)
        ContentGraphStore.syncIncomingMessage(message, in: context)

        let events = fetch(ContentEvent.self, in: context)
        let deliveries = fetch(ContentDelivery.self, in: context)

        expect(events.count == 2, "Expected message sync to add exactly one new content event")
        expect(deliveries.count == 3, "Expected message sync to create message and album deliveries")

        guard let messageEvent = events.first(where: { $0.id == "event:message:msg-1" }) else {
            fail("Missing content event for incoming message")
        }
        expect(messageEvent.kindValue == .generatedImage, "Expected image-bearing starter to map to generatedImage event kind")
        expect(messageEvent.sourceReferenceIds == ["event-1"], "Expected message event to keep source post ids")

        guard let albumDelivery = deliveries.first(where: { $0.id == "delivery:album:msg-1" }) else {
            fail("Missing album delivery for incoming image")
        }
        expect(albumDelivery.imageUrl == "https://example.com/image.jpg", "Expected album delivery to preserve image URL")

        guard let messageDelivery = deliveries.first(where: { $0.id == "delivery:message:msg-1" }) else {
            fail("Missing message delivery for incoming message")
        }
        expect(messageDelivery.threadId == "musk", "Expected message delivery to remain attached to thread")

        print("Content graph smoke passed")
    }

    private static func fetch<T: PersistentModel>(_ type: T.Type, in context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fail(message)
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}
