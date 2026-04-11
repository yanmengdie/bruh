import { fallbackPersonaReply, fallbackTopicHint } from "./fallbacks.ts"

Deno.test("fallbackTopicHint prefers the most relevant news headline", () => {
  const hint = fallbackTopicHint(
    [
      "Here are the news events most relevant right now:",
      "- AI chips surge (technology): demand keeps climbing",
    ].join("\n"),
    [{ content: "ignored", topic: "ignored" }],
  )

  if (hint !== "AI chips surge") {
    throw new Error(`Unexpected topic hint: ${hint}`)
  }
})

Deno.test("fallbackPersonaReply answers identity questions in the persona language", () => {
  const englishReply = fallbackPersonaReply(
    { personaId: "musk", displayName: "Elon", primaryLanguage: "en" },
    "Who are you?",
    [],
    "",
  )

  const chineseReply = fallbackPersonaReply(
    { personaId: "lei_jun", displayName: "雷军", primaryLanguage: "zh" },
    "你是谁",
    [],
    "",
  )

  if (!englishReply.includes("Elon")) {
    throw new Error(`Unexpected English identity reply: ${englishReply}`)
  }

  if (!chineseReply.includes("我是雷军")) {
    throw new Error(`Unexpected Chinese identity reply: ${chineseReply}`)
  }
})

Deno.test("fallbackPersonaReply uses topic-aware persona fallback", () => {
  const reply = fallbackPersonaReply(
    { personaId: "sam_altman", displayName: "Sam", primaryLanguage: "en" },
    "Thoughts?",
    [{ content: "AI chips are everywhere", topic: "AI chips" }],
    "",
  )

  if (!reply.includes("AI chips")) {
    throw new Error(`Expected fallback reply to include topic hint, got: ${reply}`)
  }
})
