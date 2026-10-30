// Checks on a summary before it is stored (#63): the model may not add a number
// the article does not give, nor words of purpose, prediction or judgement the
// style guide rules out. They catch what the prompt alone did not stop in the
// 16 Oct test: "2,500MW" for a notice that held only a title, "2036" for 2026.
import type { Summary } from "./schema";

/**
 * Words that add a purpose, a prediction or a judgement the article did not state
 * (docs/style-guide.md, rule 1). "The ministry says the goal is …" is the allowed form.
 * "may" is not here: "providers may now sell the devices" is a permission the
 * decision grants, which a summary of what changes for the reader needs.
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
  [new RegExp(N + "(?:mil millones|bilhões|bilhão|mld|mrd|billion|milyar|miliard)", "gi"), 1e9],
  [new RegExp(N + "(?:mln|million|milyon|millones|millón|milhões|milhão)", "gi"), 1e6],
  [new RegExp(N + "(?:億|억)", "g"), 1e8],
];

/**
 * The values a scaled number may have. "1,5 mln" is 1.5 million; "US$ 12.240
 * millones" is 12,240 million (Argentina writes thousands with a dot), so
 * three digits after the mark count both ways (#99: "US$12.24 billion").
 */
function scaledValues(written: string, scale: number): string[] {
  const values = [parseFloat(written.replace(",", "."))];
  if (/[.,]\d{3}$/.test(written)) values.push(Number(written.replace(/[.,]/g, "")));
  return values.map((v) => String(Math.round(v * scale)));
}

/** Roman numerals of two letters or more: "XXVI Światowego Jamboree" is the 26th (#99). */
const ROMAN = /\b(?=[MDCLXVI]{2,}\b)M{0,3}(?:CM|CD|D?C{0,3})(?:XC|XL|L?X{0,3})(?:IX|IV|V?I{0,3})\b/g;
const ROMAN_DIGITS: Record<string, number> = { M: 1000, D: 500, C: 100, L: 50, X: 10, V: 5, I: 1 };

function romanValue(numeral: string): number {
  let value = 0;
  for (let i = 0; i < numeral.length; i++) {
    const digit = ROMAN_DIGITS[numeral[i]];
    value += digit < (ROMAN_DIGITS[numeral[i + 1]] ?? 0) ? -digit : digit;
  }
  return value;
}

/**
 * Spanish numbers up to 31 written out, as Mexico's official gazette writes its
 * dates: "veintiséis de enero de dos mil veintiséis" is 26 January 2026 (#99).
 * Read without accents.
 */
const SPANISH_NUMBERS: Record<string, number> = Object.fromEntries(
  (
    "uno dos tres cuatro cinco seis siete ocho nueve diez once doce trece catorce quince dieciseis diecisiete " +
    "dieciocho diecinueve veinte veintiuno veintidos veintitres veinticuatro veinticinco veintiseis veintisiete " +
    "veintiocho veintinueve treinta"
  )
    .split(" ")
    .map((word, i) => [word, i + 1])
    .concat([["primero", 1], ["treinta y uno", 31]]),
);
const SPANISH = new RegExp(
  String.raw`\b(dos mil )?(${Object.keys(SPANISH_NUMBERS).sort((a, b) => b.length - a.length).join("|")})\b`,
  "g",
);

/**
 * Italian numbers from 10 to 99 written out, as Italian laws write ages: "i minori
 * che hanno compiuto i quattordici anni" is 14 (#99; one digit is never checked).
 * The tens drop their vowel before uno and otto (ventuno, trentotto), and ventuno
 * its o before a noun (ventun anni). Read without accents: ventitré is ventitre.
 */
const ITALIAN_UNITS: [string, number][] = [
  ["uno", 1], ["un", 1], ["due", 2], ["tre", 3], ["quattro", 4], ["cinque", 5], ["sei", 6], ["sette", 7], ["otto", 8], ["nove", 9],
];
const ITALIAN_NUMBERS: Record<string, number> = Object.fromEntries([
  ..."dieci undici dodici tredici quattordici quindici sedici diciassette diciotto diciannove"
    .split(" ")
    .map((word, i): [string, number] => [word, 10 + i]),
  ..."venti trenta quaranta cinquanta sessanta settanta ottanta novanta".split(" ").flatMap((ten, i): [string, number][] => [
    [ten, 20 + 10 * i],
    ...ITALIAN_UNITS.map(([unit, n]): [string, number] => [(/^[uo]/.test(unit) ? ten.slice(0, -1) : ten) + unit, 20 + 10 * i + n]),
  ]),
]);
const ITALIAN = new RegExp(String.raw`\b(${Object.keys(ITALIAN_NUMBERS).sort((a, b) => b.length - a.length).join("|")})\b`, "g");

/**
 * Turkish writes a large number in parts, each with its scale word: "455 bin 758"
 * is 455,758 and "1 milyon 250 bin" 1,250,000 (#99). A scale word may have a case
 * ending: "2 bini aşkın" is more than 2,000.
 */
const TURKISH_SCALES: Record<string, number> = { milyar: 1e9, milyon: 1e6, bin: 1e3 };
const TURKISH_SCALE = String.raw`(?:bin(?:in|den|de|i|e)?|milyon(?:un|dan|da|u|a)?|milyar(?:ın|dan|da|ı|a)?)(?!\p{L})`;
const TURKISH = new RegExp(String.raw`(?<![\d.,])(?:\d{1,3} ?${TURKISH_SCALE} ?)+(?:\d{1,3}(?!\d|[.,]\d))?`, "gu");

function turkishValue(parts: string): number {
  let value = 0;
  for (const m of parts.matchAll(/(\d{1,3}) ?(milyar|milyon|bin)?/g)) value += Number(m[1]) * (TURKISH_SCALES[m[2]] ?? 1);
  return value;
}

/** Japan's era years: 令和8年 is 2026, 令和元年 2019, 平成31年 2019. */
const ERAS: [RegExp, number][] = [
  [/令和(\d{1,2}|元)年/g, 2018],
  [/平成(\d{1,2}|元)年/g, 1988],
];

/** An amount with zero cents ("R$ 1.500.000,00", "$2,000.00"): its whole part counts as written without them. */
const ZERO_CENTS = /(?<![\d.,])(\d{1,3}(?:[.,   ]\d{3})+|\d+)[.,]00?(?!\d)/g;

/** The numbers a summary may use: the source's, also as dates, scaled amounts and year ranges ("2026-2027" as "2026-27"). */
function knownNumbers(source: string, year: number): Set<string> {
  const known = new Set(numbers(source));
  for (const re of DATES) {
    for (const m of source.matchAll(re)) {
      for (const part of m.slice(1)) known.add(part).add(String(Number(part)));
    }
  }
  for (const [re, scale] of SCALES) {
    for (const m of source.matchAll(re)) for (const value of scaledValues(m[1], scale)) known.add(value);
  }
  for (const [numeral] of source.matchAll(ROMAN)) if (numeral.length >= 2) known.add(String(romanValue(numeral)));
  const unaccented = source.toLowerCase().normalize("NFD").replace(/\p{M}/gu, "");
  for (const m of unaccented.matchAll(SPANISH)) known.add(String((m[1] ? 2000 : 0) + SPANISH_NUMBERS[m[2]]));
  for (const m of unaccented.matchAll(ITALIAN)) known.add(String(ITALIAN_NUMBERS[m[1]]));
  for (const [parts] of source.matchAll(TURKISH)) known.add(String(turkishValue(parts)));
  for (const [re, start] of ERAS) {
    for (const m of source.matchAll(re)) known.add(String(start + (m[1] === "元" ? 1 : Number(m[1]))));
  }
  for (const m of source.matchAll(ZERO_CENTS)) known.add(m[1].replace(/\D/g, ""));
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

/**
 * An own name kept in its language, in double, angle or CJK quotes (prompt rule 5).
 * Not ‘’: ’ is also the apostrophe.
 */
const QUOTED = /["“”„«»「」『』《》][^"“”„«»「」『』《》\n]{1,160}["“”„«»「」『』《》]/g;

/** Letters of a script other than Latin: Japanese and Chinese have too few spaces to count words. */
const NON_LATIN = /[^\P{L}\p{Script=Latin}]/gu;

function notEnglish(text: string): boolean {
  // A short English headline may quote a long Korean or Japanese law name: only the rest counts (#99).
  const unquoted = text.replace(QUOTED, " ");
  const letters = unquoted.match(/\p{L}/gu)?.length ?? 0;
  if (letters >= 40 && (unquoted.match(NON_LATIN)?.length ?? 0) / letters > 0.3) return true;
  const words = text.toLowerCase().match(/\p{L}+/gu) ?? [];
  if (words.length < MIN_WORDS) return false;
  const english = words.filter((w) => ENGLISH.has(w)).length;
  if (english / words.length >= MIN_ENGLISH_SHARE) return false;
  // Few English words: another language only when its own common words show,
  // or when the lower-case words (names and quoted own names left out) are not English either.
  const rest = unquoted.match(/\p{L}+/gu) ?? [];
  if (rest.filter((w) => OTHER.has(w.toLowerCase())).length > english) return true;
  const lower = rest.filter((w) => /^\p{Ll}/u.test(w));
  return lower.length >= 10 && lower.filter((w) => ENGLISH.has(w)).length / lower.length < MIN_ENGLISH_SHARE;
}

/** Every text of a summary that readers see. */
function shown(s: Summary): string {
  return [s.headline, s.shortSummary, s.summary].join("\n");
}

/** Words in a row a summary may share with the article before they count as copied (#133). */
export const COPIED_WORDS = 12;

/**
 * Runs of COPIED_WORDS or more words in a row that the short summary and the
 * summary take from the article (#133): they should say what changes for the
 * reader, not retell the text. Compared in lower case, letters and digits only,
 * so only a source in English can be copied. The headline may restate the title.
 */
function copiedRuns(s: Summary, source: string): string[] {
  const words = (text: string) => text.toLowerCase().match(/[\p{L}\p{N}]+/gu) ?? [];
  const from = words(source);
  const grams = new Set<string>();
  for (let i = 0; i + COPIED_WORDS <= from.length; i++) grams.add(from.slice(i, i + COPIED_WORDS).join(" "));
  const own = words(`${s.shortSummary}\n${s.summary}`);
  const copied = (end: number) => grams.has(own.slice(end - COPIED_WORDS, end).join(" "));
  const runs: string[] = [];
  for (let end = COPIED_WORDS; end <= own.length; end++) {
    if (!copied(end)) continue;
    const start = end - COPIED_WORDS;
    while (end < own.length && copied(end + 1)) end++;
    runs.push(own.slice(start, end).join(" "));
  }
  return runs;
}

/** The line an event from Wikipedia's current events ends with (fetcher/wikipedia.ts). */
const OUTLETS_LINE = /^(?:Reported by|Источники): (.+)$/m;

/**
 * The outlets an event's summary names, and "reported by" (#230): the app
 * shows where an event comes from, so "The incident was reported by Reuters"
 * gives the reader nothing (event prompt, rule 3). An outlet is found as the
 * source line writes it; one in another script ("РБК") only through "reported by".
 */
export function namedOutlets(s: Summary, text: string): string[] {
  const written = shown(s);
  const outlets = (text.match(OUTLETS_LINE)?.[1] ?? "").split(/, | via /).filter(Boolean);
  const found = outlets.filter((outlet) =>
    new RegExp(`(?<![\\p{L}\\p{N}])${outlet.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?![\\p{L}\\p{N}])`, "iu").test(written),
  );
  if (/\breported by\b/i.test(written)) found.push("reported by");
  return found;
}

export interface CheckResult {
  /** Numbers of two digits or more that are not in the article (its title and text). */
  invented: string[];
  /** Ruled-out words found, lower case. */
  banned: string[];
  /** Written in another language, often the article's own. */
  notEnglish: boolean;
  /** Runs of COPIED_WORDS or more words taken from the article. */
  copied: string[];
}

/**
 * Ruled-out words outside quotes. A capitalised one the source writes the same
 * way is part of a name, such as the "Historic Buildings Act" (#99).
 */
function bannedWords(text: string, source: string): string[] {
  const found = new Set<string>();
  for (const [word] of text.replace(QUOTED, " ").matchAll(BANNED)) {
    if (!(/^\p{Lu}/u.test(word) && source.includes(word))) found.add(word.toLowerCase());
  }
  return [...found];
}

/** Arabic-Indic (١٣٥٠٠), Persian and Devanagari digits as plain ones: NFKC keeps them. */
const DIGIT_ZEROS = [0x0660, 0x06f0, 0x0966];

function plainDigits(text: string): string {
  return text.replace(/[\u0660-\u0669\u06f0-\u06f9\u0966-\u096f]/g, (d) => {
    const code = d.charCodeAt(0);
    return String(code - DIGIT_ZEROS.find((zero) => code <= zero + 9)!);
  });
}

/**
 * "1.5 million" in a summary: its digits count when the source gives the whole
 * amount ("R$ 1.500.000,00"), or an amount that rounds to it at the precision
 * written ("R$6.49 billion" for R$6.494.296.446,00, #99). A wrong rounding
 * ("R$6.4 billion") still counts as invented.
 */
const SUMMARY_SCALES = /(\d+(?:\.\d+)?)\s?(thousand|million|billion|trillion)\b/gi;
const SCALE_VALUES: Record<string, number> = { thousand: 1e3, million: 1e6, billion: 1e9, trillion: 1e12 };

function scaledAmountKnown(written: string, scale: number, known: Set<string>): boolean {
  const value = parseFloat(written);
  if (known.has(String(Math.round(value * scale)))) return true;
  const decimals = written.split(".")[1]?.length ?? 0;
  for (const n of known) {
    const amount = Number(n);
    if (amount >= scale && Number((amount / scale).toFixed(decimals)) === value) return true;
  }
  return false;
}

/**
 * `source` is what the model read: the publication date, the original title and
 * the text. `year` is the year the article was fetched: a date in a calendar of
 * its own comes out as that year, or the one before or after (令和 and 平成 years
 * are read from the source). Full-width digits (外１４６名, 第１２条) are read as
 * plain ones (NFKC), and so are Arabic-Indic ones.
 */
export function checkSummary(s: Summary, source: string, year: number): CheckResult {
  const original = plainDigits(source.normalize("NFKC"));
  const known = knownNumbers(original, year);
  const text = plainDigits(shown(s).normalize("NFKC"));
  for (const m of text.matchAll(SUMMARY_SCALES)) {
    if (scaledAmountKnown(m[1], SCALE_VALUES[m[2].toLowerCase()], known)) known.add(m[1].replace(".", ""));
  }
  const invented = [...new Set(numbers(text).filter((n) => n.length >= 2 && !known.has(n)))];
  return { invented, banned: bannedWords(text, original), notEnglish: notEnglish(text), copied: copiedRuns(s, original) };
}
