// Dates on the site (#88), in UTC and written out by hand: no Intl, whose
// locale data costs a fresh Worker milliseconds of CPU. The month names are
// the translator's (translator/languages.ts); the formats follow the app's
// (news_widgets.dart: "14 October 2026", "14 жовтня 2026 р.").
import { LANGUAGES } from "../translator/languages";
import type { SiteLang } from "./texts";
import { text } from "./texts";

const ENGLISH_MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

const months = (lang: SiteLang): readonly string[] => (lang === "en" ? ENGLISH_MONTHS : LANGUAGES[lang].numbers.months);

/** A stored time (`YYYY-MM-DDTHH:MM:SSZ`, or a plain `YYYY-MM-DD`) as a Date, or null. */
export function parseTime(value: string | null | undefined): Date | null {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

/** "16 October 2026", "16 жовтня 2026 р.", "16 октября 2026 г.", "16 de octubre de 2026", "16. Oktober 2026". */
export function fullDate(lang: SiteLang, date: Date): string {
  const day = date.getUTCDate();
  const month = months(lang)[date.getUTCMonth()];
  const year = date.getUTCFullYear();
  switch (lang) {
    case "uk":
      return `${day} ${month} ${year} р.`;
    case "ru":
      return `${day} ${month} ${year} г.`;
    case "es":
      return `${day} de ${month} de ${year}`;
    case "de":
      return `${day}. ${month[0].toUpperCase()}${month.slice(1)} ${year}`;
    default:
      return `${day} ${month} ${year}`;
  }
}

/** "23:00 UTC". */
const clock = (date: Date) => `${String(date.getUTCHours()).padStart(2, "0")}:${String(date.getUTCMinutes()).padStart(2, "0")} UTC`;

/**
 * When a decision was published: the day, and the time in UTC when the source
 * gave one ("15 October 2026, 23:00 UTC"), so an Asia-Pacific decision dated
 * the next local day is never shown on the wrong day without saying why.
 */
export function publishedDate(lang: SiteLang, date: Date, dateOnly: boolean): string {
  const day = fullDate(lang, date);
  return dateOnly ? day : text(lang, "dateAndTime", { date: day, time: clock(date) });
}

/** The machine-readable form for `<time datetime>`. */
export const isoTime = (date: Date) => `${date.toISOString().slice(0, 19)}Z`;
