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
func seedDemoMomentsStoryboard(into context: ModelContext) {
    let now = Date()
    let demoPosts: [(id: String, personaId: String, content: String, topic: String, minutesAgo: Double, sourceURL: String, mediaUrls: [String])] = [
        (
            "demo_moments_groupchat",
            "musk",
            "Bros, big news — SpaceX just filed for IPO. Every single investment bank on Wall Street is fighting over us right now. Goldman literally sent flowers. 💐🚀",
            "tech",
            8,
            "https://bruh.local/demo/moments/group-chat",
            []
        ),
        (
            "demo_moments_sam_agents",
            "sam_altman",
            "今天把 agent 工作流又压了一轮，速度比昨天快了不少。下一步不是更会聊，而是更会干活。",
            "tech",
            22,
            "https://bruh.local/demo/moments/sam-agents",
            []
        ),
        (
            "demo_moments_liu_camera",
            "liu_jingkang",
            "刚看完一版新镜头测试，极暗环境下细节比上一代稳很多。真正有用的升级，永远是用户一上手就能感知到的那种。",
            "tech",
            35,
            "https://bruh.local/demo/moments/liu-camera",
            []
        ),
        (
            "demo_moments_luo_hackathon",
            "luo_yonghao",
            "黑客松现场最不缺的是想法，最稀缺的是把想法在 48 小时内做出像样的东西。空谈不如上线。",
            "tech",
            51,
            "https://bruh.local/demo/moments/luo-hackathon",
            []
        ),
        (
            "demo_moments_lei_delivery",
            "lei_jun",
            "发布会可以讲情怀，交付只能讲结果。今天工厂排产会又开了 4 个小时，大家都在抢每一分钟。",
            "finance",
            68,
            "https://bruh.local/demo/moments/lei-delivery",
            []
        ),
        (
            "demo_moments_zhang_trend",
            "trump",
            "这轮 AI 竞争像长跑，不是看谁先冲刺，而是看谁每个补给点都不掉速。情绪会退潮，效率不会。懂的人已经开始布局下一季了。",
            "politics",
            84,
            "https://bruh.local/demo/moments/zhang-trend",
            []
        ),
        (
            "demo_moments_kim_brand",
            "taylor_swift",
            "Backstage quick selfie before rehearsal. See you tonight, bruhs ✨",
            "entertainment",
            103,
            "https://bruh.local/demo/moments/taylor-selfie",
            ["asset://TaylorSelfie"]
        ),
        (
            "demo_moments_papi_content",
            "papi",
            "流量这件事很诚实：你要么真有内容，要么就只能靠标题骗点开。骗得了一次，骗不了一周。",
            "entertainment",
            121,
            "https://bruh.local/demo/moments/papi-content",
            []
        ),
        (
            "demo_moments_justin_market",
            "justin_sun",
            "链上今天波动很大，群里大家都在喊“长期主义”，手却比谁都快。市场永远奖励反应速度。",
            "finance",
            144,
            "https://bruh.local/demo/moments/justin-market",
            []
        ),
        (
            "demo_moments_zuck_social",
            "lei_jun",
            "用户今年最在意的已经不是“功能多不多”，而是“每次打开到底值不值”。把打扰变成价值，才是产品分水岭。",
            "tech",
            169,
            "https://bruh.local/demo/moments/zuck-social",
            []
        ),
    ]

    for postSeed in demoPosts {
        let postId = postSeed.id
        let publishedAt = now.addingTimeInterval(-postSeed.minutesAgo * 60)
        var postDescriptor = FetchDescriptor<PersonaPost>(
            predicate: #Predicate { $0.id == postId }
        )
        postDescriptor.fetchLimit = 1

        let post = (try? context.fetch(postDescriptor).first) ?? {
            let item = PersonaPost(
                id: postId,
                personaId: postSeed.personaId,
                content: postSeed.content,
                sourceType: "x",
                sourceUrl: postSeed.sourceURL,
                topic: postSeed.topic,
                importanceScore: 0.96,
                mediaUrls: postSeed.mediaUrls,
                publishedAt: publishedAt,
                fetchedAt: now,
                isDelivered: true
            )
            context.insert(item)
            return item
        }()

        post.personaId = postSeed.personaId
        post.content = postSeed.content
        post.sourceType = "x"
        post.sourceUrl = postSeed.sourceURL
        post.topic = postSeed.topic
        post.importanceScore = 0.96
        post.mediaUrls = postSeed.mediaUrls
        post.publishedAt = publishedAt
        post.fetchedAt = now
        post.isDelivered = true
    }

    let fixedLikes: [(id: String, postId: String, authorId: String, authorDisplayName: String, minutesAgo: Double)] = [
        ("demo-like-groupchat-sam", "demo_moments_groupchat", "sam_altman", "Sam Altman", 7.3),
        ("demo-like-groupchat-liu", "demo_moments_groupchat", "liu_jingkang", "刘靖康", 7.0),
        ("demo-like-groupchat-luo", "demo_moments_groupchat", "luo_yonghao", "罗永浩", 6.8),

        ("demo-like-sam-musk", "demo_moments_sam_agents", "musk", "Elon Musk", 20.0),
        ("demo-like-sam-zuck", "demo_moments_sam_agents", "trump", "特离谱", 19.6),

        ("demo-like-liu-lei", "demo_moments_liu_camera", "lei_jun", "田车", 33.0),
        ("demo-like-liu-papi", "demo_moments_liu_camera", "papi", "Hahi酱", 31.9),

        ("demo-like-luo-musk", "demo_moments_luo_hackathon", "musk", "Elon Musk", 49.7),
        ("demo-like-luo-sam", "demo_moments_luo_hackathon", "sam_altman", "Sam Altman", 48.9),

        ("demo-like-lei-zhang", "demo_moments_lei_delivery", "luo_yonghao", "罗永浩", 66.0),
        ("demo-like-lei-liu", "demo_moments_lei_delivery", "liu_jingkang", "刘靖康", 64.5),

        ("demo-like-zhang-sam", "demo_moments_zhang_trend", "sam_altman", "Sam Altman", 82.0),
        ("demo-like-zhang-musk", "demo_moments_zhang_trend", "musk", "Elon Musk", 81.0),

        ("demo-like-kim-papi", "demo_moments_kim_brand", "papi", "Hahi酱", 101.0),
        ("demo-like-kim-zuck", "demo_moments_kim_brand", "musk", "Elon Musk", 99.2),

        ("demo-like-papi-kim", "demo_moments_papi_content", "kim_kardashian", "Kim Kardashian", 118.0),
        ("demo-like-papi-luo", "demo_moments_papi_content", "luo_yonghao", "罗永浩", 117.6),

        ("demo-like-justin-musk", "demo_moments_justin_market", "musk", "Elon Musk", 141.5),
        ("demo-like-justin-sam", "demo_moments_justin_market", "sam_altman", "Sam Altman", 140.8),

        ("demo-like-zuck-sam", "demo_moments_zuck_social", "sam_altman", "Sam Altman", 165.0),
        ("demo-like-zuck-kim", "demo_moments_zuck_social", "kim_kardashian", "Kim Kardashian", 164.2),
    ]
    let fixedLikeIds = Set(fixedLikes.map(\.id))

    for like in fixedLikes {
        let likeId = like.id
        var descriptor = FetchDescriptor<FeedLike>(
            predicate: #Predicate { $0.id == likeId }
        )
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            existing.postId = like.postId
            existing.authorId = like.authorId
            existing.authorDisplayName = like.authorDisplayName
            existing.reasonCode = "demo"
            existing.createdAt = now.addingTimeInterval(-like.minutesAgo * 60)
            existing.isViewer = false
        } else {
            context.insert(
                FeedLike(
                    id: like.id,
                    postId: like.postId,
                    authorId: like.authorId,
                    authorDisplayName: like.authorDisplayName,
                    reasonCode: "demo",
                    createdAt: now.addingTimeInterval(-like.minutesAgo * 60),
                    isViewer: false
                )
            )
        }
    }

    let fixedComments: [(id: String, postId: String, authorId: String, authorDisplayName: String, content: String, replyToId: String?, minutesAgo: Double)] = [
        (
            "demo-comment-groupchat-sam",
            "demo_moments_groupchat",
            "sam_altman",
            "Sam Altman",
            "Oh, an IPO? How cute. I could take OpenAI public any day I want. I just… choose not to. It's called having OPTIONS, Elon.",
            nil,
            6.2
        ),
        (
            "demo-comment-groupchat-musk",
            "demo_moments_groupchat",
            "musk",
            "Elon Musk",
            "Options? Bro you literally had to restructure your entire company just to figure out if you're a nonprofit or not 😂",
            "demo-comment-groupchat-sam",
            5.8
        ),
        (
            "demo-comment-groupchat-liu",
            "demo_moments_groupchat",
            "liu_jingkang",
            "刘靖康",
            "哎大家都别吵了，都很厉害的。说到 IPO，其实我们做硬件的也一直在探索，Insta360 最近的全景相机卖得挺不错的，大家有空可以体验一下 😊",
            nil,
            5.1
        ),
        (
            "demo-comment-groupchat-luo",
            "demo_moments_groupchat",
            "luo_yonghao",
            "罗永浩",
            "靖康说得对！做硬件确实不容易。毕竟，锤子手机都被我亲手做倒闭了——这种经验不是谁都有的 😂😂😂",
            nil,
            4.6
        ),
        (
            "demo-comment-sam-zhang",
            "demo_moments_sam_agents",
            "liu_jingkang",
            "刘靖康",
            "这条我认同，Agent 今年最关键的是“可交付”而不是“会说话”。",
            nil,
            18.8
        ),
        (
            "demo-comment-liu-luo",
            "demo_moments_liu_camera",
            "luo_yonghao",
            "罗永浩",
            "这就对了，参数表之外，手感和稳定性才是第一生产力。",
            nil,
            30.5
        ),
        (
            "demo-comment-luo-lei",
            "demo_moments_luo_hackathon",
            "lei_jun",
            "田车",
            "48 小时能跑通闭环已经非常硬核了，respect。",
            nil,
            47.8
        ),
        (
            "demo-comment-lei-justin",
            "demo_moments_lei_delivery",
            "justin_sun",
            "孙割",
            "交付才是硬通货，这句可以直接当行业标语。",
            nil,
            63.2
        ),
        (
            "demo-comment-zhang-sam",
            "demo_moments_zhang_trend",
            "sam_altman",
            "Sam Altman",
            "Totally. Progress is compounding, hype is not.",
            nil,
            79.4
        ),
        (
            "demo-comment-kim-papi",
            "demo_moments_kim_brand",
            "papi",
            "Hahi酱",
            "太真实了，吵归吵，最后还是看转化率。",
            nil,
            97.3
        ),
        (
            "demo-comment-papi-kim",
            "demo_moments_papi_content",
            "kim_kardashian",
            "Kim Kardashian",
            "Title hooks are easy. Retention is the real flex.",
            nil,
            115.1
        ),
        (
            "demo-comment-justin-musk",
            "demo_moments_justin_market",
            "musk",
            "Elon Musk",
            "Markets are just psychology with better charts.",
            nil,
            138.6
        ),
        (
            "demo-comment-zuck-sam",
            "demo_moments_zuck_social",
            "sam_altman",
            "Sam Altman",
            "Trust is product. Retention is proof.",
            nil,
            161.4
        ),
    ]
    let fixedCommentIds = Set(fixedComments.map(\.id))

    for comment in fixedComments {
        let commentId = comment.id
        var descriptor = FetchDescriptor<FeedComment>(
            predicate: #Predicate { $0.id == commentId }
        )
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            existing.postId = comment.postId
            existing.authorId = comment.authorId
            existing.authorDisplayName = comment.authorDisplayName
            existing.content = comment.content
            existing.reasonCode = "demo"
            existing.inReplyToCommentId = comment.replyToId
            existing.isViewer = false
            existing.createdAt = now.addingTimeInterval(-comment.minutesAgo * 60)
            existing.deliveryState = "sent"
        } else {
            context.insert(
                FeedComment(
                    id: comment.id,
                    postId: comment.postId,
                    authorId: comment.authorId,
                    authorDisplayName: comment.authorDisplayName,
                    content: comment.content,
                    reasonCode: "demo",
                    inReplyToCommentId: comment.replyToId,
                    isViewer: false,
                    createdAt: now.addingTimeInterval(-comment.minutesAgo * 60),
                    deliveryState: "sent"
                )
            )
        }
    }

    let demoPostIds = Set(demoPosts.map(\.id))
    let demoPostIdPrefix = "demo_moments_"

    let likeCleanupDescriptor = FetchDescriptor<FeedLike>()
    if let existingLikes = try? context.fetch(likeCleanupDescriptor) {
        for like in existingLikes where (demoPostIds.contains(like.postId) || like.postId.hasPrefix(demoPostIdPrefix)) && !fixedLikeIds.contains(like.id) {
            context.delete(like)
        }
    }

    let commentCleanupDescriptor = FetchDescriptor<FeedComment>()
    if let existingComments = try? context.fetch(commentCleanupDescriptor) {
        for comment in existingComments where (demoPostIds.contains(comment.postId) || comment.postId.hasPrefix(demoPostIdPrefix)) && !fixedCommentIds.contains(comment.id) {
            context.delete(comment)
        }
    }

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
    let directory: [String: String] = [
        "musk": "+1 310 555 0142",
        "trump": "+1 561 555 0145",
        "zuckerberg": "+1 650 555 0108",
        "sam_altman": "+1 415 555 0112",
        "zhang_peng": "+86 10 5555 0188",
        "lei_jun": "+86 10 5555 0168",
        "liu_jingkang": "+86 755 5555 0136",
        "luo_yonghao": "+86 10 5555 0127",
        "justin_sun": "+852 5550 0133",
        "kim_kardashian": "+1 323 555 0199",
        "papi": "+86 21 5555 0126",
    ]

    return directory[personaId] ?? "+1 555 0100"
}

private func defaultEmail(for personaId: String) -> String {
    let directory: [String: String] = [
        "musk": "elon@x.ai",
        "trump": "donald@truthsocial.com",
        "zuckerberg": "mark@meta.com",
        "sam_altman": "sam@openai.com",
        "zhang_peng": "peng@geekpark.net",
        "lei_jun": "jun@xiaomi.com",
        "liu_jingkang": "jk@insta360.com",
        "luo_yonghao": "laoluo@smartisan.com",
        "justin_sun": "justin@tron.network",
        "kim_kardashian": "kim@skims.com",
        "papi": "papi@papitube.com",
    ]

    return directory[personaId] ?? "bruh@contact.local"
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
    let personas: [Persona] = (try? context.fetch(FetchDescriptor<Persona>())) ?? []
    let personaById = Dictionary(uniqueKeysWithValues: personas.map { ($0.id, $0) })
    let selectedInterestSet = inviteInterestSet(in: context)

    func personaMatchesSelectedInterests(_ personaId: String) -> Bool {
        guard !selectedInterestSet.isEmpty else { return true }
        guard let persona = personaById[personaId] else { return false }
        return !Set(persona.domains).isDisjoint(with: selectedInterestSet)
    }

    for contact in contacts {
        guard let personaId = contact.linkedPersonaId else { continue }
        if !personaMatchesSelectedInterests(personaId),
           contact.relationshipStatusValue == .pending {
            contact.relationshipStatusValue = .locked
        }
    }

    let personaContacts = contacts
        .filter { contact in
            guard let personaId = contact.linkedPersonaId else { return false }
            return personaMatchesSelectedInterests(personaId)
        }
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

@MainActor
private func inviteInterestSet(in context: ModelContext) -> Set<String> {
    let supported = Set(["politics", "entertainment", "finance", "sports", "tech"])

    let selectedFromProfile = CurrentUserProfileStore.selectedInterests(in: context)
        .filter { supported.contains($0) }
    if !selectedFromProfile.isEmpty {
        return Set(selectedFromProfile)
    }

    let selectedFromOnboarding = OnboardingInterestStore.load()
        .map(\.rawValue)
        .filter { supported.contains($0) }
    if !selectedFromOnboarding.isEmpty {
        return Set(selectedFromOnboarding)
    }

    return Set(["sports", "tech"])
}
