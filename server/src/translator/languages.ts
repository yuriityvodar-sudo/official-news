// The languages news articles are translated into (#46), and what the prompt
// and the answer check need to know about each one.
import type { Language } from "./prompt";
import { ENGLISH, GERMAN, SPANISH } from "./words";

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
    },
  },
  // Spanish and German use the English letters, so their check counts function
  // words (words.ts) instead of letters: English or the other language must not
  // outnumber the language's own in any sentence.
  es: {
    name: "Spanish",
    letters: LATIN,
    stopWords: { own: SPANISH, foreign: [ENGLISH, GERMAN] },
    numbers: {
      decimalComma: true,
      thousandsDot: true,
      months: ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"],
    },
  },
  de: {
    name: "German",
    letters: LATIN,
    stopWords: { own: GERMAN, foreign: [ENGLISH, SPANISH] },
    numbers: {
      decimalComma: true,
      thousandsDot: true,
      months: ["januar", "februar", "märz", "april", "mai", "juni", "juli", "august", "september", "oktober", "november", "dezember"],
    },
  },
};
