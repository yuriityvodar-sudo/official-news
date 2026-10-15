// The AI providers a translation can come from (#46). A provider is named
// "<kind>:<model>", e.g. "groq:qwen/qwen3.8-27b" or "zai:glm-4.5-flash"; the
// order to try them in is TRANSLATORS in ./index.ts.
import type { Env } from "../env";

/** The provider could not answer: rate limit or quota, an outage, a network error. Not the article's fault. */
export class ProviderDown extends Error {}

/** The provider answered, but not with something we can store. Counts as a failed attempt. */
export class UnusableAnswer extends Error {}

export type Messages = { role: "system" | "user"; content: string }[];

export interface Provider {
  /** As written in TRANSLATORS; stored in `article_translations.model`. */
  name: string;
  /** One call; returns the answer's text, or the object when the provider already parsed the JSON. */
  translate(messages: Messages): Promise<unknown>;
}

/**
 * A translation is about 250 to 320 output tokens (docs/research/2026-10-15
 * Translation model test.md); a longer answer is cut off and counts an attempt.
 * Groq counts the requested max_tokens, not the tokens used, against Qwen's free
 * 1,000 output tokens a minute, so a lower limit leaves room for the next
 * request sooner (#46).
 */
const MAX_TOKENS = 700;
const TEMPERATURE = 0.2;
/** A request that takes longer is treated as an outage, so a run never hangs on one provider. */
const TIMEOUT_MS = 30_000;
/**
 * Z.ai's free GLM models are slower: in the 15 Oct test glm-4.5-flash took
 * about 10 s per language, glm-4.7-flash about 19 s (docs/research/2026-10-15
 * Translation model test.md).
 */
const ZAI_TIMEOUT_MS = 60_000;

export const GROQ_URL = "https://api.groq.com/openai/v1/chat/completions";
export const ZAI_URL = "https://api.z.ai/api/paas/v4/chat/completions";

const errorText = (error: unknown) => (error instanceof Error ? error.message : String(error));

/** The parts of an OpenAI-style chat answer we read (Groq, Z.ai, and Workers AI chat models). */
interface ChatAnswer {
  choices?: { message?: { content?: unknown }; finish_reason?: string }[];
  response?: unknown;
  error?: { code?: string | number; type?: string; message?: string };
}

function content(answer: ChatAnswer): unknown {
  const choice = answer.choices?.[0];
  if (choice?.finish_reason === "length") throw new UnusableAnswer("the answer was cut off at the token limit");
  // Z.ai stops an answer its content filter blocks with "sensitive".
  if (choice?.finish_reason === "sensitive") throw new UnusableAnswer("content filter");
  if (choice?.finish_reason === "network_error") throw new ProviderDown("the answer stopped with a network error");
  const text = choice?.message?.content ?? answer.response;
  if (text === undefined || text === null || (typeof text === "string" && !text.trim())) {
    throw new UnusableAnswer("the answer was empty");
  }
  return text;
}

/** Thinking off: a translation needs none, and it would use most of the token limit. */
function reasoningEffort(model: string): string | undefined {
  if (model.includes("gpt-oss")) return "low"; // gpt-oss cannot turn it off
  if (model.startsWith("qwen/")) return "none";
  return undefined;
}

function groq(model: string, key: string, fetch: typeof globalThis.fetch): Provider {
  return {
    name: `groq:${model}`,
    async translate(messages) {
      const effort = reasoningEffort(model);
      let response: Response;
      try {
        response = await fetch(GROQ_URL, {
          method: "POST",
          headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
          body: JSON.stringify({
            model,
            messages,
            response_format: { type: "json_object" },
            temperature: TEMPERATURE,
            max_tokens: MAX_TOKENS,
            ...(effort ? { reasoning_effort: effort } : {}),
          }),
          signal: AbortSignal.timeout(TIMEOUT_MS),
        });
      } catch (error) {
        throw new ProviderDown(`request failed: ${errorText(error)}`);
      }
      const body = (await response.json().catch(() => null)) as ChatAnswer | null;
      if (!response.ok) {
        const code = body?.error?.code;
        // Groq checks JSON mode itself and answers 400 when the model's text is not JSON.
        if (response.status === 400 && code === "json_validate_failed") throw new UnusableAnswer("the answer is not valid JSON");
        // 429 (rate limit or the day's free requests used up), 5xx, and also a bad key or model: none is the article's fault.
        throw new ProviderDown(`HTTP ${response.status}${code ? ` ${code}` : ""}`);
      }
      if (!body) throw new ProviderDown("the response is not JSON");
      return content(body);
    },
  };
}

/**
 * Z.ai error codes (`error.code`) that are its content filter: the article's
 * text, so an attempt. Every other error is the provider's: 1302 (too many
 * requests at once: the free plan allows about one), 1305 (overloaded), 1234
 * (network), HTTP 429 and 5xx, and also a bad key or model.
 */
const ZAI_CONTENT_FILTER = new Set(["1301"]);

/**
 * Z.ai's OpenAI-compatible chat API (#46), for Spanish and German. Thinking
 * off, JSON mode. Its free plan allows about one request at a time, and a run
 * makes its requests one after another, so it never sends two.
 */
function zai(model: string, key: string, fetch: typeof globalThis.fetch): Provider {
  return {
    name: `zai:${model}`,
    async translate(messages) {
      let response: Response;
      try {
        response = await fetch(ZAI_URL, {
          method: "POST",
          headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
          body: JSON.stringify({
            model,
            messages,
            thinking: { type: "disabled" },
            response_format: { type: "json_object" },
            temperature: TEMPERATURE,
            max_tokens: MAX_TOKENS,
          }),
          signal: AbortSignal.timeout(ZAI_TIMEOUT_MS),
        });
      } catch (error) {
        throw new ProviderDown(`request failed: ${errorText(error)}`);
      }
      const body = (await response.json().catch(() => null)) as ChatAnswer | null;
      const code = body?.error?.code === undefined ? undefined : String(body.error.code);
      if (code && ZAI_CONTENT_FILTER.has(code)) throw new UnusableAnswer("content filter");
      if (!response.ok || (code && !body?.choices?.length)) {
        throw new ProviderDown(`HTTP ${response.status}${code ? ` ${code}` : ""}`);
      }
      if (!body) throw new ProviderDown("the response is not JSON");
      return content(body);
    },
  };
}

function workersAi(model: string, env: Env): Provider {
  return {
    name: `workers-ai:${model}`,
    async translate(messages) {
      let output: Record<string, unknown>;
      try {
        output = await env.AI.run(model, {
          messages,
          response_format: { type: "json_object" },
          chat_template_kwargs: { enable_thinking: false },
          max_tokens: MAX_TOKENS,
          temperature: TEMPERATURE,
        });
      } catch (error) {
        // An outage, capacity, or the day's free Neurons used up.
        throw new ProviderDown(errorText(error));
      }
      return content(output as ChatAnswer);
    },
  };
}

/**
 * The provider for one TRANSLATORS entry, or null when it cannot run here
 * (Groq without its `GROQ_API_KEY` secret, Z.ai without `ZAI_API_KEY`): its
 * languages then wait in the queue. An unknown kind is a typo in TRANSLATORS
 * and fails the run, so it shows in the logs at once.
 */
export function providerFor(spec: string, env: Env, fetch: typeof globalThis.fetch): Provider | null {
  const colon = spec.indexOf(":");
  const kind = spec.slice(0, colon);
  const model = spec.slice(colon + 1);
  if (colon > 0 && model) {
    if (kind === "groq") return env.GROQ_API_KEY ? groq(model, env.GROQ_API_KEY, fetch) : null;
    if (kind === "zai") return env.ZAI_API_KEY ? zai(model, env.ZAI_API_KEY, fetch) : null;
    if (kind === "workers-ai") return workersAi(model, env);
  }
  throw new Error(`unknown translator "${spec}": use groq:<model>, zai:<model> or workers-ai:<model>`);
}
