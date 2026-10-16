// The feed's filters (#67, #68): Where (all countries, a group of countries
// or one country) and one topic, and the names the app shows in their menus.
import { TOPICS, type Topic } from "../summarizer/schema";
import type { Lang } from "../translator";

/** The languages names are given in: English and every language of LANGS. */
export type NameLang = "en" | Lang;

/** The source country of the EU's own institutions (the European Commission): not a country, but in groups. */
export const EU = "EU";

/**
 * The groups of countries in the Where menu (Yurii, 16 Oct), in the menu's
 * order: official organizations, with their members among the countries we
 * have or plan sources for (ISO 3166-1 alpha-2; memberships read on the
 * organizations' official pages, 16 Oct). `includesEU`: the group also shows
 * the EU institutions' own decisions (the EU is a member of the G7 and the
 * G20, not of NATO). Russia is not a source country (#42), so it is in none.
 * Saudi Arabia has no source yet: the G20 shows it once it has one. The
 * single place groups are defined: the filter, GET /countries and their
 * names all read it.
 */
export const GROUPS = [
  { id: "eu", members: ["CZ", "DE", "ES", "FR", "IT", "PL"], includesEU: true },
  { id: "g7", members: ["CA", "DE", "FR", "GB", "IT", "JP", "US"], includesEU: true },
  {
    id: "g20",
    members: ["AR", "AU", "BR", "CA", "CN", "DE", "FR", "GB", "ID", "IN", "IT", "JP", "KR", "MX", "SA", "TR", "US", "ZA"],
    includesEU: true,
  },
  { id: "nato", members: ["CA", "CZ", "DE", "ES", "FR", "GB", "IT", "PL", "TR", "US"], includesEU: false },
] as const satisfies readonly { id: string; members: readonly string[]; includesEU: boolean }[];

export type Group = (typeof GROUPS)[number];
export type GroupId = Group["id"];

/** The source countries a group shows: its members, then the EU institutions where the group includes them. */
export const groupCountries = (group: Group): string[] => [...group.members, ...(group.includesEU ? [EU] : [])];

/**
 * Where the feed's articles come from: one country alone (only that
 * country's sources, never the EU's mixed in), or a group; null is all
 * countries.
 */
export type Where = { country: string } | { group: Group } | null;

/** The source countries `where` shows, or null for all countries. */
export const whereCountries = (where: Where): string[] | null =>
  where === null ? null : "country" in where ? [where.country] : groupCountries(where.group);

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

/** [en, uk, ru, es, de] */
type Names = readonly [string, string, string, string, string];

/**
 * Country names for the source countries (docs/sources.csv), the same as the
 * app's (app/lib/l10n), plus the countries planned next (#72). A test checks
 * that every country of docs/sources.csv is here. Written out rather than read
 * from Intl.DisplayNames: loading ICU's names costs a fresh Worker several ms
 * of its 10 ms of CPU.
 */
const COUNTRIES: Record<string, Names> = {
  AR: ["Argentina", "Аргентина", "Аргентина", "Argentina", "Argentinien"],
  AU: ["Australia", "Австралія", "Австралия", "Australia", "Australien"],
  BR: ["Brazil", "Бразилія", "Бразилия", "Brasil", "Brasilien"],
  CA: ["Canada", "Канада", "Канада", "Canadá", "Kanada"],
  CN: ["China", "Китай", "Китай", "China", "China"],
  CZ: ["Czechia", "Чехія", "Чехия", "Chequia", "Tschechien"],
  DE: ["Germany", "Німеччина", "Германия", "Alemania", "Deutschland"],
  ES: ["Spain", "Іспанія", "Испания", "España", "Spanien"],
  EU: ["European Union", "Європейський Союз", "Европейский союз", "Unión Europea", "Europäische Union"],
  FR: ["France", "Франція", "Франция", "Francia", "Frankreich"],
  GB: ["United Kingdom", "Велика Британія", "Великобритания", "Reino Unido", "Vereinigtes Königreich"],
  ID: ["Indonesia", "Індонезія", "Индонезия", "Indonesia", "Indonesien"],
  IN: ["India", "Індія", "Индия", "India", "Indien"],
  IT: ["Italy", "Італія", "Италия", "Italia", "Italien"],
  JP: ["Japan", "Японія", "Япония", "Japón", "Japan"],
  KR: ["South Korea", "Південна Корея", "Южная Корея", "Corea del Sur", "Südkorea"],
  MX: ["Mexico", "Мексика", "Мексика", "México", "Mexiko"],
  PL: ["Poland", "Польща", "Польша", "Polonia", "Polen"],
  RU: ["Russia", "Росія", "Россия", "Rusia", "Russland"],
  SA: ["Saudi Arabia", "Саудівська Аравія", "Саудовская Аравия", "Arabia Saudita", "Saudi-Arabien"],
  TR: ["Türkiye", "Туреччина", "Турция", "Turquía", "Türkei"],
  UA: ["Ukraine", "Україна", "Украина", "Ucrania", "Ukraine"],
  US: ["United States", "США", "США", "Estados Unidos", "Vereinigte Staaten"],
  ZA: ["South Africa", "ПАР", "ЮАР", "Sudáfrica", "Südafrika"],
};

const NAME_INDEX: Record<NameLang, number> = { en: 0, uk: 1, ru: 2, es: 3, de: 4 };

/** The groups' names: the European Union as the EU institutions are named; G7 and G20 written so in every language. */
const GROUP_NAMES: Record<GroupId, Names> = {
  eu: COUNTRIES[EU],
  g7: ["G7", "G7", "G7", "G7", "G7"],
  g20: ["G20", "G20", "G20", "G20", "G20"],
  nato: ["NATO", "НАТО", "НАТО", "OTAN", "NATO"],
};

/** The group's name in `lang`. */
export const groupName = (group: Group, lang: NameLang): string => GROUP_NAMES[group.id][NAME_INDEX[lang]];

/** Whether the country (or the EU institutions, `EU`) has a name in every language. */
export const hasCountryName = (code: string) => code in COUNTRIES;

/** The country's (or the EU institutions') name in `lang`; an unknown code is shown as it is. */
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

export const COUNTRY_ERROR = "country must be a country code of 2 capital letters, such as DE";
export const GROUP_ERROR = `group must be one of: ${GROUPS.map((g) => g.id).join(", ")}`;
export const WHERE_ERROR = "country and group cannot be used together: send one of them";

/**
 * The Where filter of a request: `country=XX` (2 capital letters) or
 * `group=<id>` (one of GROUPS), at most one of them; neither is all
 * countries. A message for a 400 otherwise.
 */
export function readWhere(params: URLSearchParams): { where: Where } | { error: string } {
  const country = params.get("country");
  if (country !== null && !/^[A-Z]{2}$/.test(country)) return { error: COUNTRY_ERROR };
  const groupId = params.get("group");
  const group = groupId === null ? null : GROUPS.find((g) => g.id === groupId);
  if (group === undefined) return { error: GROUP_ERROR };
  if (country !== null && group !== null) return { error: WHERE_ERROR };
  return { where: country !== null ? { country } : group !== null ? { group } : null };
}

/** `topic`: null when absent (All topics), undefined when it is not one of TOPICS. */
export function readTopic(params: URLSearchParams): Topic | null | undefined {
  const value = params.get("topic");
  if (value === null) return null;
  return (TOPICS as readonly string[]).includes(value) ? (value as Topic) : undefined;
}

export const TOPIC_ERROR = `topic must be one of: ${TOPICS.join(", ")}`;
