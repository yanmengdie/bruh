import {
  extractOpenAICompatibleError,
  extractOpenAICompatibleContent,
  isTerminalOpenAICompatibleError,
} from "./openai_compatible.ts";

Deno.test("extractOpenAICompatibleContent reads chat completion string content", () => {
  const content = extractOpenAICompatibleContent({
    choices: [{ message: { content: "hello world" } }],
  });

  if (content !== "hello world") {
    throw new Error(`Unexpected content: ${content}`);
  }
});

Deno.test("extractOpenAICompatibleContent reads responses output_text blocks", () => {
  const content = extractOpenAICompatibleContent({
    output: [
      {
        content: [
          { type: "output_text", text: "first line" },
          { type: "output_text", text: "second line" },
        ],
      },
    ],
  });

  if (content !== "first line\nsecond line") {
    throw new Error(`Unexpected responses content: ${content}`);
  }
});

Deno.test("extractOpenAICompatibleContent reads nested text value objects", () => {
  const content = extractOpenAICompatibleContent({
    choices: [{
      message: {
        content: [{ type: "text", text: { value: "nested text" } }],
      },
    }],
  });

  if (content !== "nested text") {
    throw new Error(`Unexpected nested content: ${content}`);
  }
});

Deno.test("extractOpenAICompatibleContent ignores reasoning-only payloads", () => {
  const content = extractOpenAICompatibleContent({
    choices: [{
      message: {
        reasoning_content: "hidden chain of thought",
      },
    }],
  });

  if (content !== "") {
    throw new Error(`Expected empty content, got: ${content}`);
  }
});

Deno.test("extractOpenAICompatibleContent unwraps object body wrappers", () => {
  const content = extractOpenAICompatibleContent({
    status: 200,
    msg: "ok",
    body: {
      choices: [{ message: { content: "wrapped content" } }],
    },
  });

  if (content !== "wrapped content") {
    throw new Error(`Unexpected wrapped content: ${content}`);
  }
});

Deno.test("extractOpenAICompatibleContent unwraps stringified body wrappers", () => {
  const content = extractOpenAICompatibleContent({
    status: 200,
    msg: "ok",
    body: JSON.stringify({
      choices: [{ message: { content: "string body content" } }],
    }),
  });

  if (content !== "string body content") {
    throw new Error(`Unexpected string body content: ${content}`);
  }
});

Deno.test("extractOpenAICompatibleContent unwraps result and data wrappers", () => {
  const content = extractOpenAICompatibleContent({
    result: {
      data: {
        output: [{
          content: [{ type: "output_text", text: "nested wrapper content" }],
        }],
      },
    },
  });

  if (content !== "nested wrapper content") {
    throw new Error(`Unexpected nested wrapper content: ${content}`);
  }
});

Deno.test("extractOpenAICompatibleError reads wrapped provider status errors", () => {
  const error = extractOpenAICompatibleError({
    status: 439,
    msg:
      "Your API Token has expired. API Tokens have a validity period of 7 days.",
    body: null,
  });

  if (
    error !==
      "OpenAI-compatible provider returned status 439: Your API Token has expired. API Tokens have a validity period of 7 days."
  ) {
    throw new Error(`Unexpected provider error: ${error}`);
  }
});

Deno.test("isTerminalOpenAICompatibleError recognizes expired-token failures", () => {
  const terminal = isTerminalOpenAICompatibleError(
    new Error("OpenAI-compatible provider returned status 439: Your API Token has expired."),
  );

  if (!terminal) {
    throw new Error("Expected expired-token error to be terminal");
  }
});
