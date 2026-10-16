// Checks on a summary before it is stored (#63): the model may not add a number
// the article does not give, nor words of purpose, prediction or judgement the
// style guide rules out. They catch what the prompt alone did not stop in the
// 16 Oct test: "2,500MW" for a notice that held only a title, "2036" for 2026.
import type { Summary } from "./schema";

/**
 * Words that add a purpose, a prediction or a judgement the article did not state
 * (docs/style-guide.md, rule 1). "The ministry says the goal is …" is the allowed form.
 * "may" is not here: "providers may now sell the devices" is a permission the
 * decision grants, which the impact part asks for.
 */
const BANNED = /\b(aims? to|seeks? to|(?:is|are) intended to|(?:is|are) expected to|could|might|significant(?:ly)?|routine|first step|landmark|historic)\b/gi;

/** Numbers as written, without thousands separators: "2,500" and "2 500" are "2500". */
function numbers(text: string): string[] {
  return (text.match(/\d{1,3}(?:[   ]\d{3})+(?![\d])|\d+(?:[.,]\d+)*/g) ?? []).map((n) => n.replace(/[.,\s  ]/g, ""));
}

/**
 * Common English words. They are at least 18% of the words of every English
 * summary in the 16 Oct test, and 0 to 2% of the 7 of 293 stored summaries the
 * old model wrote in the article's own language (German, Portuguese,
 * Indonesian, Turkish), which the app then labelled "translated from".
 */
const ENGLISH = new Set(
  "the of and to in for on with is are was were by from an that this will at as it its be has have not which their or after under new".split(" "),
);

/** Below this share of ENGLISH words, a summary is not in English. */
const MIN_ENGLISH_SHARE = 0.1;

/** Too few words to tell the language by its common words. */
const MIN_WORDS = 20;

function notEnglish(text: string): boolean {
  const words = text.toLowerCase().match(/\p{L}+/gu) ?? [];
  if (words.length < MIN_WORDS) return false;
  return words.filter((w) => ENGLISH.has(w)).length / words.length < MIN_ENGLISH_SHARE;
}

/** Every text of a summary that readers see. */
function shown(s: Summary): string {
  const i = s.impact;
  return [s.headline, s.shortSummary, s.summary, i?.general, i?.residents, i?.abroad, ...(i?.byTopic ?? []).map((t) => t.text)]
    .filter(Boolean)
    .join("\n");
}

export interface CheckResult {
  /** Numbers of two digits or more that are not in the article (its title and text). */
  invented: string[];
  /** Ruled-out words found, lower case. */
  banned: string[];
  /** Written in another language, often the article's own. */
  notEnglish: boolean;
}

/**
 * `source` is what the model read: the original title and text. `year` is the
 * year the article was fetched: a date in a calendar of its own (令和8年 is 2026)
 * comes out as that year, or the one before or after.
 */
export function checkSummary(s: Summary, source: string, year: number): CheckResult {
  const known = new Set(numbers(source));
  for (const y of [year - 1, year, year + 1]) known.add(String(y));
  const text = shown(s);
  const invented = [...new Set(numbers(text).filter((n) => n.length >= 2 && !known.has(n)))];
  const banned = [...new Set((text.match(BANNED) ?? []).map((w) => w.toLowerCase()))];
  return { invented, banned, notEnglish: notEnglish(text) };
}
