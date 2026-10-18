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
 * Dates written 13.10.2026, 13/10/2026 or 2026.10.19: their day and month count
 * too, as a summary writes "13 October 2026" (#91 review: every Polish cabinet
 * article dates itself this way). Only date-shaped tokens are split, so "521"
 * from "13.521.937" still counts as invented.
 */
const DATES = [/(?<!\d)(\d{1,2})[./](\d{1,2})[./](\d{4}|\d{2})(?!\d)/g, /(?<!\d)(\d{4})\.\s?(\d{1,2})\.\s?(\d{1,2})(?!\d)/g];

/** A number followed by a scale word ("5 tys. zł", "1천", "3 mln"): its full value counts too. */
const N = String.raw`(\d+(?:[.,]\d+)?)\s?`;
const SCALES: [RegExp, number][] = [
  [new RegExp(N + "(?:tys\\.|tysięcy|thousand|bin\\b|천|千)", "gi"), 1e3],
  [new RegExp(N + "(?:万|만)", "g"), 1e4],
  [new RegExp(N + "(?:mln|million|milyon|millones|millón|milhões)", "gi"), 1e6],
  [new RegExp(N + "(?:億|억)", "g"), 1e8],
  [new RegExp(N + "(?:mld|mrd|billion|milyar|miliard)", "gi"), 1e9],
];

/** The numbers a summary may use: the source's, also as dates, scaled amounts and year ranges ("2026-2027" as "2026-27"). */
function knownNumbers(source: string, year: number): Set<string> {
  const known = new Set(numbers(source));
  for (const re of DATES) {
    for (const m of source.matchAll(re)) {
      for (const part of m.slice(1)) known.add(part).add(String(Number(part)));
    }
  }
  for (const [re, scale] of SCALES) {
    for (const m of source.matchAll(re)) known.add(String(Math.round(parseFloat(m[1].replace(",", ".")) * scale)));
  }
  for (const m of source.matchAll(/(?<!\d)(\d{2})(\d{2})\s?[-–]\s?\1(\d{2})(?!\d)/g)) known.add(m[3]);
  // Names like Korea's "5·18" (18 May), which a summary may write "5.18". Korean texts also
  // write the dot as ㆍ (U+318D, which NFKC turns into U+119E), Japanese ones as ・.
  for (const m of source.matchAll(/(?<!\d)(\d{1,2})[·ᆞ・‧∙](\d{1,2})(?!\d)/g)) known.add(m[1] + m[2]);
  for (const y of [year - 1, year, year + 1]) known.add(String(y));
  return known;
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

/**
 * Common words of the other languages our sources write in, none of them
 * English. A list of names has few English words too (8 Korean vice
 * ministers: 9%), so few English words count as another language only with
 * signs of one (#91 review).
 */
const OTHER = new Set(
  [
    "der die das und den dem des ist mit für von zu auf sich im wird werden eine einen nicht", // de
    "em para com uma um os não pelo pela ao à", // pt (not da, dos: names have them)
    "el los las en con por una que se al", // es (not del, la, y)
    "il di che della delle dei gli nel alla sono", // it
    "le les des du et est pour dans une sur aux", // fr
    "dan yang untuk dengan dari ini itu pada akan dalam oleh", // id
    "ve bir bu ile için olarak daha", // tr
    "w z na się że nie od przez dla jest oraz", // pl
    "je pro se že", // cs
    "het een op voor zijn", // nl (not van)
  ]
    .join(" ")
    .split(" "),
);

/** An own name kept in its language, in double or angle quotes (prompt rule 5). */
const QUOTED = /["“”„«»][^"“”„«»\n]{1,160}["“”„«»]/g;

/** Letters of a script other than Latin: Japanese and Chinese have too few spaces to count words. */
const NON_LATIN = /[^\P{L}\p{Script=Latin}]/gu;

function notEnglish(text: string): boolean {
  const letters = text.match(/\p{L}/gu)?.length ?? 0;
  if (letters >= 40 && (text.match(NON_LATIN)?.length ?? 0) / letters > 0.3) return true;
  const words = text.toLowerCase().match(/\p{L}+/gu) ?? [];
  if (words.length < MIN_WORDS) return false;
  const english = words.filter((w) => ENGLISH.has(w)).length;
  if (english / words.length >= MIN_ENGLISH_SHARE) return false;
  // Few English words: another language only when its own common words show,
  // or when the lower-case words (names and quoted own names left out) are not English either.
  const rest = text.replace(QUOTED, " ").match(/\p{L}+/gu) ?? [];
  if (rest.filter((w) => OTHER.has(w.toLowerCase())).length > english) return true;
  const lower = rest.filter((w) => /^\p{Ll}/u.test(w));
  return lower.length >= 10 && lower.filter((w) => ENGLISH.has(w)).length / lower.length < MIN_ENGLISH_SHARE;
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
 * comes out as that year, or the one before or after. Full-width digits
 * (外１４６名, 第１２条) are read as plain ones (NFKC).
 */
export function checkSummary(s: Summary, source: string, year: number): CheckResult {
  const known = knownNumbers(source.normalize("NFKC"), year);
  const text = shown(s).normalize("NFKC");
  const invented = [...new Set(numbers(text).filter((n) => n.length >= 2 && !known.has(n)))];
  const banned = [...new Set((text.match(BANNED) ?? []).map((w) => w.toLowerCase()))];
  return { invented, banned, notEnglish: notEnglish(text) };
}
