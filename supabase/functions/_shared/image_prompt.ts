import { personaImageStyle } from "./persona_skills.ts"

export type ImagePromptConversationTurn = {
  role: string
  content: string
}

type PersonaImagePromptSubject = {
  displayName: string
  personaId: string
}

const FIXED_AVATAR_STYLE = [
  "chibi cartoon avatar",
  "big head small body proportions",
  "clean vector illustration",
  "thick black outlines",
  "flat color shading with minimal gradients",
  "friendly smiling expression",
  "white or light gray clean background",
  "emoji-style character design",
  "Japanese chibi meets western cartoon style",
  "high detail hair rendering",
  "soft cel shading",
].join(", ")

export function buildImagePrompt(
  persona: PersonaImagePromptSubject,
  userMessage: string,
  conversation: ImagePromptConversationTurn[],
) {
  const recentConversation = conversation
    .slice(-4)
    .map((item) => `${item.role}: ${item.content}`)
    .join("\n")

  return [
    `Create an image that ${persona.displayName} would share.`,
    `Fixed visual style: ${FIXED_AVATAR_STYLE}. This style is mandatory and should stay consistent across generations.`,
    "Make it a single character avatar illustration unless the user explicitly asks for multiple subjects or a different composition.",
    `Persona cues: ${personaImageStyle(persona.personaId)}. Use this for identity, outfit, props, and attitude details without changing the fixed illustration style.`,
    `User request: ${userMessage}`,
    recentConversation ? `Recent chat context:\n${recentConversation}` : "",
    "Make the image visually specific, modern, and coherent.",
    "Ignore any mentions of chat UIs or devices unless the user explicitly asked for them.",
    "Avoid phones, UI mockups, chat bubbles, screenshots, device frames, or text overlays.",
    "Do not add text unless the user explicitly asked for text inside the image.",
  ].filter((item) => item.length > 0).join("\n\n")
}

export function buildGeneratedAvatarPrompt(displayName: string) {
  const trimmedName = displayName.trim()

  return [
    "Create a profile avatar from the reference photo.",
    `Fixed visual style: ${FIXED_AVATAR_STYLE}. This style is mandatory and should stay consistent across generations.`,
    "Preserve the subject's core identity from the reference image, especially face shape, skin tone, hairstyle, age impression, and overall vibe.",
    "Make it a single-character avatar illustration with a centered head-and-shoulders composition.",
    trimmedName ? `This avatar belongs to ${trimmedName}.` : "",
    "Use the reference photo only to keep the person's identity. Do not recreate the real photo background, camera framing, or lighting literally.",
    "Convert the subject fully into the fixed illustration style. Avoid photorealism.",
    "Keep the background clean, bright, and minimal.",
    "Do not add extra people, hands covering the face, phones, UI mockups, chat bubbles, device frames, or text overlays.",
    "Do not add any text.",
  ].filter((item) => item.length > 0).join("\n\n")
}
