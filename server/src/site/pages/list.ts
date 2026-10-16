// The latest list in a language (#88): what the app's feed shows, from the
// same API call: Top stories on the first page, then the latest 20, and
// "Older decisions" for the next page. Lists cover the API's 7 days; article
// pages stay (GET /articles/:id has no date limit).
import type { ApiArticle, ApiList } from "../data";
import { parseTime, publishedDate } from "../dates";
import { html } from "../html";
import { type Page, SITE_NAME } from "../layout";
import { SITE_LANGS, type SiteLang, countryName, decisionLabel, t, text } from "../texts";
import { articlePath, listPath } from "../urls";

function item(lang: SiteLang, article: ApiArticle) {
  const type = decisionLabel(lang, article.decisionType);
  const published = parseTime(article.publishedAt);
  const lead = article.shortSummary?.trim();
  return html`<li class="item">
${type ? html`<p class="kind">${type}</p>` : ""}<a class="title" href="${articlePath(lang, article)}">${article.headline ?? article.originalTitle}</a>
${lead ? html`<p>${lead}</p>` : ""}<p class="meta">${article.source.name} · ${countryName(lang, article.country)}${
    published ? html` · ${publishedDate(lang, published, article.dateOnly)}` : ""
  }</p>
</li>`;
}

/** The `before` of the next page: the last article's feedSeq, when the API says there is one. */
export const nextBefore = (list: ApiList) => (list.nextCursor ? (list.items.at(-1)?.feedSeq ?? null) : null);

export function listPage(lang: SiteLang, origin: string, before: number | null, list: ApiList): Page {
  const next = nextBefore(list);
  const first = before === null;
  const empty =
    lang === "en"
      ? html`<p class="meta">${t(lang, "feedEmpty")}</p>`
      : html`<p class="meta"><b>${t(lang, "feedNoTranslations")}</b><br>${t(lang, "feedTranslationsComing")}</p>`;
  const body = html`<h1 class="page-title">${t(lang, "latestLink")}</h1>
${list.items.length ? html`<p class="notice">${t(lang, "aiNotice")}</p>` : ""}
${
  first && list.top.length
    ? html`<section aria-labelledby="top"><h2 class="section" id="top">${t(lang, "topStories")}</h2>
<ol class="items">${list.top.map((a) => item(lang, a))}</ol></section>`
    : ""
}
<section aria-labelledby="latest"><h2 class="section" id="latest">${t(lang, "latest")}</h2>
${list.items.length ? html`<ol class="items">${list.items.map((a) => item(lang, a))}</ol>` : empty}
</section>
${next ? html`<a class="more" href="${listPath(lang, next)}" rel="next">${t(lang, "older")} →</a><br>` : ""}
${first ? "" : html`<a class="more" href="${listPath(lang)}">${t(lang, "latestLink")}</a>`}`;

  // Every list exists in every language, as the app's language menu offers all
  // five (feed_language.dart); German is empty while it is off on the server.
  return {
    lang,
    kind: "list",
    title: `${text(lang, "latestLink")} · ${SITE_NAME}`,
    description: text(lang, "aboutIntro"),
    canonical: origin + listPath(lang, before),
    alternates: [
      ...SITE_LANGS.map((l) => ({ hreflang: l, href: origin + listPath(l, before) })),
      // The landing page chooses a language; a later page has no landing page of its own.
      { hreflang: "x-default", href: origin + (first ? "/" : listPath("en", before)) },
    ],
    switcher: SITE_LANGS.map((l) => ({ lang: l, path: listPath(l, before) })),
    body,
  };
}
