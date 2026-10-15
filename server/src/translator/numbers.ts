// The "no missing information" check of a translation (#46): every number in
// the English must also be in the translation. Numbers are compared by value,
// so a translation may write them the way its language does: 1,250,000 as
// "1 250 000", 3.5% as "3,5 %", 1.2 billion as "1,2 млрд", 11:59pm as "23:59".

/**
 * Digits, with the separators numbers use between them: 1,250,000 · 3.5 ·
 * 1 234,5 · 1'000 · 15.10.2026. A separator counts only between two digits, so
 * the full stop after "in 2026." is not part of the number.
 */
const NUMBER = /\d+(?:[.,'’    ]\d+)*/g;
const SEPARATOR = /[^\d]/g;

/** A 12-hour time in the English: 11:59pm, 5 p.m., 9:30 AM. */
const TIME_12H = /\b(\d{1,2})(?::(\d{2}))?\s?([ap])\.?m\b\.?/gi;

/** A time written with a colon, as a translation usually writes it: 23:59, 9:30. */
const TIME = /\b(\d{1,2}):(\d{2})\b/g;

const time = (hour: number, minutes: string) => `${hour}:${minutes}`;

/** One number as text, without leading zeros or trailing decimal zeros: "007" → "7", "3.50" → "3.5". */
function canonical(digits: string): string {
  const [whole, fraction = ""] = digits.split(".");
  const integer = whole.replace(/^0+(?=\d)/, "");
  const decimals = fraction.replace(/0+$/, "");
  return decimals ? `${integer}.${decimals}` : integer;
}

/** Thousands groups after the first one, all with the same separator: "1 250 000", "14.133". */
const isGrouping = (groups: string[], separators: string[]) =>
  groups[0].length <= 3 && groups.slice(1).every((g) => g.length === 3) && separators.every((s) => s === separators[0]);

/**
 * The ways a run of digits reads as one number: "3,5" is 3.5, "14.133" is
 * 14133 or 14.133, "15.10.2026" is none (it is not one number). Also its digit
 * groups: 15, 10 and 2026. In a translation "1,250" may be 1250 or 1.25; in the
 * English it is only 1250, and "500.000" only 500000, so "500" for "500,000"
 * is a missing number.
 */
function readRun(text: string, english: boolean): { values: string[]; groups: string[] } {
  const groups = text.split(SEPARATOR);
  const separators = text.match(SEPARATOR) ?? [];
  const grouping = separators.length > 0 && isGrouping(groups, separators);
  const values = new Set<string>();
  if (!separators.length) values.add(canonical(text));
  // Every separator groups thousands: 1,250,000 · 1 250 000 · 14.133.
  else if (grouping) values.add(canonical(groups.join("")));
  // The last separator is the decimal mark, any before it group thousands with another mark: 3.5 · 3,5 · 1,234.5 · 1 234,5.
  const mark = separators.at(-1);
  const onlyThousands = english && grouping && (mark === "," || /^0+$/.test(groups.at(-1) ?? ""));
  if ((mark === "." || mark === ",") && !onlyThousands) {
    const whole = groups.slice(0, -1);
    const grouping = separators.slice(0, -1);
    if (!grouping.length || (grouping[0] !== mark && isGrouping(whole, grouping))) {
      values.add(canonical(`${whole.join("")}.${groups.at(-1)}`));
    }
  }
  return { values: [...values], groups: groups.map(canonical) };
}

/**
 * What a translation must contain for one number of the English: any one of
 * the alternatives, each a list of values that must all be there.
 */
interface Needed {
  /** As written in the English, for the log. */
  text: string;
  alternatives: string[][];
}

/** The numbers of an English text, each with what a translation must contain for it. */
function neededIn(english: string): Needed[] {
  const needed: Needed[] = [];
  // 11:59pm is 23:59 in a translation, or still 11 and 59 ("11:59 вечора").
  const rest = english.replace(TIME_12H, (text, hour: string, minutes = "00", half: string) => {
    const h = Number(hour) % 12 + (half.toLowerCase() === "p" ? 12 : 0);
    needed.push({ text, alternatives: [[time(h, minutes)], [canonical(hour), ...(minutes === "00" ? [] : [canonical(minutes)])]] });
    return " ";
  });
  for (const text of rest.match(NUMBER) ?? []) {
    const { values, groups } = readRun(text, true);
    // One number: any of its readings. Not one number (a date such as 15.10.2026): each of its parts.
    needed.push({ text, alternatives: values.length ? values.map((v) => [v]) : [groups] });
  }
  return needed;
}

/** Every value a translation has: each number in every way it reads, its digit groups, and its times. */
function valuesIn(translation: string): Set<string> {
  const found = new Set<string>();
  for (const text of translation.match(NUMBER) ?? []) {
    const { values, groups } = readRun(text, false);
    for (const v of [...values, ...groups]) found.add(v);
  }
  for (const [, hour, minutes] of translation.matchAll(TIME)) found.add(time(Number(hour), minutes));
  return found;
}

/**
 * The numbers of `english` that `translation` does not have, as written in the
 * English; empty when every one is there. A number counts as there when the
 * translation has the same value in any usual format (1,250,000 = 1 250 000,
 * 3.5 = 3,5, 11:59pm = 23:59). Something that is not one number, such as a
 * date written 15.10.2026, needs each of its parts; a bill number such as
 * 5575/2026 is two numbers.
 */
export function missingNumbers(english: string, translation: string): string[] {
  const found = valuesIn(translation);
  return neededIn(english)
    .filter(({ alternatives }) => !alternatives.some((values) => values.every((v) => found.has(v))))
    .map(({ text }) => text.trim());
}
