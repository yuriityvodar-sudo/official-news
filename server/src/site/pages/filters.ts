// The list's two filters (#67, #68), as the app's compact chips under the
// title (Yurii, 16 Oct; prototype/chips, feed_filters.dart): Where (All
// countries, a group of countries, or one country) and Topics (All topics, or
// one). After the prototype's review (prototype/chips 3d88cf3, Yurii, 16 Oct).
// No script: each chip is the <summary> of a <details>, its menu a list of
// plain links, so choosing is one request, and a keyboard or a screen reader
// meets a disclosure button and links. A chip is always the grey chip; once a
// filter is on, it is short and red: a country's code (GB), a group's short
// name in the language (ЄС, G7, G20, НАТО), a topic's icon. A screen reader
// hears the full name ("Country: United Kingdom"). The menus keep the full
// names, the Topics menu each topic's icon before its name, so a reader
// learns what the chip's icon means; the current choice has a checkmark and
// aria-current. No counts. Only valid
// items: the groups and countries GET /countries lists and the topics GET
// /topics lists for the place and the language, plus the current choice when
// the list does not have it (as the app keeps it).
import type { Topic } from "../../summarizer/schema";
import type { ApiTopic, ApiWhere, Menus } from "../data";
import { type Html, html, raw } from "../html";
import { type SiteLang, countryName, groupName, groupShort, text, topicName } from "../texts";
import { type ListFilter, type Place, isCountryPage, listPath } from "../urls";

const CHEVRON = raw(
  `<svg class="chev" viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M2.5 4.5 6 8l3.5-3.5"/></svg>`,
);
const CHECK = raw(
  `<svg class="check" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m5 12.5 4.5 4.5L19 7.5"/></svg>`,
);

/** A stroked line of an icon; the rest of an icon is filled. */
const line = (d: string) => `<path d="${d}" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>`;

/**
 * What the Topics chip shows instead of the name once a topic is chosen, and
 * the Topics menu before each name: one glyph per topic, drawn here (24 × 24),
 * the same meanings as the app's topicIcons (core/topics.dart, after the
 * prototype's review): none means something else on a page, so health is a
 * star of life (a heart reads as a favourite), elections a ticked document (a
 * ticked box reads as chosen), climate a leaf (no weather). A topic added to
 * TOPICS (Roman's #91: education, justice) fails the typecheck until it has
 * one here, as its name in TOPIC_NAMES (api/filters.ts) and the app's ARB
 * files and topicIcons.
 */
export const TOPIC_ICONS: Record<Topic, string> = {
  "foreign-affairs": line("M3 12h18") + line("M12 3a14 14 0 0 1 0 18a14 14 0 0 1 0-18") + `<circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/>`,
  economy: `<rect x="3.5" y="12" width="4.5" height="8.5" rx="1.2"/><rect x="9.75" y="7" width="4.5" height="13.5" rx="1.2"/><rect x="16" y="3.5" width="4.5" height="17" rx="1.2"/>`,
  "security-defence": `<path d="M12 2.5 4.5 5.4v5.8c0 4.8 3.1 8.8 7.5 10.3 4.4-1.5 7.5-5.5 7.5-10.3V5.4z"/>`,
  health: [0, 60, 120].map((turn) => `<rect x="9.4" y="2" width="5.2" height="20" rx="1.2"${turn ? ` transform="rotate(${turn} 12 12)"` : ""}/>`).join(""),
  climate: `<path d="M20.5 3.5c-9.6 0-15.8 4.3-15.8 10.7 0 3.4 2.6 6.1 6 6.1 6.9 0 9.8-6.7 9.8-16.8z"/>${line("M3.5 21.5c2.6-4.6 6.2-8.2 10.7-10.7")}`,
  trade: line("M4 8h15M15 4l4 4-4 4M20 16H5M9 12l-4 4 4 4"),
  technology: `<rect x="3" y="4" width="18" height="12.5" rx="2" fill="none" stroke="currentColor" stroke-width="2"/>${line("M8.5 20.5h7M12 16.5v4")}`,
  energy: `<path d="M13.6 2 4.8 13.6h6.1L10.4 22l8.8-11.6h-6.1z"/>`,
  migration: `<circle cx="9" cy="7.5" r="3.6"/><path d="M2.5 20.5c0-4 2.9-6.8 6.5-6.8s6.5 2.8 6.5 6.8z"/><circle cx="17" cy="8.5" r="3"/><path d="M16.9 20.5c0-2.6-.8-4.8-2.3-6.3a6 6 0 0 1 1.9-.3c3.1 0 5.5 2.4 5.5 5.7v.9z"/>`,
  elections: line("M7 2.5h6.6L19 7.9V20a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 5 20V4.5a2 2 0 0 1 2-2zM13.5 2.5V8H19M8.5 14.6l2.4 2.4 4.6-5.1"),
  "human-rights": line("M8 12.5V6.2a1.5 1.5 0 0 1 3 0V11M11 11V4.5a1.5 1.5 0 0 1 3 0V11M14 11V5.7a1.5 1.5 0 0 1 3 0v6.8M17 12.5V9.2a1.5 1.5 0 0 1 3 0V14a7 7 0 0 1-7 7h-1.2a6 6 0 0 1-4.6-2.2l-3.4-4.1a1.6 1.6 0 0 1 2.4-2.1L8 14.4"),
  science: line("M9 3h6M10.2 3v6.2L4.8 18.6A1.6 1.6 0 0 0 6.2 21h11.6a1.6 1.6 0 0 0 1.4-2.4L13.8 9.2V3") + `<path d="M6.9 15h10.2l1.9 3.6a1.1 1.1 0 0 1-1 1.6H6a1.1 1.1 0 0 1-1-1.6z"/>`,
  // An open book (the app: book_fill) and a gavel (hammer_fill), added with #91's two topics (20 Oct).
  education: `<path d="M3 4.5A1.5 1.5 0 0 1 4.5 3h5A2.5 2.5 0 0 1 12 5.5v15a2.5 2.5 0 0 0-2.5-2.5h-5A1.5 1.5 0 0 1 3 16.5z"/><path d="M21 4.5A1.5 1.5 0 0 0 19.5 3h-5A2.5 2.5 0 0 0 12 5.5v15a2.5 2.5 0 0 1 2.5-2.5h5a1.5 1.5 0 0 0 1.5-1.5z"/>`,
  justice: `<rect x="2" y="5.5" width="9" height="5" rx="1.2" transform="rotate(-45 6.5 8)"/>` + line("M9.5 10.5 19.5 20.5") + `<rect x="3" y="19.5" width="10" height="2.5" rx="1"/>`,
};

const topicIcon = (topic: Topic) => raw(`<svg class="glyph" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">${TOPIC_ICONS[topic]}</svg>`);

interface Item {
  label: string;
  href: string;
  current: boolean;
  /** Before the name: the topic's icon, or `null` for an empty slot of the same width (All topics), so the names line up. */
  icon?: Topic | null;
}

const item = (i: Item) =>
  // nofollow: a filter's page is not indexed (Page.index) and robots.txt keeps
  // crawlers from its query; some crawlers ignore robots.txt (30 Oct, D1).
  html`<li><a href="${i.href}" rel="nofollow"${i.current ? raw(' aria-current="page"') : ""}>${
    i.icon === undefined ? "" : i.icon === null ? raw('<span class="glyph" aria-hidden="true"></span>') : topicIcon(i.icon)
  }<span>${i.label}</span>${i.current ? CHECK : ""}</a></li>`;

/** A menu's lists, each a group of links; an empty list is left out (the app's dividers between sections). */
const lists = (sections: Item[][]) => sections.filter((s) => s.length).map((s) => html`<ul>${s.map(item)}</ul>`);

/**
 * A chip, as the app's: what it shows (`shown`, a short label or an icon) and
 * a chevron (it opens a menu, or leads to the page that has it); a screen
 * reader hears `spoken`, the full name, instead. Red while a filter is on.
 */
const chip = (shown: Html | string, spoken: string, active: boolean) =>
  html`<span class="chip${active ? " on" : ""}"><span class="label" aria-hidden="true">${shown}</span><span class="vh">${spoken}</span>${CHEVRON}</span>`;

/** The full name of a place: All countries, the country's or the group's name. */
export const placeName = (lang: SiteLang, place: Place) =>
  place === null ? text(lang, "filterAllCountries") : "country" in place ? countryName(lang, place.country) : groupName(lang, place.group);

/** The topic's full name, or All topics. */
export const topicLabel = (lang: SiteLang, topic: Topic | null) => (topic ? topicName(lang, topic) : text(lang, "filterAllTopics"));

/** The Where chip: All countries; a country's code (GB); a group's short name in the language (ЄС, G7, G20, НАТО). */
function whereChip(lang: SiteLang, place: Place): Html {
  if (place === null) return chip(text(lang, "filterAllCountries"), text(lang, "filterAllCountries"), false);
  if ("country" in place) return chip(place.country, text(lang, "filterCountryChip", { name: countryName(lang, place.country) }), true);
  return chip(groupShort(lang, place.group), text(lang, "filterGroupChip", { name: groupName(lang, place.group) }), true);
}

/** The Topics chip: All topics, or the topic's icon. */
const topicsChip = (lang: SiteLang, topic: Topic | null) =>
  topic === null
    ? chip(text(lang, "filterAllTopics"), text(lang, "filterAllTopics"), false)
    : chip(topicIcon(topic), text(lang, "filterTopicChip", { name: topicName(lang, topic) }), true);

const sameCountry = (place: Place, code: string) => place !== null && "country" in place && place.country === code;
const sameGroup = (place: Place, id: string) => place !== null && "group" in place && place.group === id;

function whereMenu(lang: SiteLang, filter: ListFilter, where: ApiWhere): Html {
  const { place, topic } = filter;
  // Only countries the site has a page for (COUNTRY_PAGES in urls.ts: the source countries).
  const listed = where.countries.filter((c) => isCountryPage(c.code));
  // The current country stays offered, checked, when it has no active source now (the app does the same).
  const current = place !== null && "country" in place && !listed.some((c) => c.code === place.country) ? place.country : null;
  const countries = current ? [{ code: current, name: countryName(lang, current) }, ...listed] : listed;
  return html`<details class="pick" name="filters">
<summary>${whereChip(lang, place)}</summary>
<div class="menu">${lists([
    [{ label: text(lang, "filterAllCountries"), href: listPath(lang, { place: null, topic }), current: place === null }],
    where.groups.map((g) => ({ label: g.name, href: listPath(lang, { place: { group: g.id }, topic }), current: sameGroup(place, g.id) })),
    countries.map((c) => ({ label: c.name, href: listPath(lang, { place: { country: c.code }, topic }), current: sameCountry(place, c.code) })),
  ])}</div>
</details>`;
}

function topicsMenu(lang: SiteLang, filter: ListFilter, topics: ApiTopic[]): Html {
  const { place, topic } = filter;
  const listed = topic && !topics.some((x) => x.id === topic) ? [{ id: topic, name: topicName(lang, topic) }, ...topics] : topics;
  return html`<details class="pick" name="filters">
<summary>${topicsChip(lang, topic)}</summary>
<div class="menu">${lists([
    [{ label: text(lang, "filterAllTopics"), href: listPath(lang, { place, topic: null }), current: topic === null, icon: null }],
    listed.map((x) => ({ label: x.name, href: listPath(lang, { place, topic: x.id }), current: x.id === topic, icon: x.id })),
  ])}</div>
</details>`;
}

/**
 * The two chips under the list's title. With `menus` (a first page), each
 * opens its menu; without (a later page, which reads no D1 rows for menus),
 * each is a link to the first page of the same list, where the menus are (a
 * URL that is cached on its own, so this page still reads nothing for them).
 */
export function filterBar(lang: SiteLang, filter: ListFilter, menus: Menus | null): Html {
  if (!menus) {
    const first = listPath(lang, filter);
    return html`<nav class="filters" aria-label="${text(lang, "filters")}"><a class="chip-link" href="${first}">${whereChip(lang, filter.place)}</a><a class="chip-link" href="${first}">${topicsChip(
      lang,
      filter.topic,
    )}</a></nav>`;
  }
  return html`<nav class="filters" aria-label="${text(lang, "filters")}">
${whereMenu(lang, filter, menus.where)}
${topicsMenu(lang, filter, menus.topics)}
</nav>`;
}
