export type FallbackContextRow = {
  content: string
  topic: string | null
}

export type FallbackPersona = {
  personaId: string
  displayName: string
  primaryLanguage: string
}

function isIdentityQuestion(text: string) {
  const lower = text.toLowerCase()
  return [
    "who are you",
    "what should i call you",
    "introduce yourself",
    "你是谁",
    "怎么称呼",
    "自我介绍",
  ].some((pattern) => lower.includes(pattern))
}

export function fallbackTopicHint(newsContext: string, contextRows: FallbackContextRow[]) {
  const quotedNews = newsContext
    .split("\n")
    .map((line) => line.trim())
    .find((line) => line.length > 0 && !line.startsWith("Here are"))

  if (quotedNews) {
    const normalizedNews = quotedNews
      .replace(/^-+\s*/, "")
      .replace(/^"+|"+$/g, "")
    const headlineOnly = normalizedNews
      .replace(/\s+\([^)]+\):.*$/, "")
      .replace(/:.*$/, "")
      .trim()

    return (headlineOnly || normalizedNews).slice(0, 90)
  }

  const contextTopic = contextRows.find((row) => (row.topic ?? "").trim().length > 0)?.topic
  if (contextTopic) return contextTopic

  const contextContent = contextRows[0]?.content?.trim()
  return contextContent ? contextContent.slice(0, 90) : ""
}

export function fallbackPersonaReply(
  persona: FallbackPersona,
  userMessage: string,
  contextRows: FallbackContextRow[],
  newsContext: string,
) {
  const english = persona.primaryLanguage === "en"
  const topic = fallbackTopicHint(newsContext, contextRows)

  if (isIdentityQuestion(userMessage)) {
    return english
      ? `${persona.displayName}. Text me the concrete question and we'll skip the fluff.`
      : `我是${persona.displayName}。你直接问具体问题，我们别绕。`
  }

  switch (persona.personaId) {
    case "musk":
      return english
        ? (topic ? `${topic} mostly comes down to execution and constraints. What's the real bottleneck?` : "Start with the bottleneck. Most people optimize the wrong layer.")
        : (topic ? `${topic} 这事先看约束和瓶颈，别先看热闹。` : "先找真正的瓶颈，别在错的那层优化。")
    case "trump":
      return english
        ? (topic ? `${topic} is what weak leadership looks like. Say the strongest move.` : "Lead with strength. Everything else is noise.")
        : (topic ? `${topic} 这就是弱领导力的结果。直接说最强的动作。` : "先讲强弱，不要先讲废话。")
    case "sam_altman":
      return english
        ? (topic ? `${topic} matters if it changes what builders can actually ship next. What's the concrete unlock?` : "Tell me the concrete unlock, not the slogan.")
        : (topic ? `${topic} 真正有意义，是因为它可能改变下一步能做成什么。你先说具体 unlock。` : "先说具体 unlock，不要先喊口号。")
    case "zhang_peng":
      return english
        ? (topic ? `${topic} is more interesting as a signal than as a headline. Which variable changed underneath it?` : "先看变量，再看热闹。")
        : (topic ? `${topic} 更值得看的不是 headline，而是下面哪个变量变了。` : "先看变量，再看热闹。")
    case "lei_jun":
      return english
        ? (topic ? `${topic} only matters if it lands in product, delivery, and user value. Which one are you asking about?` : "Directly tell me the product point.")
        : (topic ? `${topic} 真正有价值，得落到产品、交付和用户价值上。你想问哪一层？` : "直接说产品点。")
    case "luo_yonghao":
      return english
        ? (topic ? `${topic} sounds big, but I care whether the thing is actually done right. Say it like a person.` : "Say it like a person, not like a deck.")
        : (topic ? `${topic} 听着挺大，但我更关心事情到底有没有做对。说人话。` : "说人话，别像在念稿。")
    case "justin_sun":
      return english
        ? (topic ? `${topic} matters because sentiment moves before consensus does. What's your actual trade?` : "What's the actual trade?")
        : (topic ? `${topic} 真正关键的是情绪和价格谁先动。你想表达什么交易判断？` : "你直接说交易判断。")
    case "kim_kardashian":
      return english
        ? (topic ? `${topic} only gets interesting when it becomes culture, brand, and imitation. Which signal do you care about?` : "Tell me whether you mean culture, brand, or attention.")
        : (topic ? `${topic} 值得聊，是因为它会变成文化、品牌和模仿。你在看哪一层？` : "你先说你在看文化、品牌还是关注度。")
    case "papi":
      return english
        ? (topic ? `${topic} gets real only when you can point to an actual scene or emotion. Give me that part.` : "Give me a real scene, not a label.")
        : (topic ? `${topic} 真正有意思，要落到一个具体场景或者情绪上。你把那部分说出来。` : "给我一个具体场景，别只给标签。")
    case "kobe_bryant":
      return english
        ? (topic ? `${topic} only matters if the standard held under pressure. Where did the work show up?` : "Tell me where the standard held or broke.")
        : (topic ? `${topic} 真正关键，是压力上来之后标准有没有守住。你先说工作体现在哪。` : "先说这里的标准是守住了，还是掉下来了。")
    default:
      return english
        ? "Say the concrete part first."
        : "先说具体一点。"
  }
}
