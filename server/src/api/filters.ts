// The feed's filters (#67, #68): Where (Global, or Local: one country plus the
// blocs it belongs to) and one topic, and the names the app shows in their menus.
import { TOPICS, type Topic } from "../summarizer/schema";
import type { Lang } from "../translator";

/** The languages names are given in: English and every language of LANGS. */
export type NameLang = "en" | Lang;

/**
 * Blocs that publish as one source country, with their members (ISO 3166-1
 * alpha-2). A member's Local feed also shows the bloc's articles; a bloc is
 * never in the list of countries. Greece is GR here, as phones report it (the
 * EU itself writes EL).
 */
export const BLOCS: Record<string, readonly string[]> = {
  EU: [
    "AT", "BE", "BG", "CY", "CZ", "DE", "DK", "EE", "ES", "FI", "FR", "GR", "HR", "HU",
    "IE", "IT", "LT", "LU", "LV", "MT", "NL", "PL", "PT", "RO", "SE", "SI", "SK",
  ],
};

/** The source countries a country's Local feed shows: the country itself, then every bloc it belongs to. */
export function localCountries(country: string): string[] {
  return [country, ...Object.keys(BLOCS).filter((bloc) => BLOCS[bloc].includes(country))];
}

/** The fixed topic list (TOPICS, docs/contract.md) in each language. */
export const TOPIC_NAMES: Record<NameLang, Record<Topic, string>> = {
  en: {
    "foreign-affairs": "Foreign affairs",
    economy: "Economy",
    "security-defence": "Security and defence",
    health: "Health",
    climate: "Climate",
    trade: "Trade",
    technology: "Technology",
    energy: "Energy",
    migration: "Migration",
    elections: "Elections",
    "human-rights": "Human rights",
    science: "Science",
  },
  uk: {
    "foreign-affairs": "Зовнішня політика",
    economy: "Економіка",
    "security-defence": "Безпека та оборона",
    health: "Здоров’я",
    climate: "Клімат",
    trade: "Торгівля",
    technology: "Технології",
    energy: "Енергетика",
    migration: "Міграція",
    elections: "Вибори",
    "human-rights": "Права людини",
    science: "Наука",
  },
  ru: {
    "foreign-affairs": "Внешняя политика",
    economy: "Экономика",
    "security-defence": "Безопасность и оборона",
    health: "Здоровье",
    climate: "Климат",
    trade: "Торговля",
    technology: "Технологии",
    energy: "Энергетика",
    migration: "Миграция",
    elections: "Выборы",
    "human-rights": "Права человека",
    science: "Наука",
  },
  es: {
    "foreign-affairs": "Asuntos exteriores",
    economy: "Economía",
    "security-defence": "Seguridad y defensa",
    health: "Salud",
    climate: "Clima",
    trade: "Comercio",
    technology: "Tecnología",
    energy: "Energía",
    migration: "Migración",
    elections: "Elecciones",
    "human-rights": "Derechos humanos",
    science: "Ciencia",
  },
  de: {
    "foreign-affairs": "Außenpolitik",
    economy: "Wirtschaft",
    "security-defence": "Sicherheit und Verteidigung",
    health: "Gesundheit",
    climate: "Klima",
    trade: "Handel",
    technology: "Technologie",
    energy: "Energie",
    migration: "Migration",
    elections: "Wahlen",
    "human-rights": "Menschenrechte",
    science: "Wissenschaft",
  },
};

/**
 * GET /topics's answer for these articles' topic lists: each topic of TOPICS
 * that one of them has, busiest first (ties keep the order of TOPICS), named
 * in `lang`, without counts. An article counts once per topic. The website
 * uses it too, for a page that already holds every article of its list.
 */
export function rankTopics(lists: Iterable<readonly string[]>, lang: NameLang): { id: Topic; name: string }[] {
  const counts = new Map<string, number>();
  for (const list of lists) for (const topic of new Set(list)) counts.set(topic, (counts.get(topic) ?? 0) + 1);
  const names = TOPIC_NAMES[lang];
  return TOPICS.filter((topic) => counts.has(topic))
    // Stable: equal counts keep the order of TOPICS.
    .sort((a, b) => (counts.get(b) ?? 0) - (counts.get(a) ?? 0))
    .map((id) => ({ id, name: names[id] }));
}

/** [en, uk, ru, es, de] */
type Names = readonly [string, string, string, string, string];

/**
 * Country names for the source countries (docs/sources.csv), the same as the
 * app's (app/lib/l10n), plus the countries planned next (#72) and every other
 * member of a bloc in BLOCS (#88: a member's Local feed is the bloc's, so the
 * website has a page for it, as the app's Local shows it). Tests check that
 * every country of docs/sources.csv and every bloc member is here, and that a
 * name the app's ARB files have is the same. Written out rather than read
 * from Intl.DisplayNames: loading ICU's names costs a fresh Worker several ms
 * of its 10 ms of CPU.
 */
const COUNTRIES: Record<string, Names> = {
  AR: ["Argentina", "Аргентина", "Аргентина", "Argentina", "Argentinien"],
  AT: ["Austria", "Австрія", "Австрия", "Austria", "Österreich"],
  AU: ["Australia", "Австралія", "Австралия", "Australia", "Australien"],
  BE: ["Belgium", "Бельгія", "Бельгия", "Bélgica", "Belgien"],
  BG: ["Bulgaria", "Болгарія", "Болгария", "Bulgaria", "Bulgarien"],
  BR: ["Brazil", "Бразилія", "Бразилия", "Brasil", "Brasilien"],
  CA: ["Canada", "Канада", "Канада", "Canadá", "Kanada"],
  CN: ["China", "Китай", "Китай", "China", "China"],
  CY: ["Cyprus", "Кіпр", "Кипр", "Chipre", "Zypern"],
  CZ: ["Czechia", "Чехія", "Чехия", "Chequia", "Tschechien"],
  DE: ["Germany", "Німеччина", "Германия", "Alemania", "Deutschland"],
  DK: ["Denmark", "Данія", "Дания", "Dinamarca", "Dänemark"],
  EE: ["Estonia", "Естонія", "Эстония", "Estonia", "Estland"],
  ES: ["Spain", "Іспанія", "Испания", "España", "Spanien"],
  EU: ["European Union", "Європейський Союз", "Европейский союз", "Unión Europea", "Europäische Union"],
  FI: ["Finland", "Фінляндія", "Финляндия", "Finlandia", "Finnland"],
  FR: ["France", "Франція", "Франция", "Francia", "Frankreich"],
  GB: ["United Kingdom", "Велика Британія", "Великобритания", "Reino Unido", "Vereinigtes Königreich"],
  GR: ["Greece", "Греція", "Греция", "Grecia", "Griechenland"],
  HR: ["Croatia", "Хорватія", "Хорватия", "Croacia", "Kroatien"],
  HU: ["Hungary", "Угорщина", "Венгрия", "Hungría", "Ungarn"],
  ID: ["Indonesia", "Індонезія", "Индонезия", "Indonesia", "Indonesien"],
  IE: ["Ireland", "Ірландія", "Ирландия", "Irlanda", "Irland"],
  IN: ["India", "Індія", "Индия", "India", "Indien"],
  IT: ["Italy", "Італія", "Италия", "Italia", "Italien"],
  JP: ["Japan", "Японія", "Япония", "Japón", "Japan"],
  KR: ["South Korea", "Південна Корея", "Южная Корея", "Corea del Sur", "Südkorea"],
  LT: ["Lithuania", "Литва", "Литва", "Lituania", "Litauen"],
  LU: ["Luxembourg", "Люксембург", "Люксембург", "Luxemburgo", "Luxemburg"],
  LV: ["Latvia", "Латвія", "Латвия", "Letonia", "Lettland"],
  MT: ["Malta", "Мальта", "Мальта", "Malta", "Malta"],
  MX: ["Mexico", "Мексика", "Мексика", "México", "Mexiko"],
  NL: ["Netherlands", "Нідерланди", "Нидерланды", "Países Bajos", "Niederlande"],
  PL: ["Poland", "Польща", "Польша", "Polonia", "Polen"],
  PT: ["Portugal", "Португалія", "Португалия", "Portugal", "Portugal"],
  RO: ["Romania", "Румунія", "Румыния", "Rumania", "Rumänien"],
  RU: ["Russia", "Росія", "Россия", "Rusia", "Russland"],
  SA: ["Saudi Arabia", "Саудівська Аравія", "Саудовская Аравия", "Arabia Saudita", "Saudi-Arabien"],
  SE: ["Sweden", "Швеція", "Швеция", "Suecia", "Schweden"],
  SI: ["Slovenia", "Словенія", "Словения", "Eslovenia", "Slowenien"],
  SK: ["Slovakia", "Словаччина", "Словакия", "Eslovaquia", "Slowakei"],
  TR: ["Türkiye", "Туреччина", "Турция", "Turquía", "Türkei"],
  UA: ["Ukraine", "Україна", "Украина", "Ucrania", "Ukraine"],
  US: ["United States", "США", "США", "Estados Unidos", "Vereinigte Staaten"],
  ZA: ["South Africa", "ПАР", "ЮАР", "Sudáfrica", "Südafrika"],
};

const NAME_INDEX: Record<NameLang, number> = { en: 0, uk: 1, ru: 2, es: 3, de: 4 };

/** Whether the country (or bloc) has a name in every language. */
export const hasCountryName = (code: string) => code in COUNTRIES;

/** The country's (or bloc's) name in `lang`; an unknown code is shown as it is. */
export function countryName(code: string, lang: NameLang): string {
  return COUNTRIES[code]?.[NAME_INDEX[lang]] ?? code;
}

/** Each language's alphabet where the order of Unicode is not the alphabet's (Cyrillic ґ, є, і, ї, ё). */
const ALPHABETS: Partial<Record<NameLang, string>> = {
  uk: "абвгґдеєжзиіїйклмнопрстуфхцчшщьюя",
  ru: "абвгдеёжзийклмнопрстуфхцчшщъыьэюя",
};

/** Latin letters with marks sort with their base letter; Spanish ñ after n ("~" sorts after "z"), German ß as ss. */
const LATIN: Record<string, string> = {
  á: "a", à: "a", â: "a", ä: "a", ã: "a", å: "a", ç: "c", é: "e", è: "e", ê: "e", ë: "e", í: "i", ì: "i", î: "i",
  ï: "i", ñ: "n~", ó: "o", ò: "o", ô: "o", ö: "o", õ: "o", ú: "u", ù: "u", û: "u", ü: "u", ß: "ss",
};

/**
 * A key that sorts names alphabetically in `lang` by plain comparison. Not
 * Intl.Collator: loading ICU's collation costs a fresh Worker about 5 ms of
 * its 10 ms of CPU, for a list of about twenty names.
 */
function sortKey(name: string, lang: NameLang): string {
  const alphabet = ALPHABETS[lang];
  let key = "";
  for (const letter of name.toLowerCase()) {
    const place = alphabet ? alphabet.indexOf(letter) : -1;
    key += place >= 0 ? String.fromCharCode(0x400 + place) : (LATIN[letter] ?? letter);
  }
  return key;
}

/** `items` sorted by name in `lang`, alphabetically. */
export function byName<T extends { name: string }>(items: T[], lang: NameLang): T[] {
  const keyed = items.map((item) => ({ item, key: sortKey(item.name, lang) }));
  keyed.sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
  return keyed.map(({ item }) => item);
}

/** `country`: null when absent (Global), undefined when it is not 2 capital letters. */
export function readCountry(params: URLSearchParams): string | null | undefined {
  const value = params.get("country");
  if (value === null) return null;
  return /^[A-Z]{2}$/.test(value) ? value : undefined;
}

export const COUNTRY_ERROR = "country must be a country code of 2 capital letters, such as DE";

/** `topic`: null when absent (All topics), undefined when it is not one of TOPICS. */
export function readTopic(params: URLSearchParams): Topic | null | undefined {
  const value = params.get("topic");
  if (value === null) return null;
  return (TOPICS as readonly string[]).includes(value) ? (value as Topic) : undefined;
}

export const TOPIC_ERROR = `topic must be one of: ${TOPICS.join(", ")}`;
