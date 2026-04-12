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
func seedPengyouMoments(into context: ModelContext) {
    let seeds = pengyouMomentSeeds()
    let validIds = Set(seeds.map(\.id))
    let moments: [PengyouMoment] = (try? context.fetch(FetchDescriptor<PengyouMoment>())) ?? []
    let existingById = Dictionary(uniqueKeysWithValues: moments.map { ($0.id, $0) })

    for moment in moments where moment.id.hasPrefix("pengyou:") && !validIds.contains(moment.id) {
        context.delete(moment)
    }

    for seed in seeds {
        if let moment = existingById[seed.id] {
            moment.personaId = seed.personaId
            moment.displayName = seed.displayName
            moment.handle = seed.handle
            moment.avatarName = seed.avatarName
            moment.locationLabel = seed.locationLabel
            moment.sourceType = seed.sourceType
            moment.exportedAt = seed.exportedAt
            moment.postId = seed.postId
            moment.content = seed.content
            moment.sourceUrl = seed.sourceUrl
            moment.mediaUrls = seed.mediaUrls
            moment.videoUrl = seed.videoUrl
            moment.publishedAt = seed.publishedAt
            moment.updatedAt = .now
        } else {
            context.insert(
                PengyouMoment(
                    id: seed.id,
                    personaId: seed.personaId,
                    displayName: seed.displayName,
                    handle: seed.handle,
                    avatarName: seed.avatarName,
                    locationLabel: seed.locationLabel,
                    sourceType: seed.sourceType,
                    exportedAt: seed.exportedAt,
                    postId: seed.postId,
                    content: seed.content,
                    sourceUrl: seed.sourceUrl,
                    mediaUrls: seed.mediaUrls,
                    videoUrl: seed.videoUrl,
                    publishedAt: seed.publishedAt,
                    createdAt: .now,
                    updatedAt: .now
                )
            )
        }
    }

    if context.hasChanges {
        try? context.save()
    }
}

private struct PengyouMomentSeed {
    let personaId: String
    let displayName: String
    let handle: String
    let avatarName: String
    let locationLabel: String
    let sourceType: String
    let exportedAt: Date
    let postId: String
    let content: String
    let sourceUrl: String?
    let mediaUrls: [String]
    let videoUrl: String?
    let publishedAt: Date

    var id: String { "pengyou:\(personaId):\(postId)" }
}

private func pengyouMomentSeeds() -> [PengyouMomentSeed] {
    [
        PengyouMomentSeed(
            personaId: "trump",
            displayName: "特离谱",
            handle: "@realDonaldTrump",
            avatarName: "Avatar_Trump",
            locationLabel: "United States",
            sourceType: "x",
            exportedAt: pengyouDate("2026-04-09T19:38:22.442Z"),
            postId: "2028505632123326484",
            content: "https://t.co/uAxTGrJisv",
            sourceUrl: "https://x.com/realdonaldtrump/status/2028505632123326484",
            mediaUrls: [],
            videoUrl: "https://video.twimg.com/amplify_video/2028504808265744385/vid/avc1/3840x2026/WHLzpB21ED3e_2wi.mp4?tag=21",
            publishedAt: pengyouDate("2026-03-02T16:20:05+00:00")
        ),
        PengyouMomentSeed(
            personaId: "trump",
            displayName: "特离谱",
            handle: "@realDonaldTrump",
            avatarName: "Avatar_Trump",
            locationLabel: "United States",
            sourceType: "x",
            exportedAt: pengyouDate("2026-04-09T19:38:22.442Z"),
            postId: "2027651077865157033",
            content: "https://t.co/BZuJDudLej",
            sourceUrl: "https://x.com/realdonaldtrump/status/2027651077865157033",
            mediaUrls: [],
            videoUrl: "https://video.twimg.com/amplify_video/2027649690032889856/vid/avc1/3840x2026/InXhHRvaG5jNn8QJ.mp4?tag=21",
            publishedAt: pengyouDate("2026-02-28T07:44:23+00:00")
        ),
        PengyouMomentSeed(
            personaId: "trump",
            displayName: "特离谱",
            handle: "@realDonaldTrump",
            avatarName: "Avatar_Trump",
            locationLabel: "United States",
            sourceType: "x",
            exportedAt: pengyouDate("2026-04-09T19:38:22.442Z"),
            postId: "2015833393917747502",
            content: "MELANIA, the Movie, is a MUST WATCH. Get your tickets today - Selling out, FAST! Photo: Regine Mahaux https://t.co/rjwd5Appkv https://t.co/vFpXfV0Mg0",
            sourceUrl: "https://x.com/realdonaldtrump/status/2015833393917747502",
            mediaUrls: ["https://pbs.twimg.com/media/G_mtyaXXcAAvj4V.jpg"],
            videoUrl: nil,
            publishedAt: pengyouDate("2026-01-26T17:05:08+00:00")
        ),
        PengyouMomentSeed(
            personaId: "trump",
            displayName: "特离谱",
            handle: "@realDonaldTrump",
            avatarName: "Avatar_Trump",
            locationLabel: "United States",
            sourceType: "x",
            exportedAt: pengyouDate("2026-04-09T19:38:22.442Z"),
            postId: "2014772963719991311",
            content: "COUNTDOWN: 7 Days until the World will witness an unforgettable, behind-the-scenes, look at one of the most important events of our time. MELANIA: TWENTY DAYS TO HISTORY: https://t.co/rjwd5Appkv https://t.co/AHD0rn1M7C",
            sourceUrl: "https://x.com/realdonaldtrump/status/2014772963719991311",
            mediaUrls: [],
            videoUrl: "https://video.twimg.com/amplify_video/2014772905972776960/vid/avc1/1280x720/m-soU3NaS1n-xyqt.mp4?tag=21",
            publishedAt: pengyouDate("2026-01-23T18:51:21+00:00")
        ),
        PengyouMomentSeed(
            personaId: "trump",
            displayName: "特离谱",
            handle: "@realDonaldTrump",
            avatarName: "Avatar_Trump",
            locationLabel: "United States",
            sourceType: "x",
            exportedAt: pengyouDate("2026-04-09T19:38:22.442Z"),
            postId: "1993801758326616561",
            content: "https://t.co/oQK0HLgf88",
            sourceUrl: "https://x.com/realdonaldtrump/status/1993801758326616561",
            mediaUrls: ["https://pbs.twimg.com/media/G6toIexXAAAuXuy.jpg"],
            videoUrl: nil,
            publishedAt: pengyouDate("2025-11-26T21:59:16+00:00")
        ),
        PengyouMomentSeed(
            personaId: "sam_altman",
            displayName: "凹凸曼",
            handle: "@sama",
            avatarName: "Avatar_Sam Altman",
            locationLabel: "San Francisco",
            sourceType: "x",
            exportedAt: pengyouDate("2026-04-09T19:38:28.014Z"),
            postId: "2037610000122839116",
            content: "The first steel beams went up this week at our Michigan Stargate site with Oracle and Related Digital https://t.co/Hl0NBqwfnS",
            sourceUrl: "https://x.com/sama/status/2037610000122839116",
            mediaUrls: [],
            videoUrl: "https://video.twimg.com/amplify_video/2037609606734925824/vid/avc1/3840x2160/fxk-n4cH0Ng2r_WY.mp4?tag=21",
            publishedAt: pengyouDate("2026-03-27T19:17:35+00:00")
        ),
        PengyouMomentSeed(
            personaId: "sam_altman",
            displayName: "凹凸曼",
            handle: "@sama",
            avatarName: "Avatar_Sam Altman",
            locationLabel: "San Francisco",
            sourceType: "x",
            exportedAt: pengyouDate("2026-04-09T19:38:28.014Z"),
            postId: "2033599375256207820",
            content: "The Codex team are hardcore builders and it really comes through in what they create. No surprise all the hardcore builders I know have switched to Codex. Usage of Codex is growing very fast: https://t.co/lRKcNJDY8n",
            sourceUrl: "https://x.com/sama/status/2033599375256207820",
            mediaUrls: ["https://pbs.twimg.com/media/HDjLsPxbEAAnqGl.png"],
            videoUrl: nil,
            publishedAt: pengyouDate("2026-03-16T17:40:48+00:00")
        ),
        PengyouMomentSeed(
            personaId: "sam_altman",
            displayName: "凹凸曼",
            handle: "@sama",
            avatarName: "Avatar_Sam Altman",
            locationLabel: "San Francisco",
            sourceType: "x",
            exportedAt: pengyouDate("2026-04-09T19:38:28.014Z"),
            postId: "2029622732594499630",
            content: "GPT-5.4 is launching, available now in the API and Codex and rolling out over the course of the day in ChatGPT. It's much better at knowledge work and web search, and it has native computer use capabilities. You can steer it mid-response, and it supports 1m tokens of context. https://t.co/DUrHIhXhzc",
            sourceUrl: "https://x.com/sama/status/2029622732594499630",
            mediaUrls: ["https://pbs.twimg.com/media/HCqqLFAaUAQ43Cd.jpg"],
            videoUrl: nil,
            publishedAt: pengyouDate("2026-03-05T18:19:02+00:00")
        ),
        PengyouMomentSeed(
            personaId: "sam_altman",
            displayName: "凹凸曼",
            handle: "@sama",
            avatarName: "Avatar_Sam Altman",
            locationLabel: "San Francisco",
            sourceType: "x",
            exportedAt: pengyouDate("2026-04-09T19:38:28.014Z"),
            postId: "2024826822060290508",
            content: "Great meeting with PM @narendramodi today to talk about the incredible energy around AI in India. India is our fastest growing market for codex globally, up 4x in weekly users in the past 2 weeks alone. 🇮🇳! https://t.co/MRbw0UkotJ",
            sourceUrl: "https://x.com/sama/status/2024826822060290508",
            mediaUrls: ["https://pbs.twimg.com/media/HBmhLRaWgAANwWX.jpg"],
            videoUrl: nil,
            publishedAt: pengyouDate("2026-02-20T12:41:48+00:00")
        ),
        PengyouMomentSeed(
            personaId: "sam_altman",
            displayName: "凹凸曼",
            handle: "@sama",
            avatarName: "Avatar_Sam Altman",
            locationLabel: "San Francisco",
            sourceType: "x",
            exportedAt: pengyouDate("2026-04-09T19:38:28.014Z"),
            postId: "2023453083595141411",
            content: "Best OpenAI sweatshirt ever https://t.co/PS2bSATW35",
            sourceUrl: "https://x.com/sama/status/2023453083595141411",
            mediaUrls: ["https://pbs.twimg.com/media/HBS_mJObcAM97y7.jpg"],
            videoUrl: nil,
            publishedAt: pengyouDate("2026-02-16T17:43:03+00:00")
        ),
        PengyouMomentSeed(
            personaId: "justin_sun",
            displayName: "孙割",
            handle: "@justinsuntron",
            avatarName: "Avatar_Justin Sun",
            locationLabel: "Hong Kong",
            sourceType: "x",
            exportedAt: pengyouDate("2026-04-09T19:38:39.194Z"),
            postId: "2039693245266223160",
            content: "USDD is doing well. Over 2 billion.@usddio https://t.co/Qo0NNlEiH4",
            sourceUrl: "https://x.com/justinsuntron/status/2039693245266223160",
            mediaUrls: ["https://pbs.twimg.com/media/HE5x5BEbMAAxPiF.jpg"],
            videoUrl: nil,
            publishedAt: pengyouDate("2026-04-02T13:15:39+00:00")
        ),
        PengyouMomentSeed(
            personaId: "justin_sun",
            displayName: "孙割",
            handle: "@justinsuntron",
            avatarName: "Avatar_Justin Sun",
            locationLabel: "Hong Kong",
            sourceType: "x",
            exportedAt: pengyouDate("2026-04-09T19:38:39.194Z"),
            postId: "2031031352146211206",
            content: "公司已经组建了AI工作群，现在已经入职波虾🦞，波牛🐮两个员工，本周预计小团队扩张到十人！ https://t.co/MW3dcJGjIZ",
            sourceUrl: "https://x.com/justinsuntron/status/2031031352146211206",
            mediaUrls: ["https://pbs.twimg.com/media/HC-sP32bAAAKyNO.jpg"],
            videoUrl: nil,
            publishedAt: pengyouDate("2026-03-09T15:36:23+00:00")
        ),
        PengyouMomentSeed(
            personaId: "justin_sun",
            displayName: "孙割",
            handle: "@justinsuntron",
            avatarName: "Avatar_Justin Sun",
            locationLabel: "Hong Kong",
            sourceType: "x",
            exportedAt: pengyouDate("2026-04-09T19:38:39.194Z"),
            postId: "2030702248725201207",
            content: "完成了人生中第一次龙虾TRX交易，个人激动感觉不亚于2012年第一次买了一枚比特币 👏 https://t.co/dI5r8VWobc",
            sourceUrl: "https://x.com/justinsuntron/status/2030702248725201207",
            mediaUrls: ["https://pbs.twimg.com/media/HC6A7cVa8AAultV.jpg"],
            videoUrl: nil,
            publishedAt: pengyouDate("2026-03-08T17:48:39+00:00")
        ),
        PengyouMomentSeed(
            personaId: "justin_sun",
            displayName: "孙割",
            handle: "@justinsuntron",
            avatarName: "Avatar_Justin Sun",
            locationLabel: "Hong Kong",
            sourceType: "x",
            exportedAt: pengyouDate("2026-04-09T19:38:39.194Z"),
            postId: "2027322821580599569",
            content: "Catch me at MERGE São Paulo. 🇧🇷 Looking forward to sharing what we’re building on TRON. https://t.co/1wUBb1tHwr",
            sourceUrl: "https://x.com/justinsuntron/status/2027322821580599569",
            mediaUrls: ["https://pbs.twimg.com/media/HCJy4rEaIAABRu9.jpg"],
            videoUrl: nil,
            publishedAt: pengyouDate("2026-02-27T10:00:01+00:00")
        ),
        PengyouMomentSeed(
            personaId: "justin_sun",
            displayName: "孙割",
            handle: "@justinsuntron",
            avatarName: "Avatar_Justin Sun",
            locationLabel: "Hong Kong",
            sourceType: "x",
            exportedAt: pengyouDate("2026-04-09T19:38:39.194Z"),
            postId: "2024282607362695637",
            content: "Day 2 of Chinese New Year. Celebrating in Hong Kong with Victoria Harbour fireworks. Absolutely stunning. 🎆 To a year of strength, speed, and good fortune. 龙马精神 🐎 https://t.co/cCfRwTU6us",
            sourceUrl: "https://x.com/justinsuntron/status/2024282607362695637",
            mediaUrls: [],
            videoUrl: "https://video.twimg.com/amplify_video/2024280373048594434/vid/avc1/1440x2560/9ygdACLRl_MH3tyD.mp4?tag=21",
            publishedAt: pengyouDate("2026-02-19T00:39:17+00:00")
        ),
        PengyouMomentSeed(
            personaId: "musk",
            displayName: "马期克",
            handle: "@elonmusk",
            avatarName: "Avatar_Elon",
            locationLabel: "X HQ",
            sourceType: "x",
            exportedAt: pengyouDate("2026-04-09T19:38:14.428Z"),
            postId: "2042135870183239802",
            content: "https://t.co/FEMJgzLQzt",
            sourceUrl: "https://x.com/elonmusk/status/2042135870183239802",
            mediaUrls: [],
            videoUrl: "https://video.twimg.com/amplify_video/2042129777360764928/vid/avc1/560x560/AU7ZPdC-Ak9x_0ye.mp4?tag=24",
            publishedAt: pengyouDate("2026-04-09T07:01:47+00:00")
        ),
        PengyouMomentSeed(
            personaId: "musk",
            displayName: "马期克",
            handle: "@elonmusk",
            avatarName: "Avatar_Elon",
            locationLabel: "X HQ",
            sourceType: "x",
            exportedAt: pengyouDate("2026-04-09T19:38:14.428Z"),
            postId: "2042135446751473938",
            content: "Grok will never go to therapy. Never. https://t.co/brJIgWeyRP",
            sourceUrl: "https://x.com/elonmusk/status/2042135446751473938",
            mediaUrls: [],
            videoUrl: "https://video.twimg.com/amplify_video/2041934051737575424/vid/avc1/1920x1080/-bBa3gi5ICdwbf9s.mp4?tag=21",
            publishedAt: pengyouDate("2026-04-09T07:00:06+00:00")
        ),
        PengyouMomentSeed(
            personaId: "musk",
            displayName: "马期克",
            handle: "@elonmusk",
            avatarName: "Avatar_Elon",
            locationLabel: "X HQ",
            sourceType: "x",
            exportedAt: pengyouDate("2026-04-09T19:38:14.428Z"),
            postId: "2042134561103212707",
            content: "Cybertruck is so awesome 😎 https://t.co/5r99xq5m6V",
            sourceUrl: "https://x.com/elonmusk/status/2042134561103212707",
            mediaUrls: [],
            videoUrl: "https://video.twimg.com/amplify_video/2041888126344331264/vid/avc1/1080x1080/Ihh3bruWugvxvGdU.mp4?tag=21",
            publishedAt: pengyouDate("2026-04-09T06:56:35+00:00")
        ),
        PengyouMomentSeed(
            personaId: "musk",
            displayName: "马期克",
            handle: "@elonmusk",
            avatarName: "Avatar_Elon",
            locationLabel: "X HQ",
            sourceType: "x",
            exportedAt: pengyouDate("2026-04-09T19:38:14.428Z"),
            postId: "2042127554224742713",
            content: "Generated with @Grok Imagine https://t.co/44cGoDrcVG",
            sourceUrl: "https://x.com/elonmusk/status/2042127554224742713",
            mediaUrls: [],
            videoUrl: "https://video.twimg.com/amplify_video/2042127469848023040/vid/avc1/720x720/vg-IWJKKlehbi_JG.mp4?tag=24",
            publishedAt: pengyouDate("2026-04-09T06:28:44+00:00")
        ),
        PengyouMomentSeed(
            personaId: "musk",
            displayName: "马期克",
            handle: "@elonmusk",
            avatarName: "Avatar_Elon",
            locationLabel: "X HQ",
            sourceType: "x",
            exportedAt: pengyouDate("2026-04-09T19:38:14.428Z"),
            postId: "2042125968052302319",
            content: "If only we’d trained Grok on just these 2 books, we’d be done already! https://t.co/Xn6UdaAMxM",
            sourceUrl: "https://x.com/elonmusk/status/2042125968052302319",
            mediaUrls: ["https://pbs.twimg.com/media/HFcWvula8AAtzvx.jpg"],
            videoUrl: nil,
            publishedAt: pengyouDate("2026-04-09T06:22:26+00:00")
        ),
        PengyouMomentSeed(
            personaId: "lei_jun",
            displayName: "田车",
            handle: "@leijun",
            avatarName: "Avatar_Leijun",
            locationLabel: "北京",
            sourceType: "x",
            exportedAt: pengyouDate("2026-04-09T19:38:34.822Z"),
            postId: "2036442921872806282",
            content: "Our Q4 2025 results are out! Revenue reached RMB457.3 billion, up 25.0% YoY. Adjusted net profit rose to RMB39.2 billion, up 43.8% YoY. As AI accelerates the \"Human × Car × Home\" ecosystem, R&D expenses reached RMB 33.1 billion, up 37.8% YoY. R&D personnel hit a record high of 25,457.",
            sourceUrl: "https://x.com/leijun/status/2036442921872806282",
            mediaUrls: [
                "https://pbs.twimg.com/media/HELmCrKXMAE-fjS.jpg",
                "https://pbs.twimg.com/media/HELmC3WXAAEq4sT.jpg"
            ],
            videoUrl: nil,
            publishedAt: pengyouDate("2026-03-24T14:00:02+00:00")
        ),
        PengyouMomentSeed(
            personaId: "lei_jun",
            displayName: "田车",
            handle: "@leijun",
            avatarName: "Avatar_Leijun",
            locationLabel: "北京",
            sourceType: "x",
            exportedAt: pengyouDate("2026-04-09T19:38:34.822Z"),
            postId: "2034600797590245843",
            content: "The new-gen Xiaomi SU7 collection is completed with Viridian Green, Radiant Purple, Dawn Pink and Mineral Gray. Which is your favorite? https://t.co/ogtiL32ifL",
            sourceUrl: "https://x.com/leijun/status/2034600797590245843",
            mediaUrls: [
                "https://pbs.twimg.com/media/HDxaoGbWYAA20_I.jpg",
                "https://pbs.twimg.com/media/HDxaoY5W8AAIomL.jpg",
                "https://pbs.twimg.com/media/HDxaovpXkAAlZXd.jpg",
                "https://pbs.twimg.com/media/HDxapCKWMAAfnoz.jpg"
            ],
            videoUrl: nil,
            publishedAt: pengyouDate("2026-03-19T12:00:05+00:00")
        ),
        PengyouMomentSeed(
            personaId: "lei_jun",
            displayName: "田车",
            handle: "@leijun",
            avatarName: "Avatar_Leijun",
            locationLabel: "北京",
            sourceType: "x",
            exportedAt: pengyouDate("2026-04-09T19:38:34.822Z"),
            postId: "2034593251626242426",
            content: "The new-gen Xiaomi SU7 brings new vibrancy. Sporty hues: Blazing Red & Brilliant Magenta. Classic picks: Obsidian Black & Pearl White. https://t.co/7YnMQXhixc",
            sourceUrl: "https://x.com/leijun/status/2034593251626242426",
            mediaUrls: [
                "https://pbs.twimg.com/media/HDxTww9WQAA54gI.jpg",
                "https://pbs.twimg.com/media/HDxTxG2W0AAhN_g.jpg",
                "https://pbs.twimg.com/media/HDxTxcnWUAABc7f.jpg",
                "https://pbs.twimg.com/media/HDxTxyzXsAAfsWR.jpg"
            ],
            videoUrl: nil,
            publishedAt: pengyouDate("2026-03-19T11:30:06+00:00")
        ),
        PengyouMomentSeed(
            personaId: "lei_jun",
            displayName: "田车",
            handle: "@leijun",
            avatarName: "Avatar_Leijun",
            locationLabel: "北京",
            sourceType: "x",
            exportedAt: pengyouDate("2026-04-09T19:38:34.822Z"),
            postId: "2034586958211568120",
            content: "Let me introduce you the new-gen Xiaomi SU7! Our new Coastal Blue is inspired by Italy’s Blue Grotto. The warm Cream Beige interior completes the vibe - love it? https://t.co/nvof1N9TH7",
            sourceUrl: "https://x.com/leijun/status/2034586958211568120",
            mediaUrls: [
                "https://pbs.twimg.com/media/HDxOCZUXUAAdBaw.jpg",
                "https://pbs.twimg.com/media/HDxOC1OW8AA9mMH.jpg",
                "https://pbs.twimg.com/media/HDxODITWUAEh4CK.jpg",
                "https://pbs.twimg.com/media/HDxODeQW0AA8eEZ.jpg"
            ],
            videoUrl: nil,
            publishedAt: pengyouDate("2026-03-19T11:05:06+00:00")
        ),
        PengyouMomentSeed(
            personaId: "lei_jun",
            displayName: "田车",
            handle: "@leijun",
            avatarName: "Avatar_Leijun",
            locationLabel: "北京",
            sourceType: "x",
            exportedAt: pengyouDate("2026-04-09T19:38:34.822Z"),
            postId: "1990760335049937050",
            content: "Our Q3 2025 results are out! Revenue reached RMB113.1 billion - our fourth straight quarter above RMB100 billion, up 22.3% YoY. Adjusted net profit rose to RMB11.3 billion, up 80.9%. Our EV and AI innovation businesses delivered RMB29 billion in revenue, with 108,796 vehicles delivered this quarter. R&D spending reached RMB9.1 billion, up 52.1%, and our R&D team has grown to 24,871 people. We expect to invest over RMB30 billion for the full year.",
            sourceUrl: "https://x.com/leijun/status/1990760335049937050",
            mediaUrls: [
                "https://pbs.twimg.com/media/G6CZ-MjX0AE2WlS.jpg",
                "https://pbs.twimg.com/media/G6CZ-W3XQAA_Cuz.jpg"
            ],
            videoUrl: nil,
            publishedAt: pengyouDate("2025-11-18T12:33:45+00:00")
        ),
    ]
}

private func pengyouDate(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) {
        return date
    }

    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value) ?? .now
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

/// Forces the demo invite order: trump=0, musk=1, sam_altman=2.
/// Resets any accepted/locked states so trump is pending first.
/// Safe to call repeatedly — no-ops if trump is already accepted.
@MainActor
func forceDemoInviteOrder(into context: ModelContext) {
    let contacts: [Contact] = (try? context.fetch(FetchDescriptor<Contact>())) ?? []

    // If trump is already accepted, the demo has progressed — don't reset.
    let trumpContact = contacts.first(where: { $0.linkedPersonaId == "trump" })
    guard trumpContact?.relationshipStatusValue != .accepted else { return }

    let demoOrder: [String: Int] = ["trump": 0, "musk": 1, "sam_altman": 2]

    for contact in contacts {
        guard let personaId = contact.linkedPersonaId, let order = demoOrder[personaId] else { continue }
        contact.inviteOrder = order
    }

    // Set trump to pending, everyone else to locked (will be normalized)
    for contact in contacts {
        guard let personaId = contact.linkedPersonaId else { continue }
        if personaId == "trump" {
            contact.relationshipStatusValue = .pending
        } else if demoOrder[personaId] != nil {
            if contact.relationshipStatusValue != .accepted && contact.relationshipStatusValue != .ignored {
                contact.relationshipStatusValue = .locked
            }
        }
    }

    if context.hasChanges {
        try? context.save()
    }
}
