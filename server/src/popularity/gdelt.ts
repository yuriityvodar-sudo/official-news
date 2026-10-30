// What the media publish about an item, from GDELT (#230 step 4): one DOC
// API search a check, the last 48 hours, up to 250 articles, counted by each
// outlet's country (`sourcecountry`), with up to 3 links per country: the
// headline, the outlet and the link, never the article's text (EU Directive
// 2019/790, art. 15). GDELT asks for one request every 5 seconds at most.
//
// On 30 Oct 2026, from a laptop and from Cloudflare (Vienna, Zurich,
// Frankfurt), GDELT answered every request either 429 or with no articles at
// all, even for "Ukraine" over a day, after 12–21 seconds: the check counts on
// Wikipedia's views and takes GDELT's answer whenever it has one.
import { GDELT_COUNTRIES } from "./places";

/** GDELT is slow (12–21 s on 30 Oct): a request is given this long. */
export const GDELT_TIMEOUT_MS = 30_000;

/** At most this many articles a country keeps as links. */
export const MEDIA_LINKS = 3;

export interface MediaLink {
  title: string;
  outlet: string;
  url: string;
}

/** A search for the item: its first two keywords of 3 characters or more (GDELT refuses shorter ones), a phrase in quotes. Null without one. */
export function gdeltUrl(keywords: string[]): string | null {
  const words = keywords
    .map((k) => k.replace(/["()]/g, "").replace(/\s+/g, " ").trim())
    .filter((k) => k.length >= 3)
    .slice(0, 2);
  if (!words.length) return null;
  const query = words.map((w) => (w.includes(" ") ? `"${w}"` : w)).join(" ");
  const params = new URLSearchParams({ query, mode: "artlist", maxrecords: "250", timespan: "48h", format: "json", sort: "hybridrel" });
  return `https://api.gdeltproject.org/api/v2/doc/doc?${params}`;
}

/**
 * GDELT's answer by country: how many of its articles each country's outlets
 * published, and up to MEDIA_LINKS of them. Countries For you does not serve
 * (not in GDELT_COUNTRIES) are left out. Null when the answer is not GDELT's
 * JSON (an error page); an answer with no articles is an empty map.
 */
export function mediaFrom(answer: unknown): Map<string, { count: number; links: MediaLink[] }> | null {
  if (!answer || typeof answer !== "object" || Array.isArray(answer)) return null;
  const articles = (answer as { articles?: unknown }).articles ?? [];
  if (!Array.isArray(articles)) return null;
  const media = new Map<string, { count: number; links: MediaLink[] }>();
  for (const a of articles as Record<string, unknown>[]) {
    const country = typeof a?.sourcecountry === "string" ? GDELT_COUNTRIES[a.sourcecountry.trim()] : undefined;
    const url = typeof a?.url === "string" && /^https?:\/\//.test(a.url) ? a.url : null;
    const title = typeof a?.title === "string" ? a.title.replace(/\s+/g, " ").trim().slice(0, 200) : "";
    const outlet = typeof a?.domain === "string" ? a.domain.trim() : "";
    if (!country || !url) continue;
    const entry = media.get(country) ?? { count: 0, links: [] };
    entry.count++;
    if (title && outlet && entry.links.length < MEDIA_LINKS) entry.links.push({ title, outlet, url });
    media.set(country, entry);
  }
  return media;
}
