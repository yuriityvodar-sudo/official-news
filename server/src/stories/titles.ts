// A story's headline in the reader's language (#230, the aggregator step 3):
// one Workers AI call writes it in English and every language of LANGS at
// once, from the outlets' own headlines, for the stories the app shows first.
// Kept per story (`story_titles`, migration 0030), so a story is written once.
// Tried on 19 stories of 1 Nov: 6.7 neurons a call, so about 2,300 a day for
// the 350 or so stories that reach a country's first places.
import type { Env } from "../env";
import { MODEL } from "../summarizer";
import { LANGS, LANGUAGES, type Lang, OTHER_LETTERS, OTHER_WORDS } from "../translator/languages";
import { NAME_PARTICLES } from "../translator/words";
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

// The check reads a headline's letters by their codes. The translator's check
// (inLanguage) does it with Unicode regexes, whose compiling took 9 ms of the
// first answer's check in a call that starts cold (2 Nov), most of a build's
// 10 ms; it is the same check, for one sentence.
const isLatin = (c: number) => (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 0xc0 && c <= 0x24f && c !== 0xd7 && c !== 0xf7);
const isCyrillic = (c: number) => c >= 0x400 && c <= 0x4ff;
const isLetter = (c: number) => isLatin(c) || isCyrillic(c) || (c >= 0x370 && c <= 0x3ff);
const isDigit = (c: number) => c >= 48 && c <= 57;
const isCapital = (word: string) => word[0] !== word[0].toLowerCase();
const isAcronym = (word: string) => word.length > 1 && word === word.toUpperCase() && word !== word.toLowerCase();

/** A headline's words: its runs of letters. */
function wordsOf(text: string): string[] {
  const words: string[] = [];
  let start = -1;
  for (let i = 0; i <= text.length; i++) {
    const letter = i < text.length && isLetter(text.charCodeAt(i));
    if (letter && start < 0) start = i;
    else if (!letter && start >= 0) {
      words.push(text.slice(start, i));
      start = -1;
    }
  }
  return words;
}

/**
 * A Latin word in lower case, of letters and digits joined by an apostrophe or
 * a hyphen: in Ukrainian or Russian, a word left untranslated. Names, acronyms
 * and brands have a capital (Binance, IG Metall, KT-1).
 */
function latinLowerWord(text: string): boolean {
  let latin = false;
  let capital = false;
  let letter = false;
  for (let i = 0; i <= text.length; i++) {
    const c = i < text.length ? text.charCodeAt(i) : 32;
    const joins = (c === 39 || c === 0x2019 || c === 45) && i + 1 < text.length && (isLetter(text.charCodeAt(i + 1)) || isDigit(text.charCodeAt(i + 1)));
    if (isLetter(c) || isDigit(c) || (joins && (letter || latin || capital || isDigit(text.charCodeAt(i - 1))))) {
      if (isLatin(c)) latin = true;
      if (isLetter(c)) {
        letter = true;
        const ch = text[i];
        if (ch !== ch.toLowerCase()) capital = true;
      }
      continue;
    }
    if (latin && letter && !capital) return true;
    latin = capital = letter = false;
  }
  return false;
}

/** Ukrainian or Russian: Cyrillic, none of the other one's letters or words, and in a long one its own letters. */
function inCyrillic(text: string, lang: "uk" | "ru"): boolean {
  let cyrillic = 0;
  for (let i = 0; i < text.length; i++) if (isCyrillic(text.charCodeAt(i))) cyrillic++;
  if (!cyrillic) return false;
  const lower = text.toLowerCase();
  for (const letter of OTHER_LETTERS[lang]) if (lower.includes(letter)) return false;
  for (const word of wordsOf(lower)) {
    for (const other of OTHER_WORDS[lang]) if (other.endsWith("*") ? word.startsWith(other.slice(0, -1)) : word === other) return false;
  }
  // As the translator asks of a field of 100 letters or more (OWN_LETTERS_FROM).
  return lang !== "uk" || cyrillic < 100 || /[іїєґ]/.test(lower);
}

/**
 * Spanish or German: Latin letters, not the English unchanged, and no more
 * function words of English or of the other language than of its own, as the
 * translator counts them (prompt.ts, functionWords): one inside a name does not
 * count, nor an acronym.
 */
function inLatin(text: string, english: string, lang: "es" | "de"): boolean {
  let latin = false;
  for (let i = 0; i < text.length && !latin; i++) latin = isLatin(text.charCodeAt(i));
  if (!latin) return false;
  const tokens = wordsOf(text);
  const plain = (s: string) => s.toLowerCase().replace(/\s+/g, " ").trim().replace(/\.$/, "");
  if (tokens.length >= 3 && plain(text) === plain(english)) return false;
  const stopWords = LANGUAGES[lang].stopWords!;
  const capitalNext = (i: number, step: 1 | -1, skip: number): boolean => {
    const next = tokens[i + step];
    if (next === undefined) return false;
    if (isCapital(next)) return true;
    return skip > 0 && NAME_PARTICLES.has(next) && capitalNext(i + step, step, skip - 1);
  };
  let own = 0;
  const foreign = [0, 0];
  tokens.forEach((token, i) => {
    if (isAcronym(token)) return;
    const word = token.toLowerCase();
    if (stopWords.own.has(word)) {
      own++;
      return;
    }
    const j = stopWords.english.has(word) ? 0 : stopWords.other.has(word) ? 1 : -1;
    if (j < 0) return;
    const skip = NAME_PARTICLES.has(token) ? 1 : 0;
    const inName = isCapital(token) ? i > 0 || (j === 1 && capitalNext(i, 1, 1)) : capitalNext(i, -1, skip) && capitalNext(i, 1, skip);
    if (!inName) foreign[j]++;
  });
  return foreign.every((n) => n <= own) && (tokens.length < 8 || own > 0);
}

/**
 * Checks the model's answer: JSON with all five headlines, none empty or
 * longer than TITLES.maxLength, each in its language (inCyrillic, inLatin: the
 * translator's check for one sentence), and in Ukrainian and Russian no Latin
 * word in lower case: the trial's one slip ("медіа sharply розділяє") passed
 * the translator's check, which lets a few English letters through in a long
 * text. The titles, or why not.
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
    else if (!inItsLanguage(text, String((parsed as Record<string, unknown>).en ?? ""), lang)) problems.push(`${lang} is not in its language`);
    else if ((lang === "uk" || lang === "ru") && latinLowerWord(text)) problems.push(`${lang} has a word in Latin letters`);
    titles[lang] = text;
  }
  return problems.length ? { problems } : titles;
}

function inItsLanguage(text: string, english: string, lang: TitleLang): boolean {
  if (lang === "uk" || lang === "ru") return inCyrillic(text, lang);
  if (lang === "es" || lang === "de") return inLatin(text, english, lang);
  for (let i = 0; i < text.length; i++) if (isLatin(text.charCodeAt(i))) return true;
  return false;
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
