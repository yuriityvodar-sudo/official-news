// The site's words (#88). The app's texts come from its ARB files through
// app-texts.generated.ts, never copied; only what the app does not say is
// written here, in all 5 languages (TypeScript requires each one). The uk and
// ru texts need Yurii's review, es and de a native speaker's.
import { countryName as apiCountryName } from "../api/filters";
import { APP_TEXTS, type AppKey, LANGUAGE_NAMES, PUBLISHER_DETAILS, PUBLISHER_NAME, SITE_LANGS, type SiteLang } from "./app-texts.generated";
import { Html, esc } from "./html";

export { LANGUAGE_NAMES, SITE_LANGS, type SiteLang };

export const isSiteLang = (value: string): value is SiteLang => (SITE_LANGS as readonly string[]).includes(value);

interface SiteTexts {
  latestLink: string;
  /** The "Get the app" block above the footer (Yurii, 28 Oct): placeholders until the app is in the stores. */
  getApp: string;
  getAppBody: string;
  comingSoon: string;
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
}

const SITE_TEXTS: Record<SiteLang, SiteTexts> = {
  en: {
    latestLink: "Latest decisions",
    getApp: "Get the app",
    getAppBody: "Official decisions from around the world, in a few calm sentences, on your phone.",
    comingSoon: "Coming soon",
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
  },
  uk: {
    latestLink: "Останні рішення",
    getApp: "Завантажте застосунок",
    getAppBody: "Офіційні рішення з усього світу кількома спокійними реченнями у вашому телефоні.",
    comingSoon: "Незабаром",
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
  },
  ru: {
    latestLink: "Последние решения",
    getApp: "Скачайте приложение",
    getAppBody: "Официальные решения со всего мира в нескольких спокойных предложениях в вашем телефоне.",
    comingSoon: "Скоро",
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
  },
  es: {
    latestLink: "Últimas decisiones",
    getApp: "Descarga la app",
    getAppBody: "Decisiones oficiales de todo el mundo, en pocas frases serenas, en tu móvil.",
    comingSoon: "Próximamente",
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
  },
  de: {
    latestLink: "Neueste Entscheidungen",
    getApp: "Hol dir die App",
    getAppBody: "Offizielle Entscheidungen aus aller Welt, in wenigen ruhigen Sätzen, auf deinem Handy.",
    comingSoon: "Demnächst",
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
