import Foundation
import SwiftData

@MainActor
func seedPersonas(into context: ModelContext) {
    let existing: [Persona] = (try? context.fetch(FetchDescriptor<Persona>())) ?? []
    let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

    for seed in Persona.all {
        if let persona = existingById[seed.id] {
            persona.displayName = seed.displayName
            persona.avatarName = seed.avatarName
            persona.handle = seed.handle
            persona.domains = seed.domains
            persona.stance = seed.stance
            persona.triggerKeywords = seed.triggerKeywords
            persona.xUsername = seed.xUsername
            persona.subtitle = seed.subtitle
            persona.inviteMessage = seed.inviteMessage
            persona.themeColorHex = seed.themeColorHex
            persona.locationLabel = seed.locationLabel
            persona.inviteOrder = seed.inviteOrder
        } else {
            context.insert(seed)
        }
    }

    if context.hasChanges {
        try? context.save()
    }
}

@MainActor
func purgeRetiredPersonaData(into context: ModelContext) {
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
func seedCurrentUserProfile(into context: ModelContext) {
    _ = CurrentUserProfileStore.fetchOrCreate(in: context)
}

@MainActor
func syncContentGraph(into context: ModelContext) {
    ContentGraphStore.backfill(in: context)

    if context.hasChanges {
        try? context.save()
    }
}

@MainActor
func seedSystemContacts(into context: ModelContext) {
    let personas: [Persona] = (try? context.fetch(FetchDescriptor<Persona>())) ?? []
    let contacts: [Contact] = (try? context.fetch(FetchDescriptor<Contact>())) ?? []
    let existingByPersonaId: [String: Contact] = Dictionary(
        uniqueKeysWithValues: contacts.compactMap { contact in
            guard let personaId = contact.linkedPersonaId else { return nil }
            return (personaId, contact)
        }
    )

    let engagedPersonaIds = fetchEngagedPersonaIds(from: context)
    let legacyInviteState = legacyInviteStateByPersonaId()
    let selectedInterestIds = CurrentUserProfileStore.selectedInterests(in: context)
    let inviteOrderMap = PersonaCatalog.inviteOrderMap(for: selectedInterestIds)
    let firstPendingPersonaId = inviteOrderMap.sorted(by: { $0.value < $1.value }).first?.key

    for persona in personas.sorted(by: { (inviteOrderMap[$0.id] ?? $0.inviteOrder) < (inviteOrderMap[$1.id] ?? $1.inviteOrder) }) {
        let effectiveInviteOrder = inviteOrderMap[persona.id] ?? persona.inviteOrder
        if let contact = existingByPersonaId[persona.id] {
            let previousStatus = contact.relationshipStatusValue
            contact.name = persona.displayName
            contact.phoneNumber = defaultPhoneNumber(for: persona.id)
            contact.email = defaultEmail(for: persona.id)
            contact.avatarName = persona.avatarName
            contact.themeColorHex = persona.themeColorHex
            contact.locationLabel = persona.locationLabel
            contact.inviteOrder = effectiveInviteOrder

            if previousStatus == .custom || previousStatus == .accepted {
                contact.relationshipStatusValue = ContactRelationshipStatus.accepted
                contact.acceptedAt = contact.acceptedAt ?? contact.updatedAt
            } else if previousStatus == .ignored {
                contact.ignoredAt = contact.ignoredAt ?? contact.updatedAt
            } else {
                let migratedStatus = resolvedInviteStatus(
                    for: persona.id,
                    legacyInviteState: legacyInviteState,
                    engagedPersonaIds: engagedPersonaIds,
                    firstPendingPersonaId: firstPendingPersonaId
                )
                contact.relationshipStatusValue = migratedStatus
                if migratedStatus == .accepted {
                    contact.acceptedAt = contact.acceptedAt ?? Date.now
                }
                if migratedStatus == .ignored {
                    contact.ignoredAt = contact.ignoredAt ?? Date.now
                }
            }

            contact.updatedAt = Date.now
            continue
        }

        let status = resolvedInviteStatus(
            for: persona.id,
            legacyInviteState: legacyInviteState,
            engagedPersonaIds: engagedPersonaIds,
            firstPendingPersonaId: firstPendingPersonaId
        )
        context.insert(
            Contact(
                linkedPersonaId: persona.id,
                name: persona.displayName,
                phoneNumber: defaultPhoneNumber(for: persona.id),
                email: defaultEmail(for: persona.id),
                avatarName: persona.avatarName,
                themeColorHex: persona.themeColorHex,
                locationLabel: persona.locationLabel,
                isFavorite: status == .accepted,
                relationshipStatus: status.rawValue,
                inviteOrder: effectiveInviteOrder,
                acceptedAt: status == .accepted ? .now : nil,
                ignoredAt: status == .ignored ? .now : nil,
                affinityScore: status == .accepted ? 0.72 : 0.5
            )
        )
    }

    normalizeInviteFrontier(in: context)

    if context.hasChanges {
        try? context.save()
    }
}

@MainActor
func seedPosts(into context: ModelContext) {
    let existing: [PersonaPost] = (try? context.fetch(FetchDescriptor<PersonaPost>())) ?? []
    guard existing.isEmpty else { return }

    let seedReferenceDate = Date(timeIntervalSince1970: 946684800) // 2000-01-01T00:00:00Z

    let mockPosts: [(personaId: String, content: String, sourceType: String, sourceUrl: String?, topic: String?, score: Double, hoursAgo: Double)] = [
        // Trump posts
        ("trump",
         "美国的关税政策正在起作用！中国终于开始认真谈判了。没有人比我更懂贸易战。我们正在赢，而且赢得很大！🇺🇸",
         "x", "https://x.com/realDonaldTrump/status/example1", "贸易", 0.95, 1),
        ("trump",
         "刚刚和华尔街的大佬们开完会。他们说，特朗普总统，你的经济政策太棒了。股市即将迎来历史性反弹！相信我。",
         "news", "https://bloomberg.com/example-article-1", "经济", 0.88, 4),
        ("trump",
         "TikTok必须属于美国！要么卖，要么关门。我们不会让外国势力控制美国年轻人的思想。这是国家安全问题！",
         "x", "https://x.com/realDonaldTrump/status/example2", "科技", 0.92, 8),
        ("trump",
         "看看那些假新闻媒体又在胡说八道了。他们永远不懂真正的美国人民在想什么。Truth Social才是真相！",
         "x", "https://truthsocial.com/example", "媒体", 0.75, 12),

        // Musk posts
        ("musk",
         "Grok 3 的推理能力又提升了一个数量级。我们正在逼近AGI的边界。OpenAI的朋友们，你们还好吗？😏",
         "x", "https://x.com/elonmusk/status/example1", "AI", 0.93, 2),
        ("musk",
         "SpaceX星舰第七次试飞成功！超重型助推器精准回收。火星殖民又近了一步。人类文明必须成为多星球物种。",
         "x", "https://x.com/elonmusk/status/example2", "太空", 0.97, 5),
        ("musk",
         "特斯拉Q1交付量超预期，但产能仍然是瓶颈。下一代平台将把制造成本降低50%。电动车的未来不可阻挡。",
         "news", "https://electrek.co/example-tesla-q1", "电动车", 0.85, 9),
        ("musk",
         "X平台的算法推荐已经全面转向开源。没有什么需要隐藏的。如果你想知道代码怎么运作，直接去看。透明度才是王道。",
         "x", "https://x.com/elonmusk/status/example3", "社交", 0.80, 14),

    ]

    for mock in mockPosts {
        let post = PersonaPost(
            personaId: mock.personaId,
            content: mock.content,
            sourceType: mock.sourceType,
            sourceUrl: mock.sourceUrl,
            topic: mock.topic,
            importanceScore: mock.score,
            publishedAt: seedReferenceDate.addingTimeInterval(-mock.hoursAgo * 3600),
            fetchedAt: seedReferenceDate,
            isDelivered: true
        )
        context.insert(post)
    }
}

@MainActor
private func fetchEngagedPersonaIds(from context: ModelContext) -> Set<String> {
    let threads: [MessageThread] = (try? context.fetch(FetchDescriptor<MessageThread>())) ?? []
    let messages: [PersonaMessage] = (try? context.fetch(FetchDescriptor<PersonaMessage>())) ?? []
    let threadPersonaIds = threads.map(\.personaId)
    let messagePersonaIds = messages.map(\.personaId)
    return Set(threadPersonaIds + messagePersonaIds)
}

private func defaultPhoneNumber(for personaId: String) -> String {
    let directory: [String: String] = [
        "musk": "+1 310 555 0142",
        "trump": "+1 561 555 0145",
        "sam_altman": "+1 415 555 0112",
        "zhang_peng": "+86 10 5555 0188",
        "lei_jun": "+86 10 5555 0168",
        "liu_jingkang": "+86 755 5555 0136",
        "luo_yonghao": "+86 10 5555 0127",
        "justin_sun": "+852 5550 0133",
        "kim_kardashian": "+1 323 555 0199",
        "papi": "+86 21 5555 0126",
        "kobe_bryant": "+1 213 555 0824",
        "cristiano_ronaldo": "+351 21 555 0107",
    ]

    return directory[personaId] ?? "+1 555 0100"
}

private func defaultEmail(for personaId: String) -> String {
    let directory: [String: String] = [
        "musk": "elon@x.ai",
        "trump": "donald@truthsocial.com",
        "sam_altman": "sam@openai.com",
        "zhang_peng": "peng@geekpark.net",
        "lei_jun": "jun@xiaomi.com",
        "liu_jingkang": "jk@insta360.com",
        "luo_yonghao": "laoluo@smartisan.com",
        "justin_sun": "justin@tron.network",
        "kim_kardashian": "kim@skims.com",
        "papi": "papi@papitube.com",
        "kobe_bryant": "kobe@mamba.local",
        "cristiano_ronaldo": "cr7@cr7.com",
    ]

    return directory[personaId] ?? "bruh@contact.local"
}

private func legacyInviteStateByPersonaId(userDefaults: UserDefaults = .standard) -> [String: ContactRelationshipStatus] {
    let trumpAccepted = userDefaults.bool(forKey: "invite_trump_accepted")
    let trumpIgnored = userDefaults.bool(forKey: "invite_trump_ignored")
    let muskAccepted = userDefaults.bool(forKey: "invite_musk_accepted")
    let muskIgnored = userDefaults.bool(forKey: "invite_musk_ignored")
    let muskUnlocked = userDefaults.bool(forKey: "invite_musk_unlocked")

    var result: [String: ContactRelationshipStatus] = [:]
    result["trump"] = trumpAccepted ? .accepted : (trumpIgnored ? .ignored : .pending)
    result["musk"] = muskAccepted ? .accepted : (muskIgnored ? .ignored : (muskUnlocked ? .pending : .locked))
    return result
}

private func resolvedInviteStatus(
    for personaId: String,
    legacyInviteState: [String: ContactRelationshipStatus],
    engagedPersonaIds: Set<String>,
    firstPendingPersonaId: String?
) -> ContactRelationshipStatus {
    if engagedPersonaIds.contains(personaId) {
        return .accepted
    }

    if let status = legacyInviteState[personaId] {
        return status
    }

    if firstPendingPersonaId == personaId {
        return .pending
    }

    return .locked
}

@MainActor
private func normalizeInviteFrontier(in context: ModelContext) {
    let contacts: [Contact] = (try? context.fetch(FetchDescriptor<Contact>())) ?? []
    let personaContacts = contacts
        .filter { $0.linkedPersonaId != nil }
        .sorted { ($0.inviteOrder ?? 999) < ($1.inviteOrder ?? 999) }

    var frontierLocked = false
    for contact in personaContacts {
        switch contact.relationshipStatusValue {
        case .accepted, .ignored:
            continue
        case .pending:
            if frontierLocked {
                contact.relationshipStatusValue = .locked
            } else {
                frontierLocked = true
            }
        case .locked:
            if !frontierLocked {
                contact.relationshipStatusValue = .pending
                frontierLocked = true
            }
        case .custom:
            continue
        }
    }
}
