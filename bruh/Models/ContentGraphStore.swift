import SwiftData

enum ContentGraphStore {
    @MainActor
    static func backfill(in context: ModelContext) {
        let posts = (try? context.fetch(FetchDescriptor<PersonaPost>())) ?? []
        let messages = (try? context.fetch(FetchDescriptor<PersonaMessage>())) ?? []

        syncFeedPosts(posts, in: context)
        syncIncomingMessages(messages, in: context)
    }
}
