import OpenAI from "openai"
import type { ConversationTurn } from "../types.js"

const client = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
  baseURL: process.env.OPENAI_BASE_URL || "https://api.openai.com/v1",
})

const MODEL = process.env.OPENAI_MODEL || "gpt-4.1-mini"

const DISCLAIMER_PATTERNS = [
  /as an ai/i, /as a language model/i, /i'm sorry,? but/i,
  /i cannot (?:actually|really)/i, /i don't have (?:personal|real)/i,
  /my (?:training|knowledge) (?:data|cutoff)/i,
]

function cleanReply(text: string): string {
  const lines = text.split("\n")
  const cleaned = lines.filter(line => !DISCLAIMER_PATTERNS.some(p => p.test(line.trim())))
  return cleaned.join("\n").replace(/\n{3,}/g, "\n\n").trim()
}

export async function generateReply(
  system: string,
  messages: { role: "system" | "user" | "assistant"; content: string }[],
  maxRetries = 2,
): Promise<string> {
  let lastError: Error | null = null

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      const response = await client.chat.completions.create({
        model: MODEL,
        messages: [{ role: "system", content: system }, ...messages],
        temperature: 0.85,
        max_tokens: 512,
      })

      const content = response.choices[0]?.message?.content?.trim()
      if (!content) throw new Error("Empty response from LLM")

      return cleanReply(content)
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error))
      const msg = lastError.message.toLowerCase()
      if (msg.includes("401") || msg.includes("403") || msg.includes("api key")) break
      if (attempt < maxRetries) await new Promise(r => setTimeout(r, 500 * (attempt + 1)))
    }
  }

  throw lastError ?? new Error("LLM generation failed")
}
