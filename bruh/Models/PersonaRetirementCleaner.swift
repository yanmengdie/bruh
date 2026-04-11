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
}
