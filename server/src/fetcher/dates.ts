import { toStoredTime } from "./text";

/** How a source writes its dates (the `date` entry of a source's config). */
export interface DateSpec {
  /**
   * Numeric pattern with yyyy, mm, dd, HH, MM, e.g. "dd/mm/yyyy" or "yyyy. mm. dd."; "fr" for "14 octobre 2026";
   * "uk" for "16 жовтня 2026", "15 жовтня 17:34" or "12:31, 16 жовтня" (no year: the latest such date).
   */
  format?: string;
  /** Offset of the source's local time when the date has no zone, e.g. "+03:00". Default UTC. */
  utcOffset?: string;
  /** Treat the value as a date without time even if it has one (e.g. "2026-08-10 00:00:00.0"). */
  dateOnly?: boolean;
}

export interface ParsedDate {
  /** `YYYY-MM-DDTHH:MM:SSZ`. */
  publishedAt: string;
  /** The source gave no time; we store midday UTC, or now if that is still ahead. */
  dateOnly: boolean;
}

const FRENCH_MONTHS = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"];
/** Genitive, as a date writes them ("16 жовтня"). */
const UKRAINIAN_MONTHS = ["січня", "лютого", "березня", "квітня", "травня", "червня", "липня", "серпня", "вересня", "жовтня", "листопада", "грудня"];

function offsetMinutes(offset: string | undefined): number {
  const m = offset?.match(/^([+-])(\d{2}):?(\d{2})$/);
  if (!m) return 0;
  return (m[1] === "-" ? -1 : 1) * (Number(m[2]) * 60 + Number(m[3]));
}

function build(
  parts: { y: number; mo: number; d: number; h?: number; mi?: number; s?: number },
  spec: DateSpec,
  now: Date,
): ParsedDate | null {
  const { y, mo, d } = parts;
  if (!(y > 1900 && mo >= 1 && mo <= 12 && d >= 1 && d <= 31)) return null;
  const hasTime = parts.h !== undefined && !spec.dateOnly;
  if (!hasTime) {
    const noon = new Date(Date.UTC(y, mo - 1, d, 12, 0, 0));
    return { publishedAt: toStoredTime(noon < now ? noon : now), dateOnly: true };
  }
  const utc = Date.UTC(y, mo - 1, d, parts.h ?? 0, parts.mi ?? 0, parts.s ?? 0) - offsetMinutes(spec.utcOffset) * 60_000;
  return { publishedAt: toStoredTime(new Date(utc)), dateOnly: false };
}

function fromPattern(raw: string, format: string): Record<string, number> | null {
  const tokens: string[] = [];
  const pattern = format
    .replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
    .replace(/\s+/g, "\\s*")
    .replace(/yyyy|mm|dd|HH|MM|SS/g, (token) => {
      tokens.push(token);
      return token === "yyyy" ? "(\\d{4})" : "(\\d{1,2})";
    });
  const m = raw.match(new RegExp(pattern));
  if (!m) return null;
  return Object.fromEntries(tokens.map((t, i) => [t, Number(m[i + 1])]));
}

/**
 * Reads a publication date. Without a format it understands ISO 8601 (with or
 * without time and zone) and feed dates such as "Wed, 14 Oct 2026 10:00:00 +0000".
 */
export function parseDate(raw: string | null | undefined, spec: DateSpec = {}, now = new Date()): ParsedDate | null {
  const text = raw?.trim();
  if (!text) return null;

  if (spec.format === "fr") {
    const m = text.toLowerCase().match(/(\d{1,2})(?:er)?\s+([a-zéû]+)\s+(\d{4})/);
    const month = m ? FRENCH_MONTHS.indexOf(m[2]) + 1 : 0;
    return m ? build({ y: Number(m[3]), mo: month, d: Number(m[1]) }, spec, now) : null;
  }
  if (spec.format === "uk") {
    const lower = text.toLowerCase();
    const m = lower.match(/(\d{1,2})\s+([а-яіїєґ]+)(?:\s+(\d{4}))?/);
    const month = m ? UKRAINIAN_MONTHS.indexOf(m[2]) + 1 : 0;
    if (!m || !month) return null;
    // The time may come before or after the date ("12:31, 16 жовтня", "15 жовтня  17:34").
    const time = lower.match(/(\d{1,2}):(\d{2})/);
    const parts = { mo: month, d: Number(m[1]), h: time ? Number(time[1]) : undefined, mi: time ? Number(time[2]) : undefined };
    let y = m[3] ? Number(m[3]) : now.getUTCFullYear();
    // No year: this year, unless that is more than a day ahead (31 December read on 1 January).
    if (!m[3] && Date.UTC(y, month - 1, parts.d) > now.getTime() + 86_400_000) y--;
    return build({ y, ...parts }, spec, now);
  }
  if (spec.format) {
    const p = fromPattern(text, spec.format);
    return p ? build({ y: p.yyyy, mo: p.mm, d: p.dd, h: p.HH, mi: p.MM, s: p.SS }, spec, now) : null;
  }

  const iso = text.match(/^(\d{4})-(\d{2})-(\d{2})(?:(?:T|\s+-\s+|\s+)(\d{2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?\s*(Z|[+-]\d{2}:?\d{2})?)?/);
  if (iso) {
    const zone = iso[7];
    const zoned: DateSpec = zone ? { ...spec, utcOffset: zone === "Z" ? "+00:00" : zone } : spec;
    const h = iso[4] === undefined ? undefined : Number(iso[4]);
    return build({ y: Number(iso[1]), mo: Number(iso[2]), d: Number(iso[3]), h, mi: Number(iso[5] ?? 0), s: Number(iso[6] ?? 0) }, zoned, now);
  }

  // "13/08/2026": day first, as almost every source outside the US writes it.
  const slash = text.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  if (slash) return build({ y: Number(slash[3]), mo: Number(slash[2]), d: Number(slash[1]) }, spec, now);

  // Feed dates; some sites leave out the space after the comma ("Wed,14 Oct 2026").
  const ms = Date.parse(text.replace(/^([A-Za-z]{3}),(\S)/, "$1, $2"));
  if (Number.isNaN(ms)) return null;
  if (spec.dateOnly) {
    const d = new Date(ms);
    return build({ y: d.getUTCFullYear(), mo: d.getUTCMonth() + 1, d: d.getUTCDate() }, spec, now);
  }
  return { publishedAt: toStoredTime(new Date(ms)), dateOnly: false };
}
