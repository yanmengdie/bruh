import {
  cleanGeneratedText,
  normalizeLegacyFallbackComment,
  safeInteractionFallbackComment,
} from "./fallbacks.ts";

Deno.test("cleanGeneratedText removes assistant leakage lines", () => {
  const cleaned = cleanGeneratedText("I'm an AI assistant.\nHello there.");

  if (cleaned !== "Hello there.") {
    throw new Error(`expected cleaned text, got ${cleaned}`);
  }
});

Deno.test("normalizeLegacyFallbackComment upgrades known legacy replies", () => {
  const normalized = normalizeLegacyFallbackComment(
    "trump",
    "当然是真心的。现场的能量非常强，很多人都看到了。",
  );

  if (normalized !== "Say it clearly.") {
    throw new Error(`expected normalized legacy fallback, got ${normalized}`);
  }
});

Deno.test("safeInteractionFallbackComment returns deterministic low-signal reply", () => {
  const fallback = safeInteractionFallbackComment(
    "sam_altman",
    "Sam Altman",
    "hi",
    {
      postId: "post-1",
      personaId: "sam_altman",
      mode: "reply",
    },
  );

  if (fallback !== "Give me the concrete version.") {
    throw new Error(`expected sam fallback reply, got ${fallback}`);
  }
});
