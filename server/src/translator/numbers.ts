// The "no missing information" check of a translation (#46): every number in
// the English must also be in the translation, each one by a number of its own,
// so "5 ministers in 5 regions" needs two fives. Numbers are compared by value,
// so a translation may write them the way its language does: 1,250,000 as
// "1 250 000", 3.5% as "3,5 %", 1.2 billion as "1,2 млрд", 11:59pm as "23:59"
// or "23.59", 15.10.2026 as "15 жовтня 2026".

/** How a language writes numbers and dates: LANGUAGES in ./index.ts has one per language. */
export interface NumberStyle {
  /**
   * The decimal mark is a comma (3,5) and thousands are grouped with spaces
   * (1 250 000), as in Ukrainian and Russian. A comma in a translation is then
   * only a decimal mark: a reader takes "1,500" for 1.5, so English thousands
   * copied unchanged do not count, except in an identifier after "№".
   */
  decimalComma: boolean;
  /** The month names as written after a day ("14 жовтня"), January first, in lower case. */
  months: readonly string[];
}

/**
 * Digits, with the separators numbers use between them: 1,250,000 · 3.5 ·
 * 1 234,5 · 1'000 · 15.10.2026. A separator counts only between two digits, so
 * the full stop after "in 2026." is not part of the number.
 */
const NUMBER = /\d+(?:[.,'’    ]\d+)*/g;
const SEPARATOR = /[^\d]/g;
const SPACES = /[    ]/g;

/** A 12-hour time in the English: 11:59pm, 5 p.m., 9:30 AM. */
const TIME_12H = /\b(\d{1,2})(?::(\d{2}))?\s?([ap])\.?m\b\.?/gi;

/** A time written with a colon: 23:59, 9:30. */
const TIME = /(?<![\d:])(\d{1,2}):(\d{2})(?![\d:])/g;

/** A time written with a full stop, as Ukrainian and Russian also do: 17.00, 23.59. */
const DOTTED_TIME = /^(\d{1,2})\.(\d{2})$/;

/** A date in numbers, day or month first: 15.10.2026, 14/10/2026, 10/14/2026, 14-10-2026. */
const DATE = /(?<![\d.,/-])(\d{1,2})([./-])(\d{1,2})\2(\d{4})(?![\d/-]|[.,]\d)/g;

/** A date in numbers, year first: 2026-10-14. */
const ISO_DATE = /(?<![\d.,/-])(\d{4})-(\d{1,2})-(\d{1,2})(?![\d/-]|[.,]\d)/g;

const time = (hour: number, minutes: string) => `${hour}:${minutes}`;
const isTime = (hour: number, minutes: number) => hour <= 24 && minutes <= 59;
const month = (n: number) => `month ${n}`;

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
 * The ways a run of digits reads as one number: "3.5" is 3.5, "14.133" is 14133
 * or 14.133, "15.10.2026" is none (it is not one number). In the English
 * "1,250" is only 1250, and "500.000" only 500000, so "500" for "500,000" is a
 * missing number. In a translation "1,250" is 1250 or 1.25, but only 1.25 with
 * `decimalComma`, where "1,250,000" is no number at all.
 */
function readRun(text: string, english: boolean, decimalComma: boolean): string[] {
  const groups = text.split(SEPARATOR);
  const separators = text.match(SEPARATOR) ?? [];
  if (!separators.length) return [canonical(text)];
  const commas = separators.filter((s) => s === ",").length;
  const commaIsDecimal = !english && decimalComma && commas > 0;
  if (commaIsDecimal && (commas > 1 || separators.at(-1) !== ",")) return [];

  const values = new Set<string>();
  const grouping = isGrouping(groups, separators);
  // Every separator groups thousands: 1,250,000 · 1 250 000 · 14.133.
  if (grouping && !commaIsDecimal) values.add(canonical(groups.join("")));
  // The last separator is the decimal mark, any before it group thousands with another mark: 3.5 · 3,5 · 1,234.5 · 1 234,5.
  const mark = separators.at(-1);
  const onlyThousands = english && grouping && (mark === "," || /^0+$/.test(groups.at(-1) ?? ""));
  if ((mark === "." || mark === ",") && !onlyThousands) {
    const whole = groups.slice(0, -1);
    const before = separators.slice(0, -1);
    if (!before.length || (before[0] !== mark && isGrouping(whole, before))) {
      values.add(canonical(`${whole.join("")}.${groups.at(-1)}`));
    }
  }
  return [...values];
}

/**
 * A number of a text and what stands for it: one slot, the values it may have,
 * or several when it is not one number (each digit group of 1.2.3 is its own).
 */
interface Found {
  text: string;
  /** Where it starts in the text, so missing numbers are named in the English order. */
  at: number;
  /** Matched first (lower): the parts of a date, then other numbers, then times, which may also be read several ways. */
  rank: number;
  slots: string[][];
}

/** The numbers of a run of digits (NUMBER). */
function numbersIn(text: string, at: number, english: boolean, decimalComma: boolean): Found[] {
  const values = readRun(text, english, decimalComma);
  if (values.length) {
    const dotted = english ? null : DOTTED_TIME.exec(text);
    if (dotted && isTime(Number(dotted[1]), Number(dotted[2]))) values.push(time(Number(dotted[1]), dotted[2]));
    return [{ text, at, rank: 1, slots: [values] }];
  }
  // Not one number. Numbers only a space separates ("2026 1,500") are read one by one;
  // a group of 3 digits stays with the number before it ("2026 1 500" is 2026 and 1500).
  const parts: { text: string; at: number }[] = [];
  let offset = 0;
  for (const piece of text.split(SPACES)) {
    const last = parts.at(-1);
    if (last && /^\d{3}$/.test(piece) && /^\d{1,3}(?:\s\d{3})*$/.test(last.text)) last.text = text.slice(last.at - at, offset + 3);
    else parts.push({ text: piece, at: at + offset });
    offset += piece.length + 1;
  }
  if (parts.length > 1) return parts.flatMap((p) => numbersIn(p.text, p.at, english, decimalComma));
  // Each digit group on its own: 15.10.2026 in a translation, 1.2.3.
  return [{ text, at, rank: 1, slots: text.split(SEPARATOR).map((g) => [canonical(g)]) }];
}

/** Blanks out what a pattern found, keeping every position, so the next pattern sees only the rest. */
function take(
  text: string,
  pattern: RegExp,
  found: (match: (string | undefined)[], index: number) => Found | null,
): { rest: string; found: Found[] } {
  const all: Found[] = [];
  // replace() passes the match, its groups, then where it starts (none of these patterns has named groups).
  const rest = text.replace(pattern, (...args: unknown[]) => {
    const match = args.slice(0, -2) as (string | undefined)[];
    const one = found(match, args.at(-2) as number);
    if (!one) return match[0] as string;
    all.push(one);
    return " ".repeat((match[0] as string).length);
  });
  return { rest, found: all };
}

/** The numbers of an English text, each with what a translation must have for it. */
function neededIn(english: string): Found[] {
  // 11:59pm is 23:59 in a translation, or 11:59 ("11:59 вечора"); 5pm also 17 ("о 17 годині") or 5.
  const times12 = take(english, TIME_12H, ([text = "", h, minutes = "00", half = ""], index) => {
    const hour = Number(h);
    if (hour < 1 || hour > 12) return null;
    const h24 = (hour % 12) + (half.toLowerCase() === "p" ? 12 : 0);
    const readings = [time(h24, minutes), time(hour, minutes), ...(minutes === "00" ? [String(h24), String(hour)] : [])];
    return { text, at: index, rank: 2, slots: [readings] };
  });
  // The month of a date in numbers may be written as a word; 05/10/2026 is 5 October or 10 May.
  const dates = take(times12.rest, DATE, ([text = "", a, , b, year = ""], index) => {
    const [first, second] = [Number(a), Number(b)];
    const dayMonth = first >= 1 && first <= 31 && second >= 1 && second <= 12;
    const monthDay = first >= 1 && first <= 12 && second >= 1 && second <= 31;
    if (!dayMonth && !monthDay) return null;
    const slots = [
      [String(first), ...(monthDay ? [month(first)] : [])],
      [String(second), ...(dayMonth ? [month(second)] : [])],
      [canonical(year)],
    ];
    return { text, at: index, rank: 0, slots };
  });
  const isoDates = take(dates.rest, ISO_DATE, ([text = "", year = "", m, d], index) => {
    const [mm, dd] = [Number(m), Number(d)];
    if (mm < 1 || mm > 12 || dd < 1 || dd > 31) return null;
    return { text, at: index, rank: 0, slots: [[canonical(year)], [String(mm), month(mm)], [String(dd)]] };
  });
  // 17:00 is also "о 17 годині".
  const times = take(isoDates.rest, TIME, ([text = "", h, minutes = ""], index) => {
    const hour = Number(h);
    if (!isTime(hour, Number(minutes))) return null;
    return { text, at: index, rank: 2, slots: [[time(hour, minutes), ...(minutes === "00" ? [String(hour)] : [])]] };
  });
  const numbers = [...times.rest.matchAll(NUMBER)].flatMap((m) => numbersIn(m[0], m.index ?? 0, true, false));
  return [...times12.found, ...dates.found, ...isoDates.found, ...times.found, ...numbers].sort((x, y) => x.at - y.at);
}

/** Every number of a translation, each with the values it may stand for, and its month names. */
function numbersOf(translation: string, style: NumberStyle): string[][] {
  const times = take(translation, TIME, ([text = "", h, minutes = ""], index) =>
    isTime(Number(h), Number(minutes)) ? { text, at: index, rank: 2, slots: [[time(Number(h), minutes)]] } : null,
  );
  const numbers = [...times.rest.matchAll(NUMBER)].flatMap((m) => {
    // An identifier after "№" (a law number) may keep the English comma: it is a label, not an amount.
    const identifier = /№\s*$/.test(times.rest.slice(0, m.index));
    return numbersIn(m[0], m.index ?? 0, false, style.decimalComma && !identifier);
  });
  const monthNames = style.months.length
    ? [...translation.matchAll(new RegExp(`(?<!\\p{L})(?:${style.months.join("|")})(?!\\p{L})`, "giu"))].map((m) => [
        month(style.months.indexOf(m[0].toLowerCase()) + 1),
      ])
    : [];
  return [...times.found, ...numbers].flatMap((f) => f.slots).concat(monthNames);
}

/**
 * The numbers of `english` that `translation` does not have, as written in the
 * English; empty when every one is there. Each number of the translation
 * stands for one number of the English at most, so a dropped "5" is not found
 * inside "3,5", "1 500" or "15.10.2026", and a number written twice is needed
 * twice. A number counts as there when the translation has the same value in
 * any usual format of `style` (1,250,000 = 1 250 000, 3.5 = 3,5, 11:59pm =
 * 23:59). A date written 15.10.2026 needs its day, its month (in numbers or as
 * a word) and its year; a bill number such as 5575/2026 is two numbers.
 */
export function missingNumbers(english: string, translation: string, style: NumberStyle): string[] {
  const values = numbersOf(translation, style);
  const needed = neededIn(english);
  const slots = needed
    .flatMap((n, item) => n.slots.map((readings) => ({ item, rank: n.rank, readings })))
    .sort((x, y) => x.rank - y.rank);
  // A matching of English slots to translation numbers (Kuhn's algorithm): a slot
  // takes a free number that fits, or one whose slot can move to another.
  const holder = new Array<number>(values.length).fill(-1);
  const place = (slot: number, tried: boolean[]): boolean => {
    for (let v = 0; v < values.length; v++) {
      if (tried[v] || !slots[slot].readings.some((r) => values[v].includes(r))) continue;
      tried[v] = true;
      if (holder[v] < 0 || place(holder[v], tried)) {
        holder[v] = slot;
        return true;
      }
    }
    return false;
  };
  const missing = new Set<number>();
  slots.forEach((slot, i) => {
    if (!place(i, new Array<boolean>(values.length).fill(false))) missing.add(slot.item);
  });
  return needed.filter((_, i) => missing.has(i)).map(({ text }) => text.trim());
}
