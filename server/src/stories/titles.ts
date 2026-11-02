// A story's headline in the reader's language (#230, the aggregator step 3):
// one Workers AI call writes it in English and every language of LANGS at
// once, from the outlets' own headlines, for the stories the app shows first.
// Kept per story (`story_titles`, migration 0030), so a story is written once.
// Tried on 19 stories of 1 Nov: 6.7 neurons a call, so about 2,300 a day for
// the 350 or so stories that reach a country's first places.
import type { Env } from "../env";
import { MODEL } from "../summarizer";
import { LANGS, LANGUAGES, type Lang } from "../translator/languages";
import { inLanguage } from "../translator/prompt";
import type { Story } from "./cluster";

export const TITLES = {
  /** A country's weightiest stories carried by this many outlets or more get a headline... */
  minOutlets: 2,
  /** ...this many of them, the ones the app shows. */
  perCountry: 6,
  /** Calls a country's build makes at most: a few seconds each. */
  perBuild: 2,
  /** A story is asked at most this many times; then it keeps its outlets' headline. */
  maxAttempts: 3,
  /** A headline is at most this long in any language (the prompt asks for 90). */
  maxLength: 120,
} as const;

export type TitleLang = "en" | Lang;
export type Titles = Record<TitleLang, string>;
export const TITLE_LANGS: readonly TitleLang[] = ["en", ...LANGS];

/** The system prompt: what the trial of 1 Nov settled (handoff/aggregator/titles-trial.mjs). */
export const TITLES_PROMPT = `You write the headline of one news story for a news app, from the headlines that news outlets gave it.

The user message gives the country of the outlets and, one per line, each outlet's headline on the story, in the outlets' language. They report the same event.

Write one headline that says what happened, in each of five languages: English (en), Ukrainian (uk), Russian (ru), Spanish (es) and German (de). The five say the same thing.

- Only what the outlets' headlines say and agree on. Nothing of your own: no opinion, no cause or consequence they do not give, no guess.
- No outlet's name, and no quote of one outlet's words.
- At most 90 characters in each language: one sentence, no full stop at the end.
- People's and places' names as each language usually writes them: in Ukrainian and Russian in Cyrillic letters, except brands and bodies always written in Latin ones (Binance, IG Metall).
- Every word in its language: nothing left in the outlets' language or in English.
- Plain words, as a news agency writes: no question, no exclamation, nothing to excite.`;

export const TITLES_SCHEMA = {
  type: "object",
  properties: Object.fromEntries(TITLE_LANGS.map((lang) => [lang, { type: "string" }])),
  required: [...TITLE_LANGS],
  additionalProperties: false,
};

/** The user message: the outlets' country and each outlet's headline on the story. */
export const titlesMessage = (country: string, story: Story): string =>
  `Country: ${country}.\n${story.items.map((item) => `- ${item.outlet.name}: ${item.title}`).join("\n")}`;

/** A Latin word in lower case: in Ukrainian or Russian, a word left untranslated. Names, acronyms and brands have a capital (Binance, IG Metall, KT-1). */
const latinLowerWord = (text: string) => (text.match(/[\p{L}\d]+(?:['’-][\p{L}\d]+)*/gu) ?? []).some((w) => /\p{Script=Latin}/u.test(w) && w === w.toLowerCase() && /\p{L}/u.test(w));

/**
 * Checks the model's answer: JSON with all five headlines, none empty or
 * longer than TITLES.maxLength, each in its language (the translator's
 * inLanguage), and in Ukrainian and Russian no Latin word in lower case: the
 * trial's one slip ("медіа sharply розділяє") passed inLanguage, which lets a
 * few English letters through in a long text. The titles, or why not.
 */
export function toTitles(answer: string): Titles | { problems: string[] } {
  let parsed: unknown;
  try {
    parsed = JSON.parse(answer);
  } catch {
    return { problems: ["not JSON"] };
  }
  const problems: string[] = [];
  const titles = {} as Titles;
  for (const lang of TITLE_LANGS) {
    const value = (parsed as Record<string, unknown> | null)?.[lang];
    const text = typeof value === "string" ? value.replace(/\s+/g, " ").trim().replace(/\.$/, "") : "";
    if (!text) problems.push(`${lang} is missing`);
    else if (text.length > TITLES.maxLength) problems.push(`${lang} is longer than ${TITLES.maxLength} characters`);
    else if (lang === "en" ? !/\p{Script=Latin}/u.test(text) : !inLanguage(text, String((parsed as Record<string, unknown>).en ?? ""), LANGUAGES[lang])) {
      problems.push(`${lang} is not in its language`);
    } else if ((lang === "uk" || lang === "ru") && latinLowerWord(text)) problems.push(`${lang} has a word in Latin letters`);
    titles[lang] = text;
  }
  return problems.length ? { problems } : titles;
}

/** The model's answer to one story; tests pass their own. */
export type WriteTitles = (country: string, story: Story) => Promise<string>;

export function workersAiTitles(env: Env): WriteTitles {
  return async (country, story) => {
    const output = await env.AI.run(MODEL, {
      messages: [
        { role: "system", content: TITLES_PROMPT },
        { role: "user", content: titlesMessage(country, story) },
      ],
      response_format: { type: "json_schema", json_schema: { name: "story_titles", schema: TITLES_SCHEMA, strict: true } },
      chat_template_kwargs: { enable_thinking: false },
      max_completion_tokens: 600,
      temperature: 0.2,
    });
    const content = output.choices[0]?.message?.content;
    return typeof content === "string" ? content : "";
  };
}

/**
 * The headlines of `stories` (a country's, weightiest first): those stored,
 * and for at most TITLES.perBuild of the first TITLES.perCountry with
 * TITLES.minOutlets outlets that have none yet, the model's, stored at once.
 * An unusable answer counts an attempt; an error of Workers AI itself (its
 * free allocation used up, an outage) counts none and asks no more this time.
 */
export async function storyTitles(env: Env, country: string, stories: Story[], write: WriteTitles = workersAiTitles(env), now = new Date()): Promise<Map<string, Titles>> {
  const wanted = stories.filter((s) => s.items.length >= TITLES.minOutlets).slice(0, TITLES.perCountry);
  const titles = new Map<string, Titles>();
  if (!wanted.length) return titles;
  const { results } = await env.DB.prepare(
    `SELECT story_id, titles, attempts FROM story_titles WHERE story_id IN (${wanted.map(() => "?").join(", ")})`,
  )
    .bind(...wanted.map((s) => s.id))
    .all<{ story_id: string; titles: string | null; attempts: number }>();
  const stored = new Map(results.map((r) => [r.story_id, r]));
  for (const r of results) if (r.titles) titles.set(r.story_id, JSON.parse(r.titles) as Titles);

  const due = wanted.filter((s) => !titles.has(s.id) && (stored.get(s.id)?.attempts ?? 0) < TITLES.maxAttempts).slice(0, TITLES.perBuild);
  const answers = await Promise.allSettled(due.map((story) => write(country, story)));
  const at = `${now.toISOString().slice(0, 19)}Z`;
  const writes: D1PreparedStatement[] = [];
  answers.forEach((answer, i) => {
    // Workers AI's own error: nobody's fault, nothing counted.
    if (answer.status === "rejected") return;
    const checked = toTitles(answer.value);
    const story = due[i];
    if ("problems" in checked) console.warn(JSON.stringify({ message: "story titles unusable", country, storyId: story.id, problems: checked.problems }));
    else titles.set(story.id, checked);
    writes.push(
      env.DB.prepare(
        `INSERT INTO story_titles (story_id, country, titles, attempts, updated_at) VALUES (?1, ?2, ?3, 1, ?4)
         ON CONFLICT (story_id) DO UPDATE SET titles = excluded.titles, attempts = story_titles.attempts + 1, updated_at = excluded.updated_at`,
      ).bind(story.id, country, "problems" in checked ? null : JSON.stringify(checked), at),
    );
  });
  if (writes.length) await env.DB.batch(writes);
  const failed = answers.filter((a) => a.status === "rejected").length;
  if (failed) console.error(JSON.stringify({ message: "story titles error", country, failed, error: String((answers.find((a) => a.status === "rejected") as PromiseRejectedResult).reason) }));
  return titles;
}
