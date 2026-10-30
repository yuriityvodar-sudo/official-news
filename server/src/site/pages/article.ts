// An article page (#88), in the order of the app's detail screen
// (detail_screen.dart): publisher, decision type, headline, the AI label right
// under it, the summary, the one AI notice (also the licences' change notice),
// the official link, then the credit line. The independence note is in every
// page's header, so it is not repeated here (#88 review). An event (#230) is
// shown as the app shows it: the country it concerns, "Event" in place of the
// official-source seal, and Wikipedia's words for the label, notice and link.
// Never the source's picture (imageUrl): a site makes public, permanent copies.
import { CREDITS } from "../credits.generated";
import type { ApiArticle } from "../data";
import { fullDate, isoTime, parseTime, publishedDate } from "../dates";
import { type Html, html, safeHttps, siteName } from "../html";
import { ARROW, type Alternate, type Page, SEAL, SITE_NAME, SPARKLE } from "../layout";
import { LANGUAGE_NAMES, SITE_LANGS, type SiteLang, aiLabel, aiNotice, countryName, decisionLabel, isEvent, placeCode, t, text } from "../texts";
import { articlePath } from "../urls";
import { articleJsonLd } from "../seo";

/** A language tag for `lang=""`: "de", "pt"; anything else is left out. */
const langTag = (value: string | null) => (value && /^[a-z]{2,3}$/.test(value) ? value : null);

/** The summary's paragraphs: the AI separates them with a blank line, as the app reads them. */
export const paragraphs = (summary: string) =>
  summary
    .split(/\n\s*\n/)
    .map((p) => p.trim())
    .filter(Boolean);

/** The languages an article is shown in, in the site's order. */
export const shownLanguages = (shown: Partial<Record<SiteLang, ApiArticle>>) => SITE_LANGS.filter((lang) => shown[lang]);

/** hreflang alternates: exactly the languages the API shows the article in, and x-default the English one. */
export function alternates(origin: string, shown: Partial<Record<SiteLang, ApiArticle>>): Alternate[] {
  const out: Alternate[] = shownLanguages(shown).map((lang) => ({ hreflang: lang, href: origin + articlePath(lang, shown[lang]!) }));
  if (shown.en) out.push({ hreflang: "x-default", href: origin + articlePath("en", shown.en) });
  return out;
}

/**
 * "Source: White House · Public domain", "Source: European Commission ·
 * © European Union, 1995-2026 · CC BY 4.0". A wording that names its licence
 * (the OGL's statement) is itself the licence link, so the licence is not said twice.
 */
function credit(lang: SiteLang, article: ApiArticle): Html {
  const row = CREDITS[article.source.id];
  const licenceUrl = safeHttps(row?.licenceUrl);
  const link = (label: string, attrs: Html | string = "") =>
    licenceUrl ? html`<a href="${licenceUrl}" rel="license"${attrs}>${label}</a>` : label;
  const wordingLang = html` lang="${row?.wordingLang ?? ""}"`;
  const namesLicence = !!(row?.wording && row.licence && row.wording.includes(row.licence));
  const parts: (Html | string)[] = [];
  if (row?.wording) parts.push(namesLicence ? link(row.wording, wordingLang) : html`<span${wordingLang}>${row.wording}</span>`);
  if (row?.licence && !namesLicence) parts.push(link(row.licence));
  return html`<p class="small">${t(lang, "creditSource", { source: article.source.name })}${parts.map((part) => html` · ${part}`)}</p>`;
}

/** The article page in `lang`, which the API shows it in. */
export function articlePage(lang: SiteLang, origin: string, shown: Partial<Record<SiteLang, ApiArticle>>): Page {
  const article = shown[lang]!;
  const aiText = article.headline !== null;
  const headline = article.headline ?? article.originalTitle;
  const summary = article.summary?.trim() ? paragraphs(article.summary) : [];
  const event = isEvent(article);
  const type = decisionLabel(lang, article.decisionType);
  const label = aiLabel(lang, article.originalLanguage, event);
  const place = placeCode(article);
  const published = parseTime(article.publishedAt);
  const added = parseTime(article.addedAt);
  const official = safeHttps(article.originalUrl);
  const original = langTag(article.originalLanguage);
  const lead = article.shortSummary?.trim() || null;

  const body = html`<article>
<div class="publisher"><span class="cc" aria-hidden="true">${place}</span><div><b>${article.source.name}</b>
<span class="meta">${countryName(lang, place)} · ${event ? t(lang, "decisionTypeEvent") : html`${SEAL} ${t(lang, "officialSource")}`}</span></div></div>
${type ? html`<p class="kind">${type}</p>` : ""}
<h1>${headline}</h1>
${aiText ? html`<p class="ai meta">${SPARKLE}<span>${label}</span></p>` : ""}
${published ? html`<p class="meta"><time datetime="${isoTime(published)}">${t(lang, "published", { date: publishedDate(lang, published, article.dateOnly) })}</time></p>` : ""}
${lead ? html`<p class="lead">${lead}</p>` : ""}
${
  summary.length
    ? html`<div class="body">${summary.map((p) => html`<p>${p.split("\n").map((line, i) => (i ? html`<br>${line}` : line))}</p>`)}</div>`
    : html`<p class="notice">${t(lang, "summaryComing")}</p>`
}
${aiText ? html`<p class="notice">${aiNotice(lang, event ? "event" : "decisions")}</p>` : ""}
${
  // An event's original title is its sentence, already summarized above (as the app).
  event ? "" : html`<p class="small">${t(lang, "originalTitle")}: <span${original ? html` lang="${original}"` : ""} dir="auto">${article.originalTitle}</span></p>`
}
${
  official
    ? html`<a class="official" href="${official}" rel="noopener"><span><b>${t(lang, event ? "readOnWikipedia" : "readOfficialDecision")}</b>
<span class="meta">${siteName(official)}</span></span>${ARROW}</a>`
    : ""
}
${credit(lang, article)}
${added ? html`<p class="small"><time datetime="${isoTime(added)}">${t(lang, "added", { date: fullDate(lang, added) })}</time></p>` : ""}
</article>
${articleJsonLd(lang, origin, article)}`;

  // Link previews show these: they are AI text, so they say so (AI Act Art. 50).
  const description = `${text(lang, "summaryByAi")}: ${lead ?? headline}`;
  const languages = shownLanguages(shown);
  return {
    lang,
    kind: "article",
    // Every article is indexed (Yurii, 29 Oct).
    index: true,
    title: `${headline} · ${SITE_NAME}`,
    // iMessage and the iOS share sheet show only the title and the host, no description (LPLinkMetadata).
    ogTitle: aiText ? `${headline} · ${text(lang, "summaryByAi")}` : undefined,
    description: aiText ? description : headline,
    canonical: origin + articlePath(lang, article),
    alternates: alternates(origin, shown),
    switcher: languages.map((l) => ({ lang: l, path: articlePath(l, shown[l]!) })),
    ogType: "article",
    body,
  };
}

/** The 404 for an article the API shows, but not in `lang` (not yet, or its translation failed): where it can be read. */
export function notInLanguagePage(lang: SiteLang, shown: Partial<Record<SiteLang, ApiArticle>>): Page {
  const languages = shownLanguages(shown);
  const links = languages.map((l) => {
    const a = shown[l]!;
    return html`<li><a href="${articlePath(l, a)}" hreflang="${l}" lang="${l}"><span>${a.headline ?? a.originalTitle}</span><span class="meta">${LANGUAGE_NAMES[l].nativeName}</span></a></li>`;
  });
  const aiText = languages.some((l) => shown[l]!.headline !== null);
  const event = isEvent(shown[languages[0]]!);
  const title = event ? "notInLangEvent" : "notInLang";
  return {
    lang,
    kind: "not-in-language",
    title: `${text(lang, title)} · ${SITE_NAME}`,
    switcher: languages.map((l) => ({ lang: l, path: articlePath(l, shown[l]!) })),
    body: html`<div class="info"><h1 class="page-title">${t(lang, title)}</h1>
<p>${t(lang, "readIn")}</p>
<ul class="choose">${links}</ul>
${aiText ? html`<p class="notice">${aiNotice(lang, event ? "event" : "decisions")}</p>` : ""}</div>`,
  };
}

