// The latest list in a language (#88): what the app's feed shows, from the
// same API call: Top stories on the first page, then the latest 20, and
// "Older decisions" for the next page. Lists cover the API's 7 days; article
// pages stay (GET /articles/:id has no date limit). With the app's filters
// (#67, #68): a country (`/{lang}/{cc}`) and one topic (`?topic=`), chosen in
// the two menus under the title (filters.ts); paging, the language links and
// the alternates keep them.
import type { ApiArticle, ApiList } from "../data";
import { parseTime, publishedDate } from "../dates";
import { html } from "../html";
import { type Page, SITE_NAME } from "../layout";
import { SITE_LANGS, type SiteLang, aiNotice, countryName, decisionLabel, t, text } from "../texts";
import { type ListFilter, type OpenMenu, articlePath, listPath } from "../urls";
import { type Menus, filterBar, topicLabel, whereLabel } from "./filters";

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

/** Which list: its filters, its page (`before`, null for the first) and a menu to open. */
export interface ListView {
  filter: ListFilter;
  before: number | null;
  menu: OpenMenu | null;
}

/** What the API answered for it: the page, and on a first page what the menus offer. */
export interface ListData {
  list: ApiList;
  menus: Menus | null;
}

export function listPage(lang: SiteLang, origin: string, view: ListView, data: ListData): Page {
  const { filter, before } = view;
  const { list } = data;
  const next = nextBefore(list);
  const first = before === null;
  const filtered = filter.country !== null || filter.topic !== null;
  // A filtered list with nothing in it says so, with a way back to all countries and all topics (the app's _FilteredEmpty).
  const empty = filtered
    ? html`<p class="meta">${t(lang, "filterEmpty")}</p>
${filter.country ? html`<a class="more" href="${listPath(lang, { country: null, topic: filter.topic })}">${t(lang, "filterShowGlobal")}</a><br>` : ""}${
        filter.topic ? html`<a class="more" href="${listPath(lang, { country: filter.country, topic: null })}">${t(lang, "filterShowAllTopics")}</a>` : ""
      }`
    : lang === "en"
      ? html`<p class="meta">${t(lang, "feedEmpty")}</p>`
      : html`<p class="meta"><b>${t(lang, "feedNoTranslations")}</b><br>${t(lang, "feedTranslationsComing")}</p>`;
  const items = list.items.length ? html`<ol class="items">${list.items.map((a) => item(lang, a))}</ol>` : empty;
  // Page 1 has Top stories, then "Latest" (the app's sections); a later page is
  // one list under the title, with no heading that would repeat it (#88 review).
  const body = html`<h1 class="page-title">${t(lang, "listTitle")}</h1>
${filterBar(lang, filter, data.menus, view.menu)}
${list.items.length ? html`<p class="notice">${aiNotice(lang)}</p>` : ""}
${
  first && list.top.length
    ? html`<section aria-labelledby="top"><h2 class="section" id="top">${t(lang, "topStories")}</h2>
<ol class="items">${list.top.map((a) => item(lang, a))}</ol></section>`
    : ""
}
${first ? html`<section aria-labelledby="latest"><h2 class="section" id="latest">${t(lang, "latest")}</h2>
${items}
</section>` : items}
${next ? html`<a class="more" href="${listPath(lang, filter, next)}" rel="next">${t(lang, "older")} →</a><br>` : ""}
${first ? "" : html`<a class="more" href="${listPath(lang, filter)}">${t(lang, "latestLink")}</a>`}`;

  // "Germany · Economy · Latest decisions · Official News": the filters first, for tabs and history.
  const names = [filter.country ? whereLabel(lang, filter) : null, filter.topic ? topicLabel(lang, filter) : null].filter((n) => n !== null);
  // Every list exists in every language, as the app's language menu offers all
  // five (feed_language.dart); German is empty while it is off on the server.
  // The canonical and the alternates are the list without an open menu.
  return {
    lang,
    kind: "list",
    title: [...names, text(lang, "latestLink"), SITE_NAME].join(" · "),
    description: text(lang, "aboutIntro"),
    canonical: origin + listPath(lang, filter, before),
    alternates: [
      ...SITE_LANGS.map((l) => ({ hreflang: l, href: origin + listPath(l, filter, before) })),
      // The landing page chooses a language; a filtered or later page has no landing page of its own.
      { hreflang: "x-default", href: origin + (first && !filtered ? "/" : listPath("en", filter, before)) },
    ],
    switcher: SITE_LANGS.map((l) => ({ lang: l, path: listPath(l, filter, before) })),
    body,
  };
}
