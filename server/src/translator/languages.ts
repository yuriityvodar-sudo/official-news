// The languages news articles are translated into (#46), and what the prompt
// and the answer check need to know about each one.
import type { Language } from "./prompt";
import { ENGLISH, GERMAN, SPANISH, except } from "./words";

/** The languages news articles are translated into, besides English. */
export const LANGS = ["uk", "ru", "es", "de"] as const;
export type Lang = (typeof LANGS)[number];

/** Whether `value` is one of LANGS. */
export const isLang = (value: string): value is Lang => (LANGS as readonly string[]).includes(value);

const LATIN = /\p{Script=Latin}/u;

/** What the prompt and the answer check need for each language in LANGS. */
export const LANGUAGES: Record<Lang, Language> = {
  uk: {
    name: "Ukrainian",
    letters: /\p{Script=Cyrillic}/u,
    own: /[іїєґ]/iu,
    // Russian letters, and Russian words Ukrainian does not have.
    foreign:
      /[ыэъё]|(?<!\p{L})(?:и|что|его|как|также|будет|будут|котор\p{L}*|или|из|она|они|был|была|было|были|правительств\p{L}*)(?!\p{L})/iu,
    numbers: {
      decimalComma: true,
      months: ["січня", "лютого", "березня", "квітня", "травня", "червня", "липня", "серпня", "вересня", "жовтня", "листопада", "грудня"],
      scales: [["мільйон\\p{L}*|млн", 6], ["мільярд\\p{L}*|млрд", 9], ["трильйон\\p{L}*|трлн", 12]],
    },
  },
  ru: {
    name: "Russian",
    letters: /\p{Script=Cyrillic}/u,
    // Ukrainian letters, and Ukrainian words Russian does not have.
    foreign:
      /[іїєґ]|(?<!\p{L})(?:що|це|щодо|також|буде|будуть|й|який|яка|яке|якого|яких|якому|або|але|його|вона|вони|був|була|було|були|цей|ця|цього|уряд|уряду|урядом|тепер)(?!\p{L})/iu,
    numbers: {
      decimalComma: true,
      months: ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"],
      scales: [["миллион\\p{L}*|млн", 6], ["миллиард\\p{L}*|млрд", 9], ["триллион\\p{L}*|трлн", 12]],
    },
  },
  // Spanish and German use the English letters, so their check counts function
  // words (words.ts) instead of letters: English or the other language must not
  // outnumber the language's own in any sentence.
  es: {
    name: "Spanish",
    letters: LATIN,
    // "bis" is also Spanish: "artículo 5 bis".
    stopWords: { own: SPANISH, english: ENGLISH, other: except(GERMAN, "bis") },
    numbers: {
      decimalComma: true,
      thousandsDot: true,
      months: ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"],
      // "mil millones" is a billion; a "billón" is a million millions.
      scales: [["millón|millones", 6], ["mil millones", 9], ["billón|billones", 12]],
    },
  },
  de: {
    name: "German",
    letters: LATIN,
    // "los" and "her" are also German: "geht los", "lange her".
    stopWords: { own: GERMAN, english: except(ENGLISH, "her"), other: except(SPANISH, "los") },
    numbers: {
      decimalComma: true,
      thousandsDot: true,
      months: ["januar", "februar", "märz", "april", "mai", "juni", "juli", "august", "september", "oktober", "november", "dezember"],
      // A German "Billion" is a million millions.
      scales: [["millionen|million|mio\\.", 6], ["milliarden|milliarde|mrd\\.", 9], ["billionen|billion", 12]],
    },
  },
};
