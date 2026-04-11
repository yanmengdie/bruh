import SwiftData

enum ContentGraphStore {
    @MainActor
    static func backfill(in context: ModelContext) {
        let posts = (try? context.fetch(FetchDescriptor<PersonaPost>())) ?? []
        let messages = (try? context.fetch(FetchDescriptor<PersonaMessage>())) ?? []

        for post in posts {
            syncFeedPost(post, in: context)
        }

        for message in messages where message.isIncoming {
            syncIncomingMessage(message, in: context)
        }
    }
}
