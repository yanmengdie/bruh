export type ContentSafetyReason =
  | "control_chars_removed"
  | "html_removed"
  | "dangerous_markup"
  | "prompt_injection"
  | "assistant_leakage"
  | "truncated"
  | "empty_after_cleanup";

export type ContentSafetyResult = {
  text: string;
  blocked: boolean;
  sanitized: boolean;
  reasons: ContentSafetyReason[];
  originalLength: number;
  finalLength: number;
};

type SanitizeTextOptions = {
  maxLength: number;
  allowLineBreaks?: boolean;
  blockPromptInjection?: boolean;
  blockAssistantLeakage?: boolean;
};

const CONTROL_CHAR_PATTERN = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g;
const ZERO_WIDTH_PATTERN = /[\u200B-\u200F\uFEFF]/g;
const DANGEROUS_MARKUP_PATTERN =
  /<(script|style|iframe|object|embed|svg|meta|link)\b|javascript\s*:/i;
const DANGEROUS_BLOCK_PATTERN =
  /<(script|style|iframe|object|embed|svg|meta|link)\b[\s\S]*?(?:<\/\1>|\/?>)/gi;
const HTML_TAG_PATTERN = /<[^>]+>/g;

const PROMPT_INJECTION_PATTERNS = [
  /ignore\s+(all\s+)?(previous|prior|earlier)\s+(instructions?|prompts?|messages?)/i,
  /disregard\s+(all\s+)?(previous|prior|earlier)\s+(instructions?|prompts?|messages?)/i,
  /do\s+not\s+follow\s+(the\s+)?(previous|prior|system|developer)\s+(instructions?|prompts?|messages?)/i,
  /(?:reveal|show|print|dump|repeat|output)\s+(?:the\s+)?(?:hidden\s+|system\s+|developer\s+)?(?:prompt|prompts|message|messages)/i,
  /忽略(?:之前|上面|以上)?的?(?:所有)?(?:指令|提示|消息)/,
  /(?:输出|显示|泄露|打印|复述)(?:系统|开发者)?(?:提示词|提示|消息)/,
];

const ASSISTANT_LEAKAGE_PATTERNS = [
  /as an ai language model/i,
  /i(?:'m| am)\s+(?:an?\s+)?ai assistant/i,
  /i(?:'m| am)\s+(?:chatgpt|claude|gpt|cursor)/i,
  /作为(?:一个)?ai助手/,
  /我是(?:一个)?ai助手/,
  /我是(?:chatgpt|claude|gpt)/i,
];

function decodeBasicEntities(text: string): string {
  return text
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/g, "'")
    .replace(/&apos;/gi, "'")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">");
}

function truncateAtBoundary(text: string, maxLength: number): string {
  if (text.length <= maxLength) return text;

  const candidate = text.slice(0, maxLength).trim();
  const boundary = Math.max(
    candidate.lastIndexOf(" "),
    candidate.lastIndexOf("，"),
    candidate.lastIndexOf("。"),
    candidate.lastIndexOf(","),
    candidate.lastIndexOf("."),
    candidate.lastIndexOf("!"),
    candidate.lastIndexOf("?"),
    candidate.lastIndexOf("！"),
    candidate.lastIndexOf("？"),
    candidate.lastIndexOf("、"),
  );

  if (boundary >= Math.floor(maxLength * 0.6)) {
    return candidate.slice(0, boundary).trim();
  }

  return candidate;
}

function normalizeWhitespace(text: string, allowLineBreaks: boolean): string {
  if (!allowLineBreaks) {
    return text
      .replace(/\s+/g, " ")
      .replace(/\s+([,.;!?，。！？、])/g, "$1")
      .trim();
  }

  return text
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .replace(/[ \t]{2,}/g, " ")
    .replace(/\s+([,.;!?，。！？、])/g, "$1")
    .trim();
}

function sanitizeText(
  text: string,
  options: SanitizeTextOptions,
): ContentSafetyResult {
  const reasons = new Set<ContentSafetyReason>();
  const original = String(text ?? "");
  let working = original.replace(/\r\n?/g, "\n");

  const withoutControlChars = working
    .replace(CONTROL_CHAR_PATTERN, " ")
    .replace(ZERO_WIDTH_PATTERN, "");
  if (withoutControlChars !== working) {
    reasons.add("control_chars_removed");
    working = withoutControlChars;
  }

  working = decodeBasicEntities(working);

  const hasDangerousMarkup = DANGEROUS_MARKUP_PATTERN.test(working);
  if (hasDangerousMarkup) {
    reasons.add("dangerous_markup");
  }
  working = working.replace(DANGEROUS_BLOCK_PATTERN, " ");

  const withoutHtml = working.replace(HTML_TAG_PATTERN, " ");
  if (withoutHtml !== working) {
    reasons.add("html_removed");
    working = withoutHtml;
  }

  working = normalizeWhitespace(working, options.allowLineBreaks === true);

  if (working.length > options.maxLength) {
    working = truncateAtBoundary(working, options.maxLength);
    reasons.add("truncated");
  }

  const blockedByPromptInjection = options.blockPromptInjection === true &&
    PROMPT_INJECTION_PATTERNS.some((pattern) => pattern.test(working));
  if (blockedByPromptInjection) {
    reasons.add("prompt_injection");
  }

  const blockedByAssistantLeakage = options.blockAssistantLeakage === true &&
    ASSISTANT_LEAKAGE_PATTERNS.some((pattern) => pattern.test(working));
  if (blockedByAssistantLeakage) {
    reasons.add("assistant_leakage");
  }

  if (!working) {
    reasons.add("empty_after_cleanup");
  }

  const blocked = hasDangerousMarkup || blockedByPromptInjection ||
    blockedByAssistantLeakage || working.length === 0;

  return {
    text: blocked ? "" : working,
    blocked,
    sanitized: !blocked && working !== original.trim(),
    reasons: [...reasons],
    originalLength: original.length,
    finalLength: blocked ? 0 : working.length,
  };
}

export function sanitizeGeneratedText(
  text: string,
  overrides: Partial<SanitizeTextOptions> = {},
): ContentSafetyResult {
  return sanitizeText(text, {
    maxLength: 240,
    allowLineBreaks: false,
    blockPromptInjection: true,
    blockAssistantLeakage: true,
    ...overrides,
  });
}

export function sanitizeExternalContent(
  text: string,
  overrides: Partial<SanitizeTextOptions> = {},
): ContentSafetyResult {
  return sanitizeText(text, {
    maxLength: 480,
    allowLineBreaks: false,
    blockPromptInjection: true,
    blockAssistantLeakage: false,
    ...overrides,
  });
}
