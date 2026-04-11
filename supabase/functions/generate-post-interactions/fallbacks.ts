import { sanitizeGeneratedText } from "../_shared/content_safety.ts";
import { resolvePersonaById } from "../_shared/personas.ts";
import { logGenerationEvent } from "./helpers.ts";

export type InteractionTextContext = {
  postId: string;
  personaId: string;
  targetId: string;
  mode: "seed" | "reply";
  source: string;
};

export type InteractionFallbackContext = {
  postId: string;
  personaId: string;
  mode: "seed" | "reply";
};

export function cleanGeneratedText(text: string): string {
  return text
    .split("\n")
    .filter((line) => {
      const lower = line.trim().toLowerCase();
      if (lower.length === 0) return false;
      return ![
        "i'm cursor",
        "i am cursor",
        "i'm claude",
        "i am claude",
        "i'm gpt",
        "i am gpt",
        "i'm an ai",
        "i am an ai",
        "i'm a language model",
        "i am a language model",
      ].some((pattern) => lower.includes(pattern));
    })
    .join(" ")
    .replace(/\s+/g, " ")
    .replace(/\bmade by [^.?!]+[.?!]?/gi, "")
    .trim();
}

function genericInteractionFallback(targetId: string): string {
  const persona = resolvePersonaById(targetId);
  return persona?.primaryLanguage === "en"
    ? "Interesting signal here."
    : "这条背后的信号比表面更强。";
}

export function sanitizeInteractionText(
  text: string,
  context: InteractionTextContext,
): string {
  const safety = sanitizeGeneratedText(cleanGeneratedText(text), {
    maxLength: 180,
  });

  if (safety.blocked) {
    logGenerationEvent("content_safety_blocked", {
      ...context,
      reasons: safety.reasons,
      originalLength: safety.originalLength,
    });
    return "";
  }

  if (safety.sanitized) {
    logGenerationEvent("content_safety_sanitized", {
      ...context,
      reasons: safety.reasons,
      originalLength: safety.originalLength,
      finalLength: safety.finalLength,
    });
  }

  return safety.text;
}

function isLowSignalViewerComment(viewerComment: string): boolean {
  const normalized = viewerComment.trim().toLowerCase();
  if (normalized.length <= 4) {
    return true;
  }

  return [
    /^h+i+$/i,
    /^hello$/i,
    /^hey$/i,
    /^yo$/i,
    /^ok(ay)?$/i,
    /^cool$/i,
    /^nice$/i,
    /^wow$/i,
    /^lol$/i,
    /^哈+$/i,
    /^哈哈+$/i,
    /^嗯+$/i,
    /^哦+$/i,
    /^在吗$/i,
  ].some((pattern) => pattern.test(normalized));
}

function isLikelyEnglishText(text: string): boolean {
  const trimmed = text.trim();
  if (!trimmed) return false;
  if (/[\u4e00-\u9fff]/.test(trimmed)) return false;
  return /[a-z]/i.test(trimmed);
}

function modernReplyFallback(targetId: string, viewerComment: string): string {
  const lowSignal = isLowSignalViewerComment(viewerComment);
  const english = isLikelyEnglishText(viewerComment);

  switch (targetId) {
    case "musk":
      if (english) {
        return lowSignal
          ? "Just say what you want to say."
          : "I saw it. Say what you actually want to ask.";
      }
      return lowSignal ? "直接说重点。" : "我看到了，直接说你想追问哪一点。";
    case "trump":
      if (english) {
        return lowSignal
          ? "Say it clearly."
          : "I saw it. Say what you actually think.";
      }
      return lowSignal ? "直接说重点。" : "我看到了，直接说你的看法。";
    case "zuckerberg":
      if (english) {
        return lowSignal
          ? "Be a little more specific."
          : "I saw it. Be a little more specific.";
      }
      return lowSignal
        ? "说具体一点，我更容易接住。"
        : "我看到了，讲具体一点会更有讨论价值。";
    case "sam_altman":
      if (english) {
        return lowSignal
          ? "Give me the concrete version."
          : "I saw it. Give me the concrete version.";
      }
      return lowSignal
        ? "先说具体一点。"
        : "我看到了，你把最关键的那一层说具体一点。";
    case "zhang_peng":
      if (english) {
        return lowSignal
          ? "Give me the variable that matters."
          : "I saw it. Tell me which variable you care about.";
      }
      return lowSignal
        ? "先讲变量。"
        : "我看到了，你先说你最在意的是哪个变量。";
    case "lei_jun":
      if (english) {
        return lowSignal
          ? "Say the real product point."
          : "I saw it. Tell me the real product point.";
      }
      return lowSignal
        ? "直接说产品点。"
        : "我看到了，直接说你最关心的产品点。";
    case "liu_jingkang":
      if (english) {
        return lowSignal
          ? "What's the actual pain point?"
          : "I saw it. What's the actual pain point here?";
      }
      return lowSignal
        ? "痛点是什么？"
        : "我看到了，你直接说这里真正的痛点是什么。";
    case "luo_yonghao":
      if (english) {
        return lowSignal
          ? "Say it like a human."
          : "I saw it. Say it like a human.";
      }
      return lowSignal ? "说人话。" : "我看到了，你直接说人话，别绕。";
    case "justin_sun":
      if (english) {
        return lowSignal
          ? "What's the trade?"
          : "I saw it. Tell me the trade you are seeing.";
      }
      return lowSignal
        ? "你想表达什么交易判断？"
        : "我看到了，直接说你的交易判断。";
    case "kim_kardashian":
      if (english) {
        return lowSignal
          ? "Be specific."
          : "I saw it. Be specific about the signal.";
      }
      return lowSignal
        ? "具体一点。"
        : "我看到了，你具体说这对文化还是品牌意味着什么。";
    case "papi":
      if (english) {
        return lowSignal
          ? "Give me an actual scene."
          : "I saw it. Give me an actual scene, not just a label.";
      }
      return lowSignal
        ? "给我个具体场景。"
        : "我看到了，你先给我一个具体场景，不然太空了。";
    default:
      if (english) {
        return lowSignal
          ? "Say a little more."
          : "I saw it. Say what you want to discuss.";
      }
      return lowSignal
        ? "说具体一点，我直接回你。"
        : "我看到了，直接说你想讨论哪一点。";
  }
}

export function normalizeLegacyFallbackComment(
  authorId: string,
  content: string,
): string {
  const trimmed = content.trim();
  switch (authorId) {
    case "musk":
      if (trimmed === "政治也是现实的一部分。看现场就知道，大家会自己判断。") {
        return modernReplyFallback(authorId, "hi");
      }
      return trimmed;
    case "trump":
      if (trimmed === "当然是真心的。现场的能量非常强，很多人都看到了。") {
        return modernReplyFallback(authorId, "hi");
      }
      return trimmed;
    case "zuckerberg":
      if (trimmed === "这确实会被政治化，但现场反馈本身也是很真实的信号。") {
        return modernReplyFallback(authorId, "hi");
      }
      return trimmed;
    default:
      return trimmed;
  }
}

function templatedFallbackComment(
  targetId: string,
  authorDisplayName: string,
  viewerComment: string,
): string {
  if (viewerComment) {
    return modernReplyFallback(targetId, viewerComment);
  }

  switch (targetId) {
    case "musk":
      return `现场能量很强。${authorDisplayName}这条发得挺直接。`;
    case "trump":
      return "这场面很强，真的很强。大家能感觉到那股势头。";
    case "zuckerberg":
      return "这种现场号召力挺少见的，传播效果会很强。";
    case "sam_altman":
      return "这条信息密度很高，后续的产品影响可能比表面更大。";
    case "zhang_peng":
      return "这条像是一个更大周期里的前置信号。";
    case "lei_jun":
      return "这条不只是热度，背后一定有产品和交付层的东西。";
    case "liu_jingkang":
      return "这条我会先看它到底击中了哪个真实场景。";
    case "luo_yonghao":
      return "这条确实值得聊，不然太浪费表达欲了。";
    case "justin_sun":
      return "这条会影响市场情绪，节奏不会慢。";
    case "kim_kardashian":
      return "这条很像会继续外溢的文化信号。";
    case "papi":
      return "这条下面一定会有人有代入感。";
    default:
      return "这条会让人想留言。";
  }
}

export function safeInteractionFallbackComment(
  targetId: string,
  authorDisplayName: string,
  viewerComment: string,
  context: InteractionFallbackContext,
): string {
  const fallback = sanitizeInteractionText(
    templatedFallbackComment(targetId, authorDisplayName, viewerComment),
    {
      ...context,
      targetId,
      source: "fallback",
    },
  );

  if (fallback) {
    return fallback;
  }

  return genericInteractionFallback(targetId);
}
