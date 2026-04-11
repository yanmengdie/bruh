import Foundation

struct PengyouMomentSeed {
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

enum PengyouMomentSeedCatalog {
    static let seeds: [PengyouMomentSeed] = [
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
