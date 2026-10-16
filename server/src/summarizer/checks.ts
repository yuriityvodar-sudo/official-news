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
  return { invented, banned };
}
