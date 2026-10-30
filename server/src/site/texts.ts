// The site's words (#88). The app's texts come from its ARB files through
// app-texts.generated.ts, never copied; only what the app does not say is
// written here, in all 5 languages (TypeScript requires each one). The uk and
// ru texts need Yurii's review, es and de a native speaker's.
import { countryName as apiCountryName, hasCountryName } from "../api/filters";
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
  /** The AI notice on an event's page (#230): from Wikipedia's text, which is not an official one. */
  aiNoticeEvent: string;
  /** The AI notice on a list that has events among its decisions (#230). */
  aiNoticeWithEvents: string;
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
  /** The cookie notice (consent.ts; Yurii, 30 Oct: a general message, Details is the privacy policy): nothing from Google loads before Accept. */
  consentTitle: string;
  consentText: string;
  consentYes: string;
  consentDetails: string;
  notInLang: string;
  /** The not-in-language page of an event (#230). */
  notInLangEvent: string;
  readIn: string;
  notFound: string;
  error: string;
  errorText: string;
  skip: string;
  /** In the header of every page: the name "Outer News" and the "Official source" mark must not read as a government's (OGL v3: no official status). */
  independentNote: string;
  siteHeading: string;
  siteData: string;
  /** Google Analytics on the website, after Accept (Roman's review of #240). */
  siteAnalytics: string;
  siteBanner: string;
  /** The footer's way to withdraw (consent.ts). */
  cookieSettings: string;
  /** The ARB policy texts say "the app". */
  siteCovers: string;
  /** On translated policy pages; `{link}` is the English page. */
  prevails: string;
  /** The Support page; `{email}` is the support address (the app writes from its own screen). */
  emailUs: string;
}

const SITE_TEXTS: Record<SiteLang, SiteTexts> = {
  en: {
    aiNotice:
      "Headlines and summaries are written by AI for Outer News ({publisher}) from the official text and are not reviewed by a person. They are not the official text and can contain mistakes: before you rely on one, read the original.",
    aiNoticeEvent:
      "Headlines and summaries are written by AI for Outer News ({publisher}) from Wikipedia's text and are not reviewed by a person. They can contain mistakes: before you rely on one, read the original.",
    aiNoticeWithEvents:
      "Headlines and summaries are written by AI for Outer News ({publisher}) from the official text, or for events from Wikipedia's text, and are not reviewed by a person. They are not the official text and can contain mistakes: before you rely on one, read the original.",
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
    consentTitle: "Cookies",
    consentText: "We use cookies to give you a better experience on Outer News.",
    consentYes: "OK",
    consentDetails: "Details",
    notInLang: "This decision is not available in this language yet.",
    notInLangEvent: "This event is not available in this language yet.",
    readIn: "Read it in:",
    notFound: "Page not found",
    error: "Something went wrong",
    errorText: "Please try again in a minute.",
    skip: "Skip to content",
    independentNote: "Independent website, not affiliated with any government.",
    siteHeading: "On this website",
    siteData:
      "Cloudflare, which hosts this website, receives your IP address and basic technical details (such as the page address, browser and time) to deliver the page; your browser may also send Cloudflare an error report if a page fails to load. We can see request logs for up to 7 days to keep the site working; we do not use them to identify you.",
    siteAnalytics: "With your yes in the cookie notice, this website uses Google Analytics, a service of Google, to count visits and see which pages are read, how far they are scrolled and which links lead out. It sets the cookies _ga and _ga_D0H8XW2SWJ, kept for up to 2 years, and the data goes to Google, which may process it outside the EU. Nothing from Google loads before you accept. To withdraw, tap Cookie settings at the bottom of any page: it deletes these cookies and asks again.",
    siteBanner: "On iPhone and iPad, Safari may show a banner for our app, using information it loads from Apple's App Store.",
    cookieSettings: "Cookie settings",
    siteCovers: "The privacy policy and the terms of use cover both the Outer News app and this website.",
    prevails: "The English version prevails ({link}).",
    emailUs: "Write to us at {email}.",
  },
  uk: {
    aiNotice:
      "Заголовки й стислі виклади пише ШІ для Outer News ({publisher}) на основі офіційного тексту, і людина їх не перевіряє. Вони не є офіційним текстом і можуть містити помилки: перш ніж покладатися на них, прочитайте оригінал.",
    aiNoticeEvent:
      "Заголовки й стислі виклади пише ШІ для Outer News ({publisher}) на основі тексту Вікіпедії, і людина їх не перевіряє. Вони можуть містити помилки: перш ніж покладатися на них, прочитайте оригінал.",
    aiNoticeWithEvents:
      "Заголовки й стислі виклади пише ШІ для Outer News ({publisher}) на основі офіційного тексту, а для подій — тексту Вікіпедії, і людина їх не перевіряє. Вони не є офіційним текстом і можуть містити помилки: перш ніж покладатися на них, прочитайте оригінал.",
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
    consentTitle: "Файли cookie",
    consentText: "Ми використовуємо файли cookie, щоб зробити Outer News зручнішим для вас.",
    consentYes: "OK",
    consentDetails: "Докладніше",
    notInLang: "Цього рішення ще немає цією мовою.",
    notInLangEvent: "Цієї події ще немає цією мовою.",
    readIn: "Читати:",
    notFound: "Сторінку не знайдено",
    error: "Щось пішло не так",
    errorText: "Спробуйте ще раз за хвилину.",
    skip: "Перейти до вмісту",
    independentNote: "Незалежний сайт, не пов’язаний із жодним урядом.",
    siteHeading: "На цьому сайті",
    siteData:
      "Cloudflare, де розміщено цей сайт, отримує вашу IP-адресу та базові технічні дані (як-от адресу сторінки, браузер і час), щоб показати сторінку; ваш браузер також може надіслати Cloudflare звіт про помилку, якщо сторінка не завантажилася. Ми бачимо журнали запитів до 7 днів, щоб сайт працював; ми не використовуємо їх, щоб вас ідентифікувати.",
    siteAnalytics: "Якщо ви погодитеся в повідомленні про cookie, цей сайт використовує Google Analytics, сервіс Google, щоб рахувати відвідування й бачити, які сторінки читають, наскільки їх прокручують і за якими посиланнями переходять на інші сайти. Він встановлює файли cookie _ga і _ga_D0H8XW2SWJ, які зберігаються до 2 років, а дані надходять до Google, який може обробляти їх за межами ЄС. До вашої згоди нічого від Google не завантажується. Щоб відкликати згоду, натисніть «Налаштування cookie» внизу будь-якої сторінки: це видалить ці файли cookie і запитає знову.",
    siteBanner: "На iPhone та iPad Safari може показати банер нашого застосунку з даними, які він завантажує з App Store від Apple.",
    cookieSettings: "Налаштування cookie",
    siteCovers: "Політика конфіденційності й умови використання стосуються і застосунку Outer News, і цього сайту.",
    prevails: "Це переклад; у разі розбіжностей переважну силу має англійська версія ({link}).",
    emailUs: "Пишіть нам на {email}.",
  },
  ru: {
    aiNotice:
      "Заголовки и краткие изложения пишет ИИ для Outer News ({publisher}) на основе официального текста, и человек их не проверяет. Они не являются официальным текстом и могут содержать ошибки: прежде чем полагаться на них, прочитайте оригинал.",
    aiNoticeEvent:
      "Заголовки и краткие изложения пишет ИИ для Outer News ({publisher}) на основе текста Википедии, и человек их не проверяет. Они могут содержать ошибки: прежде чем полагаться на них, прочитайте оригинал.",
    aiNoticeWithEvents:
      "Заголовки и краткие изложения пишет ИИ для Outer News ({publisher}) на основе официального текста, а для событий — текста Википедии, и человек их не проверяет. Они не являются официальным текстом и могут содержать ошибки: прежде чем полагаться на них, прочитайте оригинал.",
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
    consentTitle: "Файлы cookie",
    consentText: "Мы используем файлы cookie, чтобы сделать Outer News удобнее для вас.",
    consentYes: "OK",
    consentDetails: "Подробнее",
    notInLang: "Этого решения пока нет на этом языке.",
    notInLangEvent: "Этого события пока нет на этом языке.",
    readIn: "Читать:",
    notFound: "Страница не найдена",
    error: "Что-то пошло не так",
    errorText: "Попробуйте ещё раз через минуту.",
    skip: "Перейти к содержимому",
    independentNote: "Независимый сайт, не связанный ни с одним правительством.",
    siteHeading: "На этом сайте",
    siteData:
      "Cloudflare, где размещён этот сайт, получает ваш IP-адрес и базовые технические данные (например, адрес страницы, браузер и время), чтобы показать страницу; ваш браузер также может отправить Cloudflare отчёт об ошибке, если страница не загрузилась. Мы видим журналы запросов до 7 дней, чтобы сайт работал; мы не используем их, чтобы вас идентифицировать.",
    siteAnalytics: "Если вы согласитесь в уведомлении о cookie, этот сайт использует Google Analytics, сервис Google, чтобы считать посещения и видеть, какие страницы читают, насколько их прокручивают и по каким ссылкам переходят на другие сайты. Он устанавливает файлы cookie _ga и _ga_D0H8XW2SWJ, которые хранятся до 2 лет, а данные поступают в Google, который может обрабатывать их за пределами ЕС. До вашего согласия ничего от Google не загружается. Чтобы отозвать согласие, нажмите «Настройки cookie» внизу любой страницы: это удалит эти файлы cookie и спросит снова.",
    siteBanner: "На iPhone и iPad Safari может показать баннер нашего приложения с данными, которые он загружает из App Store от Apple.",
    cookieSettings: "Настройки cookie",
    siteCovers: "Политика конфиденциальности и условия использования относятся и к приложению Outer News, и к этому сайту.",
    prevails: "Это перевод; в случае расхождений преимущественную силу имеет английская версия ({link}).",
    emailUs: "Пишите нам на {email}.",
  },
  es: {
    aiNotice:
      "Los titulares y los resúmenes los escribe una IA para Outer News ({publisher}) a partir del texto oficial, y ninguna persona los revisa. No son el texto oficial y pueden contener errores: antes de fiarte de uno, lee el original.",
    aiNoticeEvent:
      "Los titulares y los resúmenes los escribe una IA para Outer News ({publisher}) a partir del texto de Wikipedia, y ninguna persona los revisa. Pueden contener errores: antes de fiarte de uno, lee el original.",
    aiNoticeWithEvents:
      "Los titulares y los resúmenes los escribe una IA para Outer News ({publisher}) a partir del texto oficial o, en los acontecimientos, del texto de Wikipedia, y ninguna persona los revisa. No son el texto oficial y pueden contener errores: antes de fiarte de uno, lee el original.",
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
    consentTitle: "Cookies",
    consentText: "Usamos cookies para ofrecerte una mejor experiencia en Outer News.",
    consentYes: "OK",
    consentDetails: "Detalles",
    notInLang: "Esta decisión aún no está disponible en este idioma.",
    notInLangEvent: "Este acontecimiento aún no está disponible en este idioma.",
    readIn: "Leer en:",
    notFound: "Página no encontrada",
    error: "Algo salió mal",
    errorText: "Vuelve a intentarlo en un minuto.",
    skip: "Saltar al contenido",
    independentNote: "Sitio web independiente, sin vínculo con ningún gobierno.",
    siteHeading: "En este sitio web",
    siteData:
      "Cloudflare, que aloja este sitio, recibe tu dirección IP y datos técnicos básicos (como la dirección de la página, el navegador y la hora) para mostrar la página; tu navegador también puede enviar a Cloudflare un informe de error si una página no carga. Vemos los registros de solicitudes durante un máximo de 7 días para que el sitio funcione; no los usamos para identificarte.",
    siteAnalytics: "Si aceptas en el aviso de cookies, este sitio usa Google Analytics, un servicio de Google, para contar visitas y ver qué páginas se leen, hasta dónde se desplazan y qué enlaces llevan fuera. Usa las cookies _ga y _ga_D0H8XW2SWJ, que se guardan hasta 2 años, y los datos van a Google, que puede tratarlos fuera de la UE. Nada de Google se carga antes de que aceptes. Para retirar tu consentimiento, toca Configuración de cookies al pie de cualquier página: borra estas cookies y vuelve a preguntar.",
    siteBanner: "En iPhone y iPad, Safari puede mostrar un banner de nuestra app con información que obtiene del App Store de Apple.",
    cookieSettings: "Configuración de cookies",
    siteCovers: "La política de privacidad y los términos de uso se aplican tanto a la app Outer News como a este sitio web.",
    prevails: "Esto es una traducción; en caso de discrepancia, prevalece la versión en inglés ({link}).",
    emailUs: "Escríbenos a {email}.",
  },
  de: {
    aiNotice:
      "Überschriften und Zusammenfassungen schreibt eine KI für Outer News ({publisher}) auf Grundlage des offiziellen Textes, und kein Mensch prüft sie. Sie sind nicht der offizielle Text und können Fehler enthalten: Lesen Sie das Original, bevor Sie sich darauf verlassen.",
    aiNoticeEvent:
      "Überschriften und Zusammenfassungen schreibt eine KI für Outer News ({publisher}) auf Grundlage des Wikipedia-Textes, und kein Mensch prüft sie. Sie können Fehler enthalten: Lesen Sie das Original, bevor Sie sich darauf verlassen.",
    aiNoticeWithEvents:
      "Überschriften und Zusammenfassungen schreibt eine KI für Outer News ({publisher}) auf Grundlage des offiziellen Textes, bei Ereignissen des Wikipedia-Textes, und kein Mensch prüft sie. Sie sind nicht der offizielle Text und können Fehler enthalten: Lesen Sie das Original, bevor Sie sich darauf verlassen.",
    creditSource: "Quelle: {source}",
    published: "Veröffentlicht am {date}",
    added: "Bei Outer News seit dem {date}",
    originalTitle: "Originaltitel",
    older: "Ältere Entscheidungen",
    latestLink: "Neueste Entscheidungen",
    latest: "Aktuell",
    listTitle: "Offizielle Entscheidungen",
    getApp: "Laden Sie die App",
    getAppBody: "Offizielle Entscheidungen aus aller Welt, in wenigen ruhigen Sätzen, auf Ihrem Handy.",
    comingSoon: "Demnächst",
    consentTitle: "Cookies",
    consentText: "Wir verwenden Cookies, um Ihnen ein besseres Erlebnis auf Outer News zu bieten.",
    consentYes: "OK",
    consentDetails: "Details",
    notInLang: "Diese Entscheidung gibt es in dieser Sprache noch nicht.",
    notInLangEvent: "Dieses Ereignis gibt es in dieser Sprache noch nicht.",
    readIn: "Lesen auf:",
    notFound: "Seite nicht gefunden",
    error: "Etwas ist schiefgelaufen",
    errorText: "Bitte versuchen Sie es in einer Minute erneut.",
    skip: "Zum Inhalt springen",
    independentNote: "Unabhängige Website ohne Verbindung zu einer Regierung.",
    siteHeading: "Auf dieser Website",
    siteData:
      "Cloudflare, wo diese Website gehostet wird, erhält Ihre IP-Adresse und grundlegende technische Angaben (etwa Seitenadresse, Browser und Uhrzeit), um die Seite auszuliefern; Ihr Browser kann Cloudflare außerdem einen Fehlerbericht senden, wenn eine Seite nicht lädt. Wir sehen die Anfrageprotokolle bis zu 7 Tage lang, damit die Website funktioniert; wir nutzen sie nicht, um Sie zu identifizieren.",
    siteAnalytics: "Wenn Sie im Cookie-Hinweis zustimmen, nutzt diese Website Google Analytics, einen Dienst von Google, um Besuche zu zählen und zu sehen, welche Seiten gelesen werden, wie weit sie gescrollt werden und welche Links nach außen führen. Sie setzt die Cookies _ga und _ga_D0H8XW2SWJ, die bis zu 2 Jahre gespeichert werden, und die Daten gehen an Google, das sie auch außerhalb der EU verarbeiten kann. Vor Ihrer Zustimmung lädt nichts von Google. Um die Einwilligung zu widerrufen, tippen Sie unten auf jeder Seite auf Cookie-Einstellungen: Das löscht diese Cookies und fragt erneut.",
    siteBanner: "Auf iPhone und iPad kann Safari ein Banner für unsere App zeigen, mit Angaben, die es aus Apples App Store lädt.",
    cookieSettings: "Cookie-Einstellungen",
    siteCovers: "Die Datenschutzerklärung und die Nutzungsbedingungen gelten für die App Outer News und für diese Website.",
    prevails: "Dies ist eine Übersetzung; bei Abweichungen ist die englische Fassung maßgeblich ({link}).",
    emailUs: "Schreiben Sie uns an {email}.",
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

/** Whose text the AI wrote from: official ones, Wikipedia's for an event (#230), or both on a list with events. */
export type NoticeOf = "decisions" | "event" | "both";
const NOTICE_KEYS = { decisions: "aiNotice", event: "aiNoticeEvent", both: "aiNoticeWithEvents" } as const;

/** The AI notice, which names us as the text's editor (see SiteTexts.aiNotice). */
export const aiNotice = (lang: SiteLang, of: NoticeOf = "decisions") => t(lang, NOTICE_KEYS[of], { publisher: PUBLISHER_NAME });
export const aiNoticeText = (lang: SiteLang, of: NoticeOf = "decisions") => text(lang, NOTICE_KEYS[of], { publisher: PUBLISHER_NAME });

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

/** An event from Wikipedia's current events, not an official decision (#230), as the app's `Article.isEvent`. */
export const isEvent = (article: { decisionType: string | null }) => article.decisionType === "event";

/**
 * The country a card or an article names, as the app's `placeName`
 * (countries.dart, #230): the source's; for an event, whose source is the
 * whole world (WW), the country it concerns most, or the world when there is
 * no name for it.
 */
export function placeCode(article: { country: string; countries: string[]; decisionType: string | null }): string {
  const main = isEvent(article) ? article.countries[0] : undefined;
  return main && (hasAppKey(`country${main}`) || hasCountryName(main)) ? main : article.country;
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
 * language as English. An event's says it is of Wikipedia's text (#230).
 */
export function aiLabel(lang: SiteLang, originalLanguage: string | null, event = false): string {
  const source = originalLanguage ?? "en";
  if (source === lang) return text(lang, event ? "summaryByAiOfWikipedia" : "summaryByAi");
  return text(lang, event ? "summaryByAiOfWikipediaTranslated" : "summaryByAiTranslated", { language: languageName(lang, source) });
}
