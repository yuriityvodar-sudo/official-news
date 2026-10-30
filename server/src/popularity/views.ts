// Wikipedia's page views of an item's article, per language (#230 step 4).
// The English article's page gives its titles in the other languages (its
// language links; robots.txt allows /wiki/ but not Wikipedia's API under /w/
// and /api/), and Wikimedia's pageviews API on wikimedia.org, open data, gives
// each one's views a day. Views come by day only, a day after it ends.

/** The language links come early in the page (about 40 KB into Christine Lagarde's 720 KB): this much is read, the rest left. */
export const READ_BYTES = 200_000;

/** A title as Wikipedia writes it in a link: underscores for spaces, percent-encoded, slashes kept. */
const linkTitle = (title: string) => encodeURIComponent(title.replaceAll(" ", "_")).replaceAll("%2F", "/");

/** The English article's page. */
export const articlePage = (title: string) => `https://en.wikipedia.org/wiki/${linkTitle(title)}`;

/** Days as the pageviews API writes them: YYYYMMDD. */
export const day = (date: Date) => date.toISOString().slice(0, 10).replaceAll("-", "");

/** The views a day of `title` on `lang`.wikipedia from `from` to `to` (YYYYMMDD), people only (no bots). */
export const viewsUrl = (lang: string, title: string, from: string, to: string) =>
  `https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/${lang}.wikipedia/all-access/user/${encodeURIComponent(title.replaceAll(" ", "_"))}/daily/${from}/${to}`;

/** The first `max` bytes of a response's body as text; the rest is not read. */
export async function readStart(response: Response, max = READ_BYTES): Promise<string> {
  const reader = response.body?.getReader();
  if (!reader) return "";
  const decoder = new TextDecoder();
  let text = "";
  let read = 0;
  while (read < max) {
    const { done, value } = await reader.read();
    if (done) break;
    read += value.byteLength;
    text += decoder.decode(value, { stream: true });
  }
  await reader.cancel().catch(() => {});
  return text;
}

/**
 * The article's own title (after a redirect: `wgPageName`) and its titles in
 * the other languages, from the page's language links. Only the links read
 * (READ_BYTES) count: a page cut before them has none.
 */
export function languageLinks(html: string): { title: string | null; links: Map<string, string> } {
  const page = /"wgPageName":"((?:[^"\\]|\\.)*)"/.exec(html);
  let title: string | null = null;
  try {
    title = page ? (JSON.parse(`"${page[1]}"`) as string).replaceAll("_", " ") : null;
  } catch {
    title = null;
  }
  const links = new Map<string, string>();
  for (const anchor of html.matchAll(/<a\s[^>]*interlanguage-link-target[^>]*>/g)) {
    const href = /href="https:\/\/([a-z-]+)\.wikipedia\.org\/wiki\/([^"#?]+)"/.exec(anchor[0]);
    if (!href || links.has(href[1])) continue;
    try {
      links.set(href[1], decodeURIComponent(href[2]).replaceAll("_", " "));
    } catch {
      // A link that is not valid percent-encoding: left out.
    }
  }
  return { title, links };
}

/** The usual day: the median of these days' views. */
function median(values: number[]): number {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : Math.round((sorted[middle - 1] + sorted[middle]) / 2);
}

/** Days before the item's that make its usual day. */
export const USUAL_DAYS = 7;

/**
 * From the pageviews API's answer: the most views in a day from the day the
 * item was published (`published`, YYYYMMDD) on, and the usual day, the median
 * of the USUAL_DAYS days before it (a day the API leaves out had no views).
 * Null when no day from `published` on has come yet: today's views come
 * tomorrow.
 */
export function viewsFrom(answer: unknown, published: string): { views: number; usual: number } | null {
  const items = (answer as { items?: unknown } | null)?.items;
  if (!Array.isArray(items)) return null;
  const byDay = new Map<string, number>();
  for (const item of items as { timestamp?: unknown; views?: unknown }[]) {
    if (typeof item?.timestamp === "string" && typeof item.views === "number") byDay.set(item.timestamp.slice(0, 8), item.views);
  }
  const after = [...byDay].filter(([d]) => d >= published).map(([, v]) => v);
  if (!after.length) return null;
  const start = Date.UTC(Number(published.slice(0, 4)), Number(published.slice(4, 6)) - 1, Number(published.slice(6, 8)));
  const before = Array.from({ length: USUAL_DAYS }, (_, i) => byDay.get(day(new Date(start - (i + 1) * 86_400_000))) ?? 0);
  return { views: Math.max(...after), usual: median(before) };
}
