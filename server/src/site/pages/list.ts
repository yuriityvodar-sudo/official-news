// The latest list in a language (#88): what the app's feed shows, from the
// same API call: Top stories on the first page, then the latest 20 without
// the Top stories above them (as the app's feed_screen.dart; #89 review), and
// "Older decisions" for the next page. Lists cover the API's 7 days; article
// pages stay (GET /articles/:id has no date limit).
import type { ApiArticle, ApiList } from "../data";
import { fullDate, parseTime, publishedDate } from "../dates";
import { html } from "../html";
import { type Page, SITE_NAME } from "../layout";
import { SITE_LANGS, type SiteLang, aiNotice, countryName, decisionLabel, isEvent, placeCode, t, text } from "../texts";
import { articlePath, listPath } from "../urls";

function item(lang: SiteLang, article: ApiArticle) {
  const type = decisionLabel(lang, article.decisionType);
  const published = parseTime(article.publishedAt);
  const lead = article.shortSummary?.trim();
  return html`<li class="item">
${type ? html`<p class="kind">${type}</p>` : ""}<a class="title" href="${articlePath(lang, article)}">${article.headline ?? article.originalTitle}</a>
${lead ? html`<p>${lead}</p>` : ""}<p class="meta">${article.source.name} · ${countryName(lang, placeCode(article))}${
    published ? html` · ${publishedDate(lang, published, article.dateOnly)}` : ""
  }</p>
</li>`;
}

/** The front page's lead (design 1a, Yurii 28 Oct): the first top story, big, with its short summary. */
function leadStory(lang: SiteLang, article: ApiArticle) {
  const type = decisionLabel(lang, article.decisionType);
  const published = parseTime(article.publishedAt);
  const dek = article.shortSummary?.trim();
  return html`<article class="leadstory">
${type ? html`<p class="kind">${type}</p>` : ""}<a class="title" href="${articlePath(lang, article)}">${article.headline ?? article.originalTitle}</a>
${dek ? html`<p class="dek">${dek}</p>` : ""}<p class="meta">${article.source.name} · ${countryName(lang, placeCode(article))}${
    published ? html` · ${publishedDate(lang, published, article.dateOnly)}` : ""
  }</p>
</article>`;
}

/** When, in a stream row: the time (UTC) for today's decisions, else the day ("16.10"). */
function when(article: ApiArticle, today: string): string {
  const date = parseTime(article.publishedAt);
  if (!date) return "";
  const iso = date.toISOString();
  if (!article.dateOnly && iso.slice(0, 10) === today) return iso.slice(11, 16);
  return `${iso.slice(8, 10)}.${iso.slice(5, 7)}`;
}

/** A row of the front page's Latest column: when, then the decision's kind, headline and source. */
function streamItem(lang: SiteLang, article: ApiArticle, today: string) {
  const type = decisionLabel(lang, article.decisionType);
  return html`<li class="item row"><span class="when">${when(article, today)}</span><div>
${type ? html`<p class="kind">${type}</p>` : ""}<a class="title" href="${articlePath(lang, article)}">${article.headline ?? article.originalTitle}</a>
<p class="meta">${article.source.name} · ${countryName(lang, placeCode(article))}</p>
</div></li>`;
}

/** A card of the grid under the top part (design 1b's grid, Yurii 28 Oct): the first one wide, with its short summary. */
function card(lang: SiteLang, article: ApiArticle, today: string, wide: boolean) {
  const type = decisionLabel(lang, article.decisionType);
  const dek = wide ? article.shortSummary?.trim() : undefined;
  const at = when(article, today);
  return html`<li class="card${wide ? " wide" : ""}">
${type ? html`<p class="kind">${type}</p>` : ""}<a class="title" href="${articlePath(lang, article)}">${article.headline ?? article.originalTitle}</a>
${dek ? html`<p class="dek">${dek}</p>` : ""}<p class="meta">${article.source.name} · ${countryName(lang, placeCode(article))}${at ? ` · ${at}` : ""}</p>
</li>`;
}

/** How many decisions the Latest column holds, and the grid under it (one wide and one, then three: Yurii, 28 Oct, "not too many"). The rest of the page follows as a compact list. */
const COLUMN = 6;
const GRID = 5;

/** The `before` of the next page: the last article's feedSeq, when the API says there is one. */
export const nextBefore = (list: ApiList) => (list.nextCursor ? (list.items.at(-1)?.feedSeq ?? null) : null);

/** Which list: its page (`before`, null for the first). */
export interface ListView {
  before: number | null;
}

/** What the API answered for it: the page. */
export interface ListData {
  list: ApiList;
}

export function listPage(lang: SiteLang, origin: string, view: ListView, data: ListData): Page {
  const { before } = view;
  const { list } = data;
  const next = nextBefore(list);
  const first = before === null;
  const empty =
    lang === "en"
      ? html`<p class="meta">${t(lang, "feedEmpty")}</p>`
      : html`<p class="meta"><b>${t(lang, "feedNoTranslations")}</b><br>${t(lang, "feedTranslationsComing")}</p>`;
  // Page 1's Latest leaves out the Top stories above it, so a short list does
  // not show each decision twice; the next page still starts after
  // the API's whole page (nextBefore). Nothing left: no Latest at all, as the app.
  const topIds = new Set(first ? list.top.map((a) => a.id) : []);
  const latest = list.items.filter((a) => !topIds.has(a.id));
  const items = list.items.length ? (latest.length ? html`<ol class="items">${latest.map((a) => item(lang, a))}</ol>` : "") : empty;
  // Page 1 is design 1a (Yurii, 28 Oct): the lead on the left (the first top
  // story, or the first decision when there are none), the other top stories
  // under it, and the Latest column on the right, by time; on a phone one
  // column, lead first. A later page is one list under the title, with no
  // heading that would repeat it (#88 review).
  const today = new Date().toISOString().slice(0, 10);
  const lead = first ? (list.top[0] ?? latest[0]) : undefined;
  const moreTop = first ? list.top.slice(1) : [];
  const stream = lead && !list.top.length ? latest.slice(1) : latest;
  // The AI's text is of official pages, and of Wikipedia's for events (#230).
  const notice = html`<p class="notice">${aiNotice(lang, [...list.top, ...list.items].some(isEvent) ? "both" : "decisions")}</p>`;
  const head = html`<div class="front-head"><h1 class="page-title">${t(lang, "listTitle")}</h1></div>`;
  const older = next ? html`<a class="more" href="${listPath(lang, next)}" rel="next">${t(lang, "older")} →</a><br>` : "";
  const body = lead
    ? html`${head}
<div class="front">
${
  list.top.length
    ? html`<section class="lead-col" aria-labelledby="top"><h2 class="vh" id="top">${t(lang, "topStoriesTitle")}</h2>`
    : html`<section class="lead-col" aria-labelledby="lead"><h2 class="vh" id="lead">${t(lang, "latest")}</h2>`
}
${leadStory(lang, lead)}
${notice}
${moreTop.length ? html`<ol class="items">${moreTop.map((a) => item(lang, a))}</ol>` : ""}
</section>
${stream.length ? html`<section class="latest-col" aria-labelledby="latest"><div class="latest-head"><h2 class="section" id="latest">${t(lang, "latest")}</h2><span class="meta">${fullDate(lang, new Date())}</span></div>
<ol class="items">${stream.slice(0, COLUMN).map((a) => streamItem(lang, a, today))}</ol>
</section>` : ""}
</div>
${stream.length > COLUMN ? html`<ol class="cards" aria-label="${t(lang, "latest")}">${stream.slice(COLUMN, COLUMN + GRID).map((a, i) => card(lang, a, today, i === 0))}</ol>` : ""}
${stream.length > COLUMN + GRID ? html`<ol class="items more-rows" aria-label="${t(lang, "latest")}">${stream.slice(COLUMN + GRID).map((a) => streamItem(lang, a, today))}</ol>` : ""}
${older}`
    : html`<h1 class="page-title">${t(lang, "listTitle")}</h1>
${list.items.length ? notice : ""}
${items}
${older}
${first ? "" : html`<a class="more" href="${listPath(lang)}">${t(lang, "latestLink")}</a>`}`;

  // Every list exists in every language, as the app's language menu offers all
  // five (feed_language.dart); German is empty while it is off on the server.
  return {
    lang,
    kind: "list",
    // A later page repeats what the first page links; an empty list (German
    // while it is off) has nothing to find.
    index: first && list.items.length > 0,
    // The front page leads with the name, "Outer News · Official decisions" (Yurii, 29 Oct).
    title: first ? `${SITE_NAME} · ${text(lang, "listTitle")}` : [text(lang, "latestLink"), SITE_NAME].join(" · "),
    description: text(lang, "aboutIntro"),
    canonical: origin + listPath(lang, before),
    alternates: [
      ...SITE_LANGS.map((l) => ({ hreflang: l, href: origin + listPath(l, before) })),
      // `/` picks the visitor's language (lang.ts); a later page has no such address of its own.
      { hreflang: "x-default", href: origin + (first ? "/" : listPath("en", before)) },
    ],
    switcher: SITE_LANGS.map((l) => ({ lang: l, path: listPath(l, before) })),
    body,
  };
}
