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

    for persona in personas.sorted(by: { $0.inviteOrder < $1.inviteOrder }) {
        if let contact = existingByPersonaId[persona.id] {
            let previousStatus = contact.relationshipStatusValue
            contact.name = persona.displayName
            contact.phoneNumber = defaultPhoneNumber(for: persona.id)
            contact.email = defaultEmail(for: persona.id)
            contact.avatarName = persona.avatarName
            contact.themeColorHex = persona.themeColorHex
            contact.locationLabel = persona.locationLabel
            contact.inviteOrder = persona.inviteOrder

            if previousStatus == .custom || previousStatus == .accepted {
                contact.relationshipStatusValue = ContactRelationshipStatus.accepted
                contact.acceptedAt = contact.acceptedAt ?? contact.updatedAt
            } else if previousStatus == .ignored {
                contact.ignoredAt = contact.ignoredAt ?? contact.updatedAt
            } else {
                let migratedStatus = resolvedInviteStatus(
                    for: persona.id,
                    legacyInviteState: legacyInviteState,
                    engagedPersonaIds: engagedPersonaIds
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
            engagedPersonaIds: engagedPersonaIds
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
                inviteOrder: persona.inviteOrder,
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

        // Zuckerberg posts
        ("zuckerberg",
         "Llama 4 的开源版本即将发布。我们相信开放AI才能让每个人受益。Meta将继续引领开源AI革命。",
         "news", "https://techcrunch.com/example-llama4", "AI", 0.90, 3),
        ("zuckerberg",
         "Quest 4 的销量超出了我们的预期。VR社交正在成为现实。想象一下，未来你可以在元宇宙里和朋友面对面聊天。",
         "x", "https://x.com/finkd/status/example1", "VR", 0.82, 6),
        ("zuckerberg",
         "Threads月活突破2亿。我们证明了社交媒体可以更健康、更开放。感谢每一位用户的支持！",
         "x", "https://x.com/finkd/status/example2", "社交", 0.87, 10),
        ("zuckerberg",
         "Meta AI助手现在已经集成到所有产品中。从Instagram到WhatsApp，AI将无处不在。这是下一个平台转变。",
         "news", "https://theverge.com/example-meta-ai", "AI", 0.91, 15),
        ("zuckerberg",
         "刚刚和团队完成了新一季的产品路线图。AR眼镜的原型机已经可以连续佩戴4小时了。下一代计算平台即将到来。",
         "x", "https://x.com/finkd/status/example3", "AR", 0.78, 18),
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
    switch personaId {
    case "musk":
        return "+1 310 555 0142"
    case "trump":
        return "+1 561 555 0145"
    case "zuckerberg":
        return "+1 650 555 0108"
    default:
        return "+1 555 0100"
    }
}

private func defaultEmail(for personaId: String) -> String {
    switch personaId {
    case "musk":
        return "elon@x.ai"
    case "trump":
        return "donald@truthsocial.com"
    case "zuckerberg":
        return "mark@meta.com"
    default:
        return "bruh@contact.local"
    }
}

private func legacyInviteStateByPersonaId(userDefaults: UserDefaults = .standard) -> [String: ContactRelationshipStatus] {
    let trumpAccepted = userDefaults.bool(forKey: "invite_trump_accepted")
    let trumpIgnored = userDefaults.bool(forKey: "invite_trump_ignored")
    let muskAccepted = userDefaults.bool(forKey: "invite_musk_accepted")
    let muskIgnored = userDefaults.bool(forKey: "invite_musk_ignored")
    let muskUnlocked = userDefaults.bool(forKey: "invite_musk_unlocked")
    let zuckerbergAccepted = userDefaults.bool(forKey: "invite_zuckerberg_accepted")
    let zuckerbergIgnored = userDefaults.bool(forKey: "invite_zuckerberg_ignored")
    let zuckerbergUnlocked = userDefaults.bool(forKey: "invite_zuckerberg_unlocked")

    var result: [String: ContactRelationshipStatus] = [:]
    result["trump"] = trumpAccepted ? .accepted : (trumpIgnored ? .ignored : .pending)
    result["musk"] = muskAccepted ? .accepted : (muskIgnored ? .ignored : (muskUnlocked ? .pending : .locked))
    result["zuckerberg"] = zuckerbergAccepted ? .accepted : (zuckerbergIgnored ? .ignored : (zuckerbergUnlocked ? .pending : .locked))
    return result
}

private func resolvedInviteStatus(
    for personaId: String,
    legacyInviteState: [String: ContactRelationshipStatus],
    engagedPersonaIds: Set<String>
) -> ContactRelationshipStatus {
    if engagedPersonaIds.contains(personaId) {
        return .accepted
    }

    if let status = legacyInviteState[personaId] {
        return status
    }

    if let entry = PersonaCatalog.entry(for: personaId), entry.inviteOrder == 0 {
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
