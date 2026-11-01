// Wikipedia's current events (#230, step 3): what happened in the world each
// day, read from the pages' raw wikitext (`/wiki/<page>?action=raw`: robots.txt
// allows `/wiki/`, not `/w/` or `/api/`). One item per event: its sentence, with
// the topics above it and the outlets it cites, for the summarizer. English has
// a page a day; Russian one page of the latest events, under a heading a day.
// The text is CC BY-SA 4.0: the item links the page it came from.
import type { FoundItem } from "./types";

export type EventsLang = "en" | "ru";

const EN_MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
const RU_MONTHS = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"];

/** The raw pages to read: in English today's and yesterday's (UTC), in Russian the page of the latest events. */
export function currentEventsPages(lang: EventsLang, now: Date): string[] {
  if (lang === "ru") return [encodeURI("https://ru.wikipedia.org/wiki/Портал:Текущие_события/Последние_события?action=raw")];
  return [0, 1].map((back) => {
    const day = new Date(now.getTime() - back * 86_400_000);
    return `https://en.wikipedia.org/wiki/Portal:Current_events/${day.getUTCFullYear()}_${EN_MONTHS[day.getUTCMonth()]}_${day.getUTCDate()}?action=raw`;
  });
}

/** Wikitext as plain text: links as their words, no references, templates, comments or bold and italics. */
export function plainText(wikitext: string): string {
  let text = wikitext
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/<ref[^>]*\/>/g, "")
    .replace(/<ref[^>]*>[\s\S]*?<\/ref>/g, "");
  // Templates may hold templates: take them out from the inside.
  for (let before = ""; before !== text; ) {
    before = text;
    text = text.replace(/\{\{[^{}]*\}\}/g, "");
  }
  return text
    .replace(/\[\[(?:[^|\]]*\|)?([^\]]*)\]\]/g, "$1")
    .replace(/\[https?:\/\/[^\s\]]+(?:\s[^\]]*)?\]/g, "")
    .replace(/'{2,}/g, "")
    .replace(/\s+/g, " ")
    .replace(/\s+([.,;:])/g, "$1")
    .trim();
}

/** The sources an English event cites: `[https://… (AP)]`, the first link and every outlet's name. */
function englishCites(line: string): { url: string | null; outlets: string[] } {
  const cites = [...line.matchAll(/\[(https?:\/\/[^\s\]]+)\s+\(([^)]*)\)\]/g)];
  return { url: cites[0]?.[1] ?? null, outlets: cites.map((c) => plainText(c[2])).filter(Boolean) };
}

/** The sources a Russian event cites: `<ref>{{cite web|url=…|publisher=…}}</ref>`. */
function russianCites(line: string): { url: string | null; outlets: string[] } {
  const refs = [...line.matchAll(/<ref[^>/]*>([\s\S]*?)<\/ref>/g)].map((r) => r[1]);
  const urls = refs.map((r) => /\|\s*url\s*=\s*([^|}\s]+)/i.exec(r)?.[1]).filter((u): u is string => Boolean(u));
  const outlets = refs
    .map((r) => /\|\s*(?:publisher|website|work|agency|издание|издательство)\s*=\s*([^|}]+)/i.exec(r)?.[1])
    .filter((o): o is string => Boolean(o))
    .map(plainText)
    .filter(Boolean);
  return { url: urls[0] ?? null, outlets: [...new Set(outlets)] };
}

/** A short stable id for an event, from the link of its first source: FNV-1a, in base 36. */
function eventId(key: string): string {
  let hash = 0x811c9dc5;
  for (const ch of key) hash = Math.imul(hash ^ ch.charCodeAt(0), 0x01000193) >>> 0;
  return hash.toString(36);
}

/**
 * The events of one page, `day` (YYYY-MM-DD) for an English one; a Russian one
 * dates its events by its `=== [[29 октября]] ===` headings. A bullet with a
 * cited source is an event; one without is a topic, kept as the context of the
 * events under it; a `'''heading'''` (English) or a top bullet without a source
 * (Russian) is the category.
 */
export function parseCurrentEvents(wikitext: string, pageUrl: string, lang: EventsLang, now: Date, day?: string): FoundItem[] {
  const items: FoundItem[] = [];
  let date = day ?? null;
  let category = "";
  const topics: string[] = [];
  // The links of each topic line above, by depth: the articles on the story it belongs to.
  const topicLinks: string[][] = [];
  for (const raw of wikitext.split("\n")) {
    const line = raw.trim();
    const heading = /^'''([^']+)'''$/.exec(line);
    if (heading) {
      category = plainText(heading[1]);
      topics.length = 0;
      topicLinks.length = 0;
      continue;
    }
    const dayHeading = /^===\s*\[\[(\d{1,2}) ([а-яё]+)\]\]\s*===$/i.exec(line);
    if (dayHeading) {
      const month = RU_MONTHS.indexOf(dayHeading[2].toLowerCase());
      if (month >= 0) {
        // The page's latest events: a date later than tomorrow is last year's.
        let year = now.getUTCFullYear();
        if (Date.UTC(year, month, Number(dayHeading[1])) > now.getTime() + 86_400_000) year--;
        date = new Date(Date.UTC(year, month, Number(dayHeading[1]))).toISOString().slice(0, 10);
      }
      category = "";
      topics.length = 0;
      topicLinks.length = 0;
      continue;
    }
    const bullet = /^(\*+)\s*(.*)$/.exec(line);
    if (!bullet || !date) continue;
    const depth = bullet[1].length;
    const body = bullet[2];
    const { url, outlets } = lang === "ru" ? russianCites(body) : englishCites(body);
    topics.length = Math.min(topics.length, depth - 1);
    topicLinks.length = Math.min(topicLinks.length, depth - 1);
    if (!url) {
      if (lang === "ru" && depth === 1) {
        category = plainText(body);
        topics.length = 0;
        topicLinks.length = 0;
      } else {
        topics[depth - 1] = plainText(body);
        topicLinks[depth - 1] = linkTargets(body);
      }
      continue;
    }
    const sentence = plainText(body);
    if (!sentence) continue;
    const context = topics.slice(0, depth - 1).filter(Boolean);
    const reported = outlets.length ? `${lang === "ru" ? "Источники" : "Reported by"}: ${outlets.join(", ")}` : "";
    items.push({
      url: `${pageUrl}#event-${eventId(url)}`,
      title: sentence.slice(0, 500),
      publishedAt: `${date}T12:00:00Z`,
      dateOnly: true,
      text: [category, context.join(" › "), sentence, reported].filter(Boolean).join("\n"),
      imageUrl: null,
      category: category || null,
      background: backgroundOf(topicLinks.slice(0, depth - 1).reverse(), sentence, linkTargets(body)) ?? undefined,
    });
  }
  return items;
}

/** The articles a wikitext links, as their titles ("[[Blockade of Oleshky|the blockade]]" links "Blockade of Oleshky"), no files or categories. */
export function linkTargets(wikitext: string): string[] {
  return [...wikitext.matchAll(/\[\[([^|\]#]+)(?:#[^|\]]*)?(?:\|[^\]]*)?\]\]/g)]
    .map((m) => m[1].replace(/_/g, " ").trim())
    .filter((t) => t && !/^(file|image|category|файл|изображение|категория):/i.test(t));
}

/** Words of four letters or more, lowercased: what a title and a sentence share. */
const words = (text: string) => new Set(text.toLowerCase().match(/[\p{L}\p{N}]{4,}/gu) ?? []);

/**
 * The article whose lead gives an event its background (#230, Roman, 1 Nov:
 * «почему новости из википедии такие короткие?»): the topic lines above the
 * event link Wikipedia's articles on the story it belongs to ("Blockade of
 * Oleshky" above "Hundreds evacuate the Ukrainian city of Oleshky…"). The
 * innermost line first, and on it the link whose words the sentence shares
 * the most of, as a share of the title's words ("Blockade of Oleshky" 1 of 2
 * against "Peace negotiations in the Russo-Ukrainian war" 1 of 6; its first
 * on a tie); without topics, the event's own first link that shares a word
 * with it, else its first.
 */
export function backgroundOf(topicLinksInnermostFirst: string[][], sentence: string, ownLinks: string[]): string | null {
  const said = words(sentence);
  const shared = (title: string) => {
    const own = [...words(title)];
    return own.length ? own.filter((w) => said.has(w)).length / own.length : 0;
  };
  for (const links of topicLinksInnermostFirst) {
    if (!links.length) continue;
    return links.reduce((best, title) => (shared(title) > shared(best) ? title : best), links[0]);
  }
  return ownLinks.find((title) => shared(title) > 0) ?? ownLinks[0] ?? null;
}

/** About this much of an article's lead is kept as an event's background: two or three paragraphs. */
export const BACKGROUND_CHARS = 1200;

/**
 * The lead of an article's wikitext (`/wiki/<title>?action=raw`), as plain
 * text: what comes before its first heading, without files, tables and
 * templates (the infobox), cut at a sentence near BACKGROUND_CHARS. A
 * redirect gives its target instead, to read once more; null when there is
 * no lead.
 */
export function leadOf(wikitext: string): { lead: string } | { redirect: string } | null {
  const redirect = /^#(?:redirect|перенаправление)\s*\[\[([^|\]#]+)/i.exec(wikitext.trim());
  if (redirect) return { redirect: redirect[1].trim() };
  const top = wikitext.split(/^==[^=].*$/m)[0] ?? "";
  const text = plainText(
    top
      .replace(/\[\[(?:file|image|файл|изображение):[^\n]*\]\]/gi, "")
      .replace(/\{\|[\s\S]*?\|\}/g, "")
      .replace(/<gallery[\s\S]*?<\/gallery>/gi, ""),
  );
  if (text.length < 40) return null;
  if (text.length <= BACKGROUND_CHARS) return { lead: text };
  const cut = text.slice(0, BACKGROUND_CHARS);
  const end = cut.lastIndexOf(". ");
  return { lead: end > BACKGROUND_CHARS / 2 ? cut.slice(0, end + 1) : `${cut}…` };
}

/** The raw wikitext of an article on the wiki of `pageUrl` (`/wiki/` is what robots.txt allows). */
export const articleRaw = (pageUrl: string, title: string) =>
  `${new URL(pageUrl).origin}/wiki/${encodeURIComponent(title.replace(/ /g, "_")).replace(/%2F/g, "/")}?action=raw`;

/** The day of an English day page, from its address: `…/2026_October_29?action=raw` is 2026-10-29. */
export function englishPageDay(page: string): string | undefined {
  const m = /Portal:Current_events\/(\d{4})_([A-Za-z]+)_(\d{1,2})/.exec(page);
  const month = m ? EN_MONTHS.indexOf(m[2]) : -1;
  return m && month >= 0 ? new Date(Date.UTC(Number(m[1]), month, Number(m[3]))).toISOString().slice(0, 10) : undefined;
}
