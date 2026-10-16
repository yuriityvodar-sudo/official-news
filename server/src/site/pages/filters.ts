// The list's two filters (#67, #68), as the app's chips under the title
// (feed_filters.dart): Where (Global, Local, or one country) and Topics (all,
// or one). No script: each chip is the <summary> of a <details>, its menu a
// list of plain links, so choosing is one request, and a keyboard or a screen
// reader meets a disclosure button and links. A chip that narrows the list is
// red, as in the app; the current choice in a menu has a checkmark and
// aria-current. No counts. Only valid items: the countries GET /countries
// lists and the topics GET /topics lists for the country and the language,
// plus the current choice when the list does not have it (as the app keeps it).
import type { ApiCountry, ApiTopic } from "../data";
import { type Html, html, raw } from "../html";
import { type SiteLang, countryName, t, text, topicName } from "../texts";
import { type ListFilter, type OpenMenu, listPath, localPath } from "../urls";

const icon = (paths: string) =>
  raw(`<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths}</svg>`);
const GLOBE = icon(`<circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><path d="M12 3a14 14 0 0 1 0 18a14 14 0 0 1 0-18"/>`);
const PIN = icon(`<path d="M12 21s-7-6.2-7-11.5a7 7 0 0 1 14 0C19 14.8 12 21 12 21z"/><circle cx="12" cy="9.5" r="2.5"/>`);
const GRID = icon(`<rect x="4" y="4" width="6.5" height="6.5" rx="1.5"/><rect x="13.5" y="4" width="6.5" height="6.5" rx="1.5"/><rect x="4" y="13.5" width="6.5" height="6.5" rx="1.5"/><rect x="13.5" y="13.5" width="6.5" height="6.5" rx="1.5"/>`);
const CHEVRON = raw(
  `<svg class="chev" viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M2.5 4.5 6 8l3.5-3.5"/></svg>`,
);
const CHECK = raw(
  `<svg class="check" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m5 12.5 4.5 4.5L19 7.5"/></svg>`,
);

/** What the menus offer, from the API: on the first page of a list only. */
export interface Menus {
  countries: ApiCountry[];
  topics: ApiTopic[];
}

interface Item {
  label: string;
  detail?: string;
  href: string;
  current: boolean;
}

const item = (i: Item) =>
  // The space keeps "Global All countries" two words for a screen reader (the detail is a block below).
  html`<li><a href="${i.href}"${i.current ? raw(' aria-current="page"') : ""}><span>${i.label}${
    i.detail ? html` <small>${i.detail}</small>` : ""
  }</span>${i.current ? CHECK : ""}</a></li>`;

/** A chip, as the app's: its glyph, its label, a chevron (it opens a menu, or leads to the page that has it). */
const chip = (glyph: Html, label: string, active: boolean) =>
  html`<span class="chip${active ? " on" : ""}">${glyph}<span class="label">${label}</span>${CHEVRON}</span>`;

/** The Where chip's label: the country's name, or Global. */
export const whereLabel = (lang: SiteLang, filter: ListFilter) => (filter.country ? countryName(lang, filter.country) : text(lang, "filterGlobal"));

/** The Topics chip's label: the topic's name, or All topics. */
export const topicLabel = (lang: SiteLang, filter: ListFilter) => (filter.topic ? topicName(lang, filter.topic) : text(lang, "filterAllTopics"));

function whereMenu(lang: SiteLang, filter: ListFilter, countries: ApiCountry[], open: boolean): Html {
  const { topic } = filter;
  // The current country stays offered, checked, when it has no active source now (the app does the same).
  const listed =
    filter.country && !countries.some((c) => c.code === filter.country)
      ? [{ code: filter.country, name: countryName(lang, filter.country) }, ...countries]
      : countries;
  const scopes = [
    item({ label: text(lang, "filterGlobal"), detail: text(lang, "filterGlobalDetail"), href: listPath(lang, { country: null, topic }), current: !filter.country }),
    // Local is the reader's own country: a 302 worked out per request, never in a cached page.
    item({ label: text(lang, "filterLocal"), href: localPath(lang, topic), current: false }),
  ];
  return html`<details class="pick" name="filters"${open ? raw(" open") : ""}>
<summary>${chip(filter.country ? PIN : GLOBE, whereLabel(lang, filter), !!filter.country)}</summary>
<div class="menu">${open ? html`<p class="menu-note">${t(lang, "localNone")}</p>` : ""}<ul>${scopes}</ul>${
    listed.length
      ? html`<ul>${listed.map((c) => item({ label: c.name, href: listPath(lang, { country: c.code, topic }), current: c.code === filter.country }))}</ul>`
      : ""
  }</div>
</details>`;
}

function topicsMenu(lang: SiteLang, filter: ListFilter, topics: ApiTopic[]): Html {
  const { country } = filter;
  const listed =
    filter.topic && !topics.some((x) => x.id === filter.topic) ? [{ id: filter.topic, name: topicName(lang, filter.topic) }, ...topics] : topics;
  return html`<details class="pick" name="filters">
<summary>${chip(GRID, topicLabel(lang, filter), !!filter.topic)}</summary>
<div class="menu"><ul>${item({ label: text(lang, "filterAllTopics"), href: listPath(lang, { country, topic: null }), current: !filter.topic })}${listed.map((x) =>
    item({ label: x.name, href: listPath(lang, { country, topic: x.id }), current: x.id === filter.topic }),
  )}</ul></div>
</details>`;
}

/**
 * The two chips under the list's title. With `menus` (a first page), each
 * opens its menu; without (a later page, which reads no D1 rows for menus),
 * each is a link to the first page of the same list, where the menus are (a
 * URL that is cached on its own, so this page still reads nothing for them).
 * `open` opens Where: Local with no country to go to.
 */
export function filterBar(lang: SiteLang, filter: ListFilter, menus: Menus | null, open: OpenMenu | null): Html {
  if (!menus) {
    const first = listPath(lang, filter);
    return html`<nav class="filters" aria-label="${text(lang, "filters")}"><a class="chip-link" href="${first}">${chip(
      filter.country ? PIN : GLOBE,
      whereLabel(lang, filter),
      !!filter.country,
    )}</a><a class="chip-link" href="${first}">${chip(GRID, topicLabel(lang, filter), !!filter.topic)}</a></nav>`;
  }
  return html`<nav class="filters" aria-label="${text(lang, "filters")}">
${whereMenu(lang, filter, menus.countries, open === "where")}
${topicsMenu(lang, filter, menus.topics)}
</nav>`;
}
