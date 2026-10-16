// The site's words (#88). The app's texts come from its ARB files through
// app-texts.generated.ts, never copied; only what the app does not say is
// written here, in all 5 languages (TypeScript requires each one). The uk and
// ru texts need Yurii's review, es and de a native speaker's.
import { APP_TEXTS, type AppKey, LANGUAGE_NAMES, PUBLISHER_NAME, SITE_LANGS, type SiteLang } from "./app-texts.generated";
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
  /** The list page's h1; "Latest" (the app's own word) heads its section. */
  listTitle: string;
  notInLang: string;
  readIn: string;
  notFound: string;
  error: string;
  errorText: string;
  skip: string;
  /** In the header of every page: the name "Official News" and the "Official source" mark must not read as a government's (OGL v3: no official status). */
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
    aiNotice:
      "Headlines and summaries are written by AI for Official News ({publisher}) from the official text and are not reviewed by a person. They are not the official text and can contain mistakes: before you rely on one, read the original.",
    creditSource: "Source: {source}",
    published: "Published {date}",
    added: "In Official News since {date}",
    originalTitle: "Original title",
    older: "Older decisions",
    latestLink: "Latest decisions",
    listTitle: "Official decisions",
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
    siteCovers: "The privacy policy and the terms of use cover both the Official News app and this website.",
    prevails: "The English version prevails ({link}).",
  },
  uk: {
    aiNotice:
      "Заголовки й стислі виклади пише ШІ для Official News ({publisher}) на основі офіційного тексту, і людина їх не перевіряє. Вони не є офіційним текстом і можуть містити помилки: перш ніж покладатися на них, прочитайте оригінал.",
    creditSource: "Джерело: {source}",
    published: "Опубліковано {date}",
    added: "В Official News з {date}",
    originalTitle: "Оригінальна назва",
    older: "Давніші рішення",
    latestLink: "Останні рішення",
    listTitle: "Офіційні рішення",
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
    siteCovers: "Політика конфіденційності й умови використання стосуються і застосунку Official News, і цього сайту.",
    prevails: "Це переклад; у разі розбіжностей переважну силу має англійська версія ({link}).",
  },
  ru: {
    aiNotice:
      "Заголовки и краткие изложения пишет ИИ для Official News ({publisher}) на основе официального текста, и человек их не проверяет. Они не являются официальным текстом и могут содержать ошибки: прежде чем полагаться на них, прочитайте оригинал.",
    creditSource: "Источник: {source}",
    published: "Опубликовано {date}",
    added: "В Official News с {date}",
    originalTitle: "Оригинальное название",
    older: "Более ранние решения",
    latestLink: "Последние решения",
    listTitle: "Официальные решения",
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
    siteCovers: "Политика конфиденциальности и условия использования относятся и к приложению Official News, и к этому сайту.",
    prevails: "Это перевод; в случае расхождений преимущественную силу имеет английская версия ({link}).",
  },
  es: {
    aiNotice:
      "Los titulares y los resúmenes los escribe una IA para Official News ({publisher}) a partir del texto oficial, y ninguna persona los revisa. No son el texto oficial y pueden contener errores: antes de fiarte de uno, lee el original.",
    creditSource: "Fuente: {source}",
    published: "Publicado el {date}",
    added: "En Official News desde el {date}",
    originalTitle: "Título original",
    older: "Decisiones anteriores",
    latestLink: "Últimas decisiones",
    listTitle: "Decisiones oficiales",
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
    siteCovers: "La política de privacidad y los términos de uso se aplican tanto a la app Official News como a este sitio web.",
    prevails: "Esto es una traducción; en caso de discrepancia, prevalece la versión en inglés ({link}).",
  },
  de: {
    aiNotice:
      "Überschriften und Zusammenfassungen schreibt eine KI für Official News ({publisher}) auf Grundlage des offiziellen Textes, und kein Mensch prüft sie. Sie sind nicht der offizielle Text und können Fehler enthalten: Lesen Sie das Original, bevor Sie sich darauf verlassen.",
    creditSource: "Quelle: {source}",
    published: "Veröffentlicht am {date}",
    added: "Bei Official News seit dem {date}",
    originalTitle: "Originaltitel",
    older: "Ältere Entscheidungen",
    latestLink: "Neueste Entscheidungen",
    listTitle: "Offizielle Entscheidungen",
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
    siteCovers: "Die Datenschutzerklärung und die Nutzungsbedingungen gelten für die App Official News und für diese Website.",
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

/** "RS Elite Pro s.r.o., Slovakia" in the language, as the app says it. */
export const publisher = (lang: SiteLang) => text(lang, "publisher", { name: PUBLISHER_NAME });

/** The AI notice, which names us as the text's editor (see SiteTexts.aiNotice). */
export const aiNotice = (lang: SiteLang) => t(lang, "aiNotice", { publisher: PUBLISHER_NAME });
export const aiNoticeText = (lang: SiteLang) => text(lang, "aiNotice", { publisher: PUBLISHER_NAME });

const hasAppKey = (key: string): key is AppKey => key in APP_TEXTS.en;

/** A country code's name, as the app shows it (countries.dart): an unknown code as it is. */
export function countryName(lang: SiteLang, code: string): string {
  const key = `country${code}`;
  return hasAppKey(key) ? APP_TEXTS[lang][key] : code;
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
