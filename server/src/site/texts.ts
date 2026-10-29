// The site's words (#88). The app's texts come from its ARB files through
// app-texts.generated.ts, never copied; only what the app does not say is
// written here, in all 5 languages (TypeScript requires each one). The uk and
// ru texts need Yurii's review, es and de a native speaker's.
import { GROUPS, type GroupId, TOPIC_NAMES, countryName as apiCountryName, groupName as apiGroupName } from "../api/filters";
import type { Topic } from "../summarizer/schema";
import { APP_TEXTS, type AppKey, LANGUAGE_NAMES, PUBLISHER_DETAILS, PUBLISHER_NAME, SITE_LANGS, type SiteLang } from "./app-texts.generated";
import { Html, esc } from "./html";

export { LANGUAGE_NAMES, SITE_LANGS, type SiteLang };

export const isSiteLang = (value: string): value is SiteLang => (SITE_LANGS as readonly string[]).includes(value);

interface SiteTexts {
  /**
   * The EU AI Act Art. 50(4) notice: AI text on public-interest matters, not
   * reviewed by a person. It is also the change notice the licences ask for
   * (CC BY: changes indicated; the Japanese PDL 1.0: that the text was edited
   * and by whom, `{publisher}`), and says it is not the official text (no
   * official status). Once on a page, above the credit (#88 review).
   */
  aiNotice: string;
  creditSource: string;
  published: string;
  added: string;
  originalTitle: string;
  older: string;
  latestLink: string;
  /** Heads the list under Top stories on page 1. The site's own since the app
   * shows one list under its Top stories block with no heading (#164). */
  latest: string;
  /** The list page's h1. */
  listTitle: string;
  /** The "Get the app" block above the footer (Yurii, 28 Oct): placeholders until the app is in the stores. */
  getApp: string;
  getAppBody: string;
  comingSoon: string;
  /** The analytics banner (consent.ts): nothing from Google loads before a yes. */
  consentTitle: string;
  consentText: string;
  consentYes: string;
  consentNo: string;
  notInLang: string;
  readIn: string;
  notFound: string;
  error: string;
  errorText: string;
  skip: string;
  /** In the header of every page: the name "Outer News" and the "Official source" mark must not read as a government's (OGL v3: no official status). */
  independentNote: string;
  siteHeading: string;
  siteData: string;
  siteBanner: string;
  /** The ARB policy texts say "the app". */
  siteCovers: string;
  /** On translated policy pages; `{link}` is the English page. */
  prevails: string;
  /**
   * The filters' words (#67, #68), word for word from the app's ARB keys of
   * the same names (#87, feature/67-filters-app, after the chips prototype's
   * review, prototype/chips 3d88cf3, 16 Oct), which main does not have yet;
   * scripts/site-texts.check.mjs fails when a copy differs from an ARB file
   * that has the key. Whichever of #87 and #89 merges second moves them to
   * KEYS in scripts/site-texts.mjs, out of this file, and runs `npm run
   * site:texts` in server/. `filterAllCountries` is "All countries", the
   * Where chip and its menu's first item.
   */
  filterAllCountries: string;
  filterAllTopics: string;
  /** What a screen reader says for the Where chip, which shows only the country's code (GB). */
  filterCountryChip: string;
  /** The same for a group, whose chip shows its short name (ЄС, G7, G20, НАТО). */
  filterGroupChip: string;
  /** The European Union's chip: the EU's abbreviation in the language. NATO's chip is its name (GROUPS' names, the app's groupNato); G7 and G20 are written so in every language. */
  filterGroupEUShort: string;
  /** The same for the Topics chip, which shows only the topic's icon. */
  filterTopicChip: string;
  filterEmpty: string;
  filterShowAllCountries: string;
  filterShowAllTopics: string;
  /** The filter bar's name for screen readers (the site's own). */
  filters: string;
}

const SITE_TEXTS: Record<SiteLang, SiteTexts> = {
  en: {
    aiNotice:
      "Headlines and summaries are written by AI for Outer News ({publisher}) from the official text and are not reviewed by a person. They are not the official text and can contain mistakes: before you rely on one, read the original.",
    creditSource: "Source: {source}",
    published: "Published {date}",
    added: "In Outer News since {date}",
    originalTitle: "Original title",
    older: "Older decisions",
    latestLink: "Latest decisions",
    latest: "Latest",
    listTitle: "Official decisions",
    getApp: "Get the app",
    getAppBody: "Official decisions from around the world, in a few calm sentences, on your phone.",
    comingSoon: "Coming soon",
    consentTitle: "Analytics",
    consentText: "May we use Google Analytics to see how this site is used? It counts visits and what is read, sets cookies, and loads only if you allow it.",
    consentYes: "Allow",
    consentNo: "No, thanks",
    notInLang: "This decision is not available in this language yet.",
    readIn: "Read it in:",
    notFound: "Page not found",
    error: "Something went wrong",
    errorText: "Please try again in a minute.",
    skip: "Skip to content",
    independentNote: "Independent website, not affiliated with any government.",
    siteHeading: "On this website",
    siteData:
      "This website sets no cookies and runs no scripts, and everything on its pages comes from this website. Cloudflare, which hosts it, receives your IP address and basic technical details (such as the page address, browser and time) to deliver the page; your browser may also send Cloudflare an error report if a page fails to load. We can see request logs for up to 7 days to keep the site working; we do not use them to identify you.",
    siteBanner: "On iPhone and iPad, Safari may show a banner for our app, using information it loads from Apple's App Store.",
    siteCovers: "The privacy policy and the terms of use cover both the Outer News app and this website.",
    prevails: "The English version prevails ({link}).",
    filterAllCountries: "All countries",
    filterAllTopics: "All topics",
    filterCountryChip: "Country: {name}",
    filterGroupChip: "Countries: {name}",
    filterGroupEUShort: "EU",
    filterTopicChip: "Topic: {name}",
    filterEmpty: "No decisions here in the last 7 days.",
    filterShowAllCountries: "Show all countries",
    filterShowAllTopics: "Show all topics",
    filters: "Filters",
  },
  uk: {
    aiNotice:
      "Заголовки й стислі виклади пише ШІ для Outer News ({publisher}) на основі офіційного тексту, і людина їх не перевіряє. Вони не є офіційним текстом і можуть містити помилки: перш ніж покладатися на них, прочитайте оригінал.",
    creditSource: "Джерело: {source}",
    published: "Опубліковано {date}",
    added: "В Outer News з {date}",
    originalTitle: "Оригінальна назва",
    older: "Давніші рішення",
    latestLink: "Останні рішення",
    latest: "Останнє",
    listTitle: "Офіційні рішення",
    getApp: "Завантажте застосунок",
    getAppBody: "Офіційні рішення з усього світу кількома спокійними реченнями у вашому телефоні.",
    comingSoon: "Незабаром",
    consentTitle: "Аналітика",
    consentText: "Чи можемо ми використовувати Google Analytics, щоб бачити, як користуються сайтом? Він рахує відвідування й прочитане, ставить файли cookie і вмикається лише з вашого дозволу.",
    consentYes: "Дозволити",
    consentNo: "Ні, дякую",
    notInLang: "Цього рішення ще немає цією мовою.",
    readIn: "Читати:",
    notFound: "Сторінку не знайдено",
    error: "Щось пішло не так",
    errorText: "Спробуйте ще раз за хвилину.",
    skip: "Перейти до вмісту",
    independentNote: "Незалежний сайт, не пов’язаний із жодним урядом.",
    siteHeading: "На цьому сайті",
    siteData:
      "Цей сайт не встановлює файлів cookie і не запускає скриптів, а все на його сторінках завантажується з цього ж сайту. Cloudflare, де він розміщений, отримує вашу IP-адресу та базові технічні дані (як-от адресу сторінки, браузер і час), щоб показати сторінку; ваш браузер також може надіслати Cloudflare звіт про помилку, якщо сторінка не завантажилася. Ми бачимо журнали запитів до 7 днів, щоб сайт працював; ми не використовуємо їх, щоб вас ідентифікувати.",
    siteBanner: "На iPhone та iPad Safari може показати банер нашого застосунку з даними, які він завантажує з App Store від Apple.",
    siteCovers: "Політика конфіденційності й умови використання стосуються і застосунку Outer News, і цього сайту.",
    prevails: "Це переклад; у разі розбіжностей переважну силу має англійська версія ({link}).",
    filterAllCountries: "Усі країни",
    filterAllTopics: "Усі теми",
    filterCountryChip: "Країна: {name}",
    filterGroupChip: "Країни: {name}",
    filterGroupEUShort: "ЄС",
    filterTopicChip: "Тема: {name}",
    filterEmpty: "За останні 7 днів тут немає рішень.",
    filterShowAllCountries: "Показати всі країни",
    filterShowAllTopics: "Показати всі теми",
    filters: "Фільтри",
  },
  ru: {
    aiNotice:
      "Заголовки и краткие изложения пишет ИИ для Outer News ({publisher}) на основе официального текста, и человек их не проверяет. Они не являются официальным текстом и могут содержать ошибки: прежде чем полагаться на них, прочитайте оригинал.",
    creditSource: "Источник: {source}",
    published: "Опубликовано {date}",
    added: "В Outer News с {date}",
    originalTitle: "Оригинальное название",
    older: "Более ранние решения",
    latestLink: "Последние решения",
    latest: "Последние решения",
    listTitle: "Официальные решения",
    getApp: "Скачайте приложение",
    getAppBody: "Официальные решения со всего мира в нескольких спокойных предложениях в вашем телефоне.",
    comingSoon: "Скоро",
    consentTitle: "Аналитика",
    consentText: "Можно ли нам использовать Google Analytics, чтобы видеть, как пользуются сайтом? Он считает посещения и прочитанное, ставит файлы cookie и включается только с вашего разрешения.",
    consentYes: "Разрешить",
    consentNo: "Нет, спасибо",
    notInLang: "Этого решения пока нет на этом языке.",
    readIn: "Читать:",
    notFound: "Страница не найдена",
    error: "Что-то пошло не так",
    errorText: "Попробуйте ещё раз через минуту.",
    skip: "Перейти к содержимому",
    independentNote: "Независимый сайт, не связанный ни с одним правительством.",
    siteHeading: "На этом сайте",
    siteData:
      "Этот сайт не устанавливает файлы cookie и не запускает скрипты, а всё на его страницах загружается с этого же сайта. Cloudflare, где он размещён, получает ваш IP-адрес и базовые технические данные (например, адрес страницы, браузер и время), чтобы показать страницу; ваш браузер также может отправить Cloudflare отчёт об ошибке, если страница не загрузилась. Мы видим журналы запросов до 7 дней, чтобы сайт работал; мы не используем их, чтобы вас идентифицировать.",
    siteBanner: "На iPhone и iPad Safari может показать баннер нашего приложения с данными, которые он загружает из App Store от Apple.",
    siteCovers: "Политика конфиденциальности и условия использования относятся и к приложению Outer News, и к этому сайту.",
    prevails: "Это перевод; в случае расхождений преимущественную силу имеет английская версия ({link}).",
    filterAllCountries: "Все страны",
    filterAllTopics: "Все темы",
    filterCountryChip: "Страна: {name}",
    filterGroupChip: "Страны: {name}",
    filterGroupEUShort: "ЕС",
    filterTopicChip: "Тема: {name}",
    filterEmpty: "За последние 7 дней здесь нет решений.",
    filterShowAllCountries: "Показать все страны",
    filterShowAllTopics: "Показать все темы",
    filters: "Фильтры",
  },
  es: {
    aiNotice:
      "Los titulares y los resúmenes los escribe una IA para Outer News ({publisher}) a partir del texto oficial, y ninguna persona los revisa. No son el texto oficial y pueden contener errores: antes de fiarte de uno, lee el original.",
    creditSource: "Fuente: {source}",
    published: "Publicado el {date}",
    added: "En Outer News desde el {date}",
    originalTitle: "Título original",
    older: "Decisiones anteriores",
    latestLink: "Últimas decisiones",
    latest: "Lo último",
    listTitle: "Decisiones oficiales",
    getApp: "Descarga la app",
    getAppBody: "Decisiones oficiales de todo el mundo, en pocas frases serenas, en tu móvil.",
    comingSoon: "Próximamente",
    consentTitle: "Analítica",
    consentText: "¿Podemos usar Google Analytics para ver cómo se usa este sitio? Cuenta visitas y lo que se lee, usa cookies y solo se activa si lo permites.",
    consentYes: "Permitir",
    consentNo: "No, gracias",
    notInLang: "Esta decisión aún no está disponible en este idioma.",
    readIn: "Leer en:",
    notFound: "Página no encontrada",
    error: "Algo salió mal",
    errorText: "Vuelve a intentarlo en un minuto.",
    skip: "Saltar al contenido",
    independentNote: "Sitio web independiente, sin vínculo con ningún gobierno.",
    siteHeading: "En este sitio web",
    siteData:
      "Este sitio no usa cookies ni ejecuta scripts, y todo lo que aparece en sus páginas viene de este mismo sitio. Cloudflare, que lo aloja, recibe tu dirección IP y datos técnicos básicos (como la dirección de la página, el navegador y la hora) para mostrar la página; tu navegador también puede enviar a Cloudflare un informe de error si una página no carga. Vemos los registros de solicitudes durante un máximo de 7 días para que el sitio funcione; no los usamos para identificarte.",
    siteBanner: "En iPhone y iPad, Safari puede mostrar un banner de nuestra app con información que obtiene del App Store de Apple.",
    siteCovers: "La política de privacidad y los términos de uso se aplican tanto a la app Outer News como a este sitio web.",
    prevails: "Esto es una traducción; en caso de discrepancia, prevalece la versión en inglés ({link}).",
    filterAllCountries: "Todos los países",
    filterAllTopics: "Todos los temas",
    filterCountryChip: "País: {name}",
    filterGroupChip: "Países: {name}",
    filterGroupEUShort: "UE",
    filterTopicChip: "Tema: {name}",
    filterEmpty: "No hay decisiones aquí en los últimos 7 días.",
    filterShowAllCountries: "Mostrar todos los países",
    filterShowAllTopics: "Mostrar todos los temas",
    filters: "Filtros",
  },
  de: {
    aiNotice:
      "Überschriften und Zusammenfassungen schreibt eine KI für Outer News ({publisher}) auf Grundlage des offiziellen Textes, und kein Mensch prüft sie. Sie sind nicht der offizielle Text und können Fehler enthalten: Lesen Sie das Original, bevor Sie sich darauf verlassen.",
    creditSource: "Quelle: {source}",
    published: "Veröffentlicht am {date}",
    added: "Bei Outer News seit dem {date}",
    originalTitle: "Originaltitel",
    older: "Ältere Entscheidungen",
    latestLink: "Neueste Entscheidungen",
    latest: "Aktuell",
    listTitle: "Offizielle Entscheidungen",
    getApp: "Hol dir die App",
    getAppBody: "Offizielle Entscheidungen aus aller Welt, in wenigen ruhigen Sätzen, auf deinem Handy.",
    comingSoon: "Demnächst",
    consentTitle: "Analyse",
    consentText: "Dürfen wir Google Analytics nutzen, um zu sehen, wie diese Website genutzt wird? Es zählt Besuche und Gelesenes, setzt Cookies und lädt nur mit deiner Erlaubnis.",
    consentYes: "Erlauben",
    consentNo: "Nein, danke",
    notInLang: "Diese Entscheidung gibt es in dieser Sprache noch nicht.",
    readIn: "Lesen auf:",
    notFound: "Seite nicht gefunden",
    error: "Etwas ist schiefgelaufen",
    errorText: "Bitte versuchen Sie es in einer Minute erneut.",
    skip: "Zum Inhalt springen",
    independentNote: "Unabhängige Website ohne Verbindung zu einer Regierung.",
    siteHeading: "Auf dieser Website",
    siteData:
      "Diese Website setzt keine Cookies und führt keine Skripte aus; alles auf ihren Seiten kommt von dieser Website selbst. Cloudflare, wo sie gehostet wird, erhält Ihre IP-Adresse und grundlegende technische Angaben (etwa Seitenadresse, Browser und Uhrzeit), um die Seite auszuliefern; Ihr Browser kann Cloudflare außerdem einen Fehlerbericht senden, wenn eine Seite nicht lädt. Wir sehen die Anfrageprotokolle bis zu 7 Tage lang, damit die Website funktioniert; wir nutzen sie nicht, um Sie zu identifizieren.",
    siteBanner: "Auf iPhone und iPad kann Safari ein Banner für unsere App zeigen, mit Angaben, die es aus Apples App Store lädt.",
    siteCovers: "Die Datenschutzerklärung und die Nutzungsbedingungen gelten für die App Outer News und für diese Website.",
    prevails: "Dies ist eine Übersetzung; bei Abweichungen ist die englische Fassung maßgeblich ({link}).",
    filterAllCountries: "Alle Länder",
    filterAllTopics: "Alle Themen",
    filterCountryChip: "Land: {name}",
    filterGroupChip: "Länder: {name}",
    filterGroupEUShort: "EU",
    filterTopicChip: "Thema: {name}",
    filterEmpty: "In den letzten 7 Tagen gab es hier keine Entscheidungen.",
    filterShowAllCountries: "Alle Länder anzeigen",
    filterShowAllTopics: "Alle Themen anzeigen",
    filters: "Filter",
  },
};

export type TextKey = AppKey | keyof SiteTexts;

type Values = Record<string, string | Html>;

const template = (lang: SiteLang, key: TextKey): string =>
  key in SITE_TEXTS[lang] ? SITE_TEXTS[lang][key as keyof SiteTexts] : APP_TEXTS[lang][key as AppKey];

/**
 * A text with its `{name}` placeholders filled, as markup: the text and every
 * string value are escaped ("Contact & Support"), Html values (links) are kept.
 * A placeholder without a value stays as `{name}`, so the tests catch it.
 */
export function t(lang: SiteLang, key: TextKey, values: Values = {}): Html {
  const out = template(lang, key)
    .split(/(\{\w+\})/)
    .map((part) => {
      const name = /^\{(\w+)\}$/.exec(part)?.[1];
      const value = name === undefined ? undefined : values[name];
      if (value === undefined) return esc(part);
      return value instanceof Html ? value.value : esc(value);
    });
  return new Html(out.join(""));
}

/** The same as plain text, for `<title>` and attributes (escaped where it is put). */
export function text(lang: SiteLang, key: TextKey, values: Record<string, string> = {}): string {
  return template(lang, key).replace(/\{(\w+)\}/g, (part, name: string) => values[name] ?? part);
}

/** "RS Elite Pro s.r.o., Czech Republic" in the language, as the app says it. */
export const publisher = (lang: SiteLang) => text(lang, "publisher", { name: PUBLISHER_NAME });

/** The publisher with its seat, company ID and register file, as the app's privacy policy and terms say it. */
export const publisherDetails = (lang: SiteLang) => text(lang, "publisherDetails", { name: PUBLISHER_NAME, ...PUBLISHER_DETAILS });

/** The AI notice, which names us as the text's editor (see SiteTexts.aiNotice). */
export const aiNotice = (lang: SiteLang) => t(lang, "aiNotice", { publisher: PUBLISHER_NAME });
export const aiNoticeText = (lang: SiteLang) => text(lang, "aiNotice", { publisher: PUBLISHER_NAME });

const hasAppKey = (key: string): key is AppKey => key in APP_TEXTS.en;

/**
 * A country code's name, as the app shows it (countries.dart), else as the API
 * names it in GET /countries (COUNTRIES in api/filters.ts: the same names,
 * which a check keeps so, for a country the app's ARB files do not have yet);
 * an unknown code as it is.
 */
export function countryName(lang: SiteLang, code: string): string {
  const key = `country${code}`;
  return hasAppKey(key) ? APP_TEXTS[lang][key] : apiCountryName(code, lang);
}

/** A group's name, as GET /countries names it (GROUPS in api/filters.ts): "European Union", "G7", "НАТО". */
export const groupName = (lang: SiteLang, id: GroupId) => apiGroupName(GROUPS.find((g) => g.id === id)!, lang);

/**
 * A group's chip, short in the language, as the app's groupShortName: the
 * EU's abbreviation (EU, ЄС, ЕС, UE), the others their name, already short
 * (G7, G20; NATO, НАТО, OTAN), so the chip and its checked menu item agree.
 */
export const groupShort = (lang: SiteLang, id: GroupId) => (id === "eu" ? text(lang, "filterGroupEUShort") : groupName(lang, id));

/** A topic's name, as GET /topics names it (TOPIC_NAMES in api/filters.ts). */
export const topicName = (lang: SiteLang, topic: Topic) => TOPIC_NAMES[lang][topic];

/** A source language's name as it fills "translated from {language}" (languages.dart): an unknown code in capitals. */
export function languageName(lang: SiteLang, code: string): string {
  const key = `language${code.charAt(0).toUpperCase()}${code.slice(1)}`;
  return /^[a-z]{2}$/.test(code) && hasAppKey(key) ? APP_TEXTS[lang][key] : code.toUpperCase();
}

/** A decision type's label, as decision_types.dart: null for an unknown or missing type (no label). */
export function decisionLabel(lang: SiteLang, id: string | null): string | null {
  if (!id || !/^[a-z]+(-[a-z]+)*$/.test(id)) return null;
  const key = `decisionType${id
    .split("-")
    .map((w) => w[0].toUpperCase() + w.slice(1))
    .join("")}`;
  return hasAppKey(key) ? APP_TEXTS[lang][key] : null;
}

/**
 * The AI label, with the app's own rule (detail_screen.dart): "Summary by AI"
 * when the source is in the language the article is read in, otherwise
 * "Summary by AI · translated from German". The app reads a missing source
 * language as English.
 */
export function aiLabel(lang: SiteLang, originalLanguage: string | null): string {
  const source = originalLanguage ?? "en";
  return source === lang ? text(lang, "summaryByAi") : text(lang, "summaryByAiTranslated", { language: languageName(lang, source) });
}
