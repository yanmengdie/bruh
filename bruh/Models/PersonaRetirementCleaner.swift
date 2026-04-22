import Foundation
import SwiftData

enum PersonaRetirementCleaner {
    @MainActor
    static func purge(into context: ModelContext) {
        let validPersonaIds = Set(Persona.all.map(\.id))

        let personas: [Persona] = (try? context.fetch(FetchDescriptor<Persona>())) ?? []
        for persona in personas where !validPersonaIds.contains(persona.id) {
            context.delete(persona)
        }

        let contacts: [Contact] = (try? context.fetch(FetchDescriptor<Contact>())) ?? []
        for contact in contacts {
            guard let personaId = contact.linkedPersonaId else { continue }
            if !validPersonaIds.contains(personaId) {
                context.delete(contact)
            }
        }

        let threads: [MessageThread] = (try? context.fetch(FetchDescriptor<MessageThread>())) ?? []
        for thread in threads where !validPersonaIds.contains(thread.personaId) {
            context.delete(thread)
        }

        let messages: [PersonaMessage] = (try? context.fetch(FetchDescriptor<PersonaMessage>())) ?? []
        for message in messages where !validPersonaIds.contains(message.personaId) {
            context.delete(message)
        }

        let posts: [PersonaPost] = (try? context.fetch(FetchDescriptor<PersonaPost>())) ?? []
        for post in posts where !validPersonaIds.contains(post.personaId) {
            context.delete(post)
        }

        let deliveries: [ContentDelivery] = (try? context.fetch(FetchDescriptor<ContentDelivery>())) ?? []
        for delivery in deliveries {
            guard let personaId = delivery.personaId else { continue }
            if !validPersonaIds.contains(personaId) {
                context.delete(delivery)
            }
        }

        let events: [ContentEvent] = (try? context.fetch(FetchDescriptor<ContentEvent>())) ?? []
        for event in events {
            guard let personaId = event.primaryPersonaId else { continue }
            if !validPersonaIds.contains(personaId) {
                context.delete(event)
            }
        }

        let sourceItems: [SourceItem] = (try? context.fetch(FetchDescriptor<SourceItem>())) ?? []
        for item in sourceItems where !item.sourceName.isEmpty && !validPersonaIds.contains(item.sourceName) && item.id.hasPrefix("source:") {
            context.delete(item)
        }

        if context.hasChanges {
            try? context.save()
        }
    }

    @MainActor
    static func purgeLocalData(
        for personaId: String,
        removeContact: Bool = true,
        into context: ModelContext
    ) {
        purgeLocalData(
            for: [personaId],
            removeContacts: removeContact,
            into: context
        )
    }

    @MainActor
    private static func purgeLocalData(
        for personaIds: Set<String>,
        removeContacts: Bool,
        into context: ModelContext
    ) {
        guard !personaIds.isEmpty else { return }

        let posts: [PersonaPost] = (try? context.fetch(FetchDescriptor<PersonaPost>())) ?? []
        let removedPostIds: Set<String> = Set(
            posts.compactMap { post in
                guard personaIds.contains(post.personaId) else { return nil }
                context.delete(post)
                return post.id
            }
        )

        let moments: [PengyouMoment] = (try? context.fetch(FetchDescriptor<PengyouMoment>())) ?? []
        for moment in moments where personaIds.contains(moment.personaId) {
            context.delete(moment)
        }

        if removeContacts {
            let contacts: [Contact] = (try? context.fetch(FetchDescriptor<Contact>())) ?? []
            for contact in contacts {
                guard let personaId = contact.linkedPersonaId,
                      personaIds.contains(personaId) else { continue }
                context.delete(contact)
            }
        }

        let threads: [MessageThread] = (try? context.fetch(FetchDescriptor<MessageThread>())) ?? []
        for thread in threads where personaIds.contains(thread.personaId) {
            context.delete(thread)
        }

        let messages: [PersonaMessage] = (try? context.fetch(FetchDescriptor<PersonaMessage>())) ?? []
        for message in messages where personaIds.contains(message.personaId) {
            context.delete(message)
        }

        let deliveries: [ContentDelivery] = (try? context.fetch(FetchDescriptor<ContentDelivery>())) ?? []
        for delivery in deliveries {
            guard let personaId = delivery.personaId,
                  personaIds.contains(personaId) else { continue }
            context.delete(delivery)
        }

        let events: [ContentEvent] = (try? context.fetch(FetchDescriptor<ContentEvent>())) ?? []
        for event in events {
            guard let personaId = event.primaryPersonaId,
                  personaIds.contains(personaId) else { continue }
            context.delete(event)
        }

        let sourceItems: [SourceItem] = (try? context.fetch(FetchDescriptor<SourceItem>())) ?? []
        for item in sourceItems where !item.sourceName.isEmpty && personaIds.contains(item.sourceName) && item.id.hasPrefix("source:") {
            context.delete(item)
        }

        if !removedPostIds.isEmpty {
            let likes: [FeedLike] = (try? context.fetch(FetchDescriptor<FeedLike>())) ?? []
            for like in likes where removedPostIds.contains(like.postId) {
                context.delete(like)
            }

            let comments: [FeedComment] = (try? context.fetch(FetchDescriptor<FeedComment>())) ?? []
            for comment in comments where removedPostIds.contains(comment.postId) {
                context.delete(comment)
            }

            let seedStates: [FeedInteractionSeedState] = (try? context.fetch(FetchDescriptor<FeedInteractionSeedState>())) ?? []
            for seedState in seedStates where removedPostIds.contains(seedState.postId) {
                context.delete(seedState)
            }
        }

        if context.hasChanges {
            try? context.save()
        }
    }
}
