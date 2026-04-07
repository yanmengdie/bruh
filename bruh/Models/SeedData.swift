import Foundation
import SwiftData

@MainActor
func seedPersonas(into context: ModelContext) {
    let existing: [Persona] = (try? context.fetch(FetchDescriptor<Persona>())) ?? []
    guard existing.isEmpty else { return }

    for persona in Persona.all {
        context.insert(persona)
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
