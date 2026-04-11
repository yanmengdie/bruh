import Foundation

extension FeedLocalInteractionGenerator {
    static func seedComment(
        authorId: String,
        postAuthorDisplayName: String,
        postContent: String,
        topic: String?,
        variantSeed: String
    ) -> String {
        let english = isLikelyEnglishText(postContent)
        let cue = cueText(from: postContent, topic: topic, english: english)
        let variant = Int(stableHash(variantSeed) % 3)

        switch authorId {
        case "musk":
            return english
                ? englishVariant(variant, options: [
                    "\(cueOrFallback(cue, fallback: "This")) is mostly execution.",
                    "The real constraint matters more than the noise.",
                    "Interesting signal. I'd still watch the bottleneck.",
                ])
                : chineseVariant(variant, options: [
                    "\(cueOrFallback(cue, fallback: "这事"))最后还是看 execution。",
                    "真正该看的还是约束和瓶颈。",
                    "有点意思，但先别被情绪带着走。",
                ])
        case "trump":
            return english
                ? englishVariant(variant, options: [
                    "Strong post. People can feel the momentum.",
                    "\(cueOrFallback(cue, fallback: "This")) is a big signal.",
                    "A lot of people are thinking the same thing.",
                ])
                : chineseVariant(variant, options: [
                    "这条发得很强，气势是有的。",
                    "\(cueOrFallback(cue, fallback: "这事"))本身就是个很强的信号。",
                    "很多人其实都在这么想，只是没说出来。",
                ])
        case "sam_altman":
            return english
                ? englishVariant(variant, options: [
                    "The useful question is what this unlocks next.",
                    "\(cueOrFallback(cue, fallback: "This")) matters if builders can ship more from it.",
                    "The signal is real if it changes what people can do next.",
                ])
                : chineseVariant(variant, options: [
                    "关键还是它接下来能 unlock 什么。",
                    "\(cueOrFallback(cue, fallback: "这件事"))有意义，前提是它真的改变下一步能做什么。",
                    "如果这会改变大家接下来能做成的东西，那信号就是真的。",
                ])
        case "kobe_bryant":
            return english
                ? englishVariant(variant, options: [
                    "Pressure only shows whether the work was really there.",
                    "\(cueOrFallback(cue, fallback: "This")) comes down to standards and execution.",
                    "The part that matters is what they were prepared to do when it got hard.",
                ])
                : chineseVariant(variant, options: [
                    "压力只会暴露训练是不是真的到位。",
                    "\(cueOrFallback(cue, fallback: "这件事"))最后还是标准和执行的问题。",
                    "真正值得看的是，难的时候他们有没有准备好。",
                ])
        default:
            let trimmedAuthorName = postAuthorDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return english
                ? englishVariant(variant, options: [
                    "Interesting angle.",
                    "\(cueOrFallback(cue, fallback: trimmedAuthorName.isEmpty ? "This" : trimmedAuthorName)) is worth watching.",
                    "There is a real signal here.",
                ])
                : chineseVariant(variant, options: [
                    "这条角度挺对。",
                    "\(cueOrFallback(cue, fallback: trimmedAuthorName.isEmpty ? "这件事" : trimmedAuthorName))是值得继续看的。",
                    "这里面确实有信号。",
                ])
        }
    }

    static func replyComment(
        authorId: String,
        viewerComment: String,
        postContent: String,
        topic: String?
    ) -> String {
        let english = isLikelyEnglishText(viewerComment)
        let lowSignal = isLowSignal(viewerComment)
        let cue = cueText(from: postContent, topic: topic, english: english)

        switch authorId {
        case "musk":
            if english {
                return lowSignal ? "Say the concrete bottleneck." : "I saw it. Tell me the actual bottleneck you care about."
            }
            return lowSignal ? "直接说你关心的瓶颈。" : "我看到了，直接说你真正在追问哪个瓶颈。"
        case "trump":
            if english {
                return lowSignal ? "Say it clearly." : "I saw it. Say the strongest version of your point."
            }
            return lowSignal ? "直接说清楚。" : "我看到了，你直接把你最想说的那一句讲出来。"
        case "sam_altman":
            if english {
                return lowSignal ? "Give me the concrete version." : "I saw it. What is the concrete unlock here?"
            }
            return lowSignal ? "先说具体一点。" : "我看到了，你先说这里最具体的 unlock 是什么。"
        case "kobe_bryant":
            if english {
                return lowSignal ? "Say the standard." : "I saw it. Tell me where the standard held or broke."
            }
            return lowSignal ? "直接说标准。" : "我看到了，你直接说这里到底是标准没守住，还是执行没到位。"
        default:
            if english {
                return lowSignal ? "Say a little more." : "I saw it. Say what part of this you want to discuss."
            }
            if !cue.isEmpty {
                return "我看到了，你是想聊 \(cue) 的哪一层？"
            }
            return lowSignal ? "说具体一点。" : "我看到了，直接说你想讨论哪一层。"
        }
    }

    static func cueText(from postContent: String, topic: String?, english: Bool) -> String {
        let trimmedTopic = topic?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedTopic.isEmpty {
            return trimmedTopic
        }

        let trimmedContent = postContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return "" }

        if english {
            let words = trimmedContent
                .split(whereSeparator: \.isWhitespace)
                .prefix(5)
                .map(String.init)
            return words.joined(separator: " ")
        }

        let stripped = trimmedContent
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { "，。！？；,.!?;".contains($0) })
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return String(stripped.prefix(12))
    }

    static func cueOrFallback(_ cue: String, fallback: String) -> String {
        cue.isEmpty ? fallback : cue
    }

    static func englishVariant(_ variant: Int, options: [String]) -> String {
        options[clampedVariant(variant, count: options.count)]
    }

    static func chineseVariant(_ variant: Int, options: [String]) -> String {
        options[clampedVariant(variant, count: options.count)]
    }

    static func clampedVariant(_ variant: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return max(0, min(variant, count - 1))
    }

    static func isLikelyEnglishText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.range(of: #"[一-龥]"#, options: .regularExpression) != nil {
            return false
        }
        return trimmed.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
    }

    static func isLowSignal(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }
        if normalized.count <= 4 {
            return true
        }

        return [
            "hi", "hey", "hello", "ok", "okay", "cool", "nice", "wow", "lol",
            "哈", "哈哈", "嗯", "哦", "在吗",
        ].contains(normalized)
    }
}
