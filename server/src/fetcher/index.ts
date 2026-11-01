import type { Env } from "../env";
import { recordChecks } from "../health/status";
import { parseApi } from "./api";
import { parseFeed } from "./feed";
import { extractContent, findLink, parsePage } from "./page";
import { type Robots, isAllowed, robotsFromResponse } from "./robots";
import { decodeBody, getStrings, htmlToText, toStoredTime, ulid } from "./text";
import { type FilterField, type FoundItem, type SourceConfig, type SourceRow, configRegex, readConfig } from "./types";
import { type EventsLang, articleRaw, currentEventsPages, englishPageDay, leadOf, parseCurrentEvents } from "./wikipedia";

export const USER_AGENT = "OfficialNewsBot/0.1 (+https://github.com/yuriityvodar-sudo/official-news)";

/** Limits that keep one source's check, a call of its own, inside the free plan (50 outside requests, 10 ms CPU). */
export const LIMITS = {
  /**
   * A source is read in full at least this often: robots.txt, every listed
   * item, known items read again (#227). The checks between only compare its
   * list with the last one, so they parse nothing and write nothing.
   */
  fullCheckMinutes: 60,
  /**
   * A list is checked this often unless its source says otherwise (config.everyMinutes, 1 for
   * those that publish as things happen). Every check is a request to the site, and a call
   * through ctx.exports counts against the account's 100,000 Worker requests a day, since our
   * Worker has Workers Caching on (Yurii's review of #274): every source every minute would
   * take about 53,000 of them.
   */
  everyMinutes: 5,
  /** A source whose last check failed is asked again after this long, not at every turn. */
  failedCheckMinutes: 10,
  /** Newest items looked at per check. */
  itemsPerSource: 20,
  /** New items saved per check; the rest are saved on the next check. */
  newPerSource: 10,
  /**
   * Item pages (or `fullText` reads) per run, for text and image. Reading HTML
   * is the heavy part of a run (#40); a text that reaches `maxText` counts as
   * all of them. A page that failed or was not answered does not count.
   */
  pagesPerRun: 2,
  requestsPerRun: 40,
  /** The feed shows 7 days, so older items are never saved. */
  maxAgeDays: 7,
  /**
   * List text shorter than this is a teaser (#71: 200 to 500 characters of a
   * 3,000-character article): the item page, or the source's `fullText`, is
   * read for the whole text, also when the list has a picture, and the item
   * waits for page budget instead of being saved with the teaser.
   */
  teaserText: 1000,
  /** A `fullText` read follows at most this many steps. */
  fullTextSteps: 3,
  /**
   * Each answer of a `fullText` read is at most this big. JSON is parsed whole
   * (195 KB took about 1 ms locally); a page is read only up to `maxText`
   * characters of text, whatever its size.
   */
  fullTextBytes: 200_000,
  /**
   * An item whose text could not be read (the site busy, or its page failing)
   * is asked again on later checks while it is this new; then the teaser is saved.
   */
  retryHours: 24,
  /** A known item out of the feed is read again at most this often (#227). */
  rereadMinutes: 60,
  /** Pages of one site that may fail (5xx, no answer in time) in a run before the site counts as busy. */
  failedPagesPerHost: 3,
  maxText: 20_000,
  textDays: 30,
  timeoutMs: 15_000,
};

/** What happened to one source in a run; source health (item 8) builds on it. */
export interface SourceCheck {
  sourceId: string;
  ok: boolean;
  httpStatus: number | null;
  /** Items on the list after the source's filters. */
  found: number;
  saved: number;
  /** New items left for the next check: no page budget left to read their text, or the site asked us to wait. */
  waiting: number;
  /** Items skipped because they had no date (a broken date selector would otherwise flood the feed as today's news). */
  undated: number;
  /** Items skipped because their link leaves the source's site. */
  offSite: number;
  /** Known items read again: their text never came, or their publisher renamed them (#227). */
  reread: number;
  error: string | null;
  /** Read in full (LIMITS.fullCheckMinutes), not only compared with the last list. */
  full: boolean;
  /** The list is the one read last time: nothing was parsed. */
  unchanged: boolean;
}

export interface FetcherOptions {
  fetch?: typeof fetch;
  now?: Date;
  sleep?: (ms: number) => Promise<void>;
  /**
   * How a source is checked: in production a call of its own (`SourceChecker`, src/index.ts). Without it
   * the check runs inside this call, and a run checks only one source (runFetcher).
   */
  call?: (source: SourceRow) => Promise<SourceCheck>;
}

/** Per-check state: request budget, robots.txt per site, last request per site. */
interface Run {
  env: Env;
  now: Date;
  /** A full check (LIMITS.fullCheckMinutes): robots.txt is read for the list, and the list is parsed even when unchanged. */
  full: boolean;
  fetch: typeof fetch;
  sleep: (ms: number) => Promise<void>;
  requests: number;
  pages: number;
  robots: Map<string, Promise<Robots>>;
  lastRequest: Map<string, number>;
  /** Hosts that answered 429 or 503, could not be reached, or failed `failedPagesPerHost` pages in this run: not asked again until the next run. */
  busy: Set<string>;
  /** Pages that failed in this run, per host. */
  failed: Map<string, number>;
}

/** `form`: the body of a form POST (config.listPost), else a GET. */
async function request(
  run: Run,
  url: string,
  accept: string,
  crawlDelaySeconds = 0,
  extraHeaders: Record<string, string> = {},
  form?: string,
): Promise<Response> {
  if (run.requests >= LIMITS.requestsPerRun) throw new Error("request budget for this run used up");
  // Counted before the first await, so two checks running side by side cannot both pass the limit.
  run.requests++;
  const host = new URL(url).host;
  const last = run.lastRequest.get(host);
  if (crawlDelaySeconds && last !== undefined) {
    const wait = last + crawlDelaySeconds * 1000 - Date.now();
    if (wait > 0) await run.sleep(wait);
  }
  run.lastRequest.set(host, Date.now());
  return run.fetch(url, {
    ...(form === undefined ? {} : { method: "POST", body: form }),
    headers: {
      "user-agent": USER_AGENT,
      accept,
      ...(form === undefined ? {} : { "content-type": "application/x-www-form-urlencoded" }),
      ...extraHeaders,
    },
    redirect: "follow",
    signal: AbortSignal.timeout(LIMITS.timeoutMs),
  });
}

function robotsFor(run: Run, url: URL): Promise<Robots> {
  let robots = run.robots.get(url.origin);
  if (!robots) {
    robots = request(run, `${url.origin}/robots.txt`, "text/plain")
      .then(async (res) => robotsFromResponse(res.status, res.ok ? await res.text() : ""))
      .catch((error): Robots => ({ kind: "disallowAll", reason: `robots.txt not reachable: ${error instanceof Error ? error.message : String(error)}` }));
    run.robots.set(url.origin, robots);
  }
  return robots;
}

/** null when allowed, otherwise why not. */
async function blockedBy(run: Run, url: string): Promise<string | null> {
  const u = new URL(url);
  const robots = await robotsFor(run, u);
  if (robots.kind === "disallowAll") return robots.reason;
  return isAllowed(robots, u.pathname + u.search) ? null : "robots.txt does not allow this path";
}

function charsetOf(res: Response, config: SourceConfig, bytes: ArrayBuffer): string | null {
  const header = res.headers.get("content-type")?.match(/charset=["']?([^;"']+)/i)?.[1];
  if (header) return header;
  if (config.encoding) return config.encoding;
  const head = new TextDecoder().decode(bytes.slice(0, 200));
  return head.match(/encoding=["']([^"']+)["']/i)?.[1] ?? null;
}

/**
 * A link is used only when it stays on the source's own site (same host, or a
 * subdomain of it without "www."), or on a host the config allows, and only over
 * https: we show the text with the "Official source" mark. http links on those
 * hosts are upgraded, since every source is read over https. Null otherwise.
 */
function onSite(link: string, sourceUrl: string, config: SourceConfig): string | null {
  let url: URL;
  try {
    url = new URL(link);
  } catch {
    return null;
  }
  const site = new URL(sourceUrl).host.replace(/^www\./, "");
  const host = url.host;
  const allowed = host === site || host.endsWith(`.${site}`) || (config.allowedHosts ?? []).includes(host);
  if (!allowed || (url.protocol !== "https:" && url.protocol !== "http:")) return null;
  if (url.protocol === "http:") url.protocol = "https:";
  return url.toString();
}

function onSourceSite(item: FoundItem, sourceUrl: string, config: SourceConfig): FoundItem | null {
  const url = onSite(item.url, sourceUrl, config);
  return url ? { ...item, url } : null;
}

function passesFilters(item: FoundItem, config: SourceConfig): boolean {
  for (const [field, pattern] of Object.entries(config.match ?? {})) {
    const regex = configRegex(pattern);
    // A newspaper's lead may leave out the decision its headline names (Урядовий кур'єр).
    const headline = field === "title" && item.headline !== undefined && regex.test(item.headline);
    if (!headline && !regex.test(item[field as FilterField] ?? "")) return false;
  }
  for (const [field, pattern] of Object.entries(config.exclude ?? {})) {
    if (configRegex(pattern).test(item[field as FilterField] ?? "")) return false;
  }
  return true;
}

interface ListResult {
  items: FoundItem[];
  status: number;
  /** The list's validators, to send back next time (conditionalGet sources). */
  etag: string | null;
  lastModified: string | null;
  /** The list's fingerprint, to compare at the next check; null when none was read. */
  hash: string | null;
  /** The list is the one read last time (a 304, or the same fingerprint between full checks). */
  unchanged?: boolean;
}

/** SHA-256 of a list. */
async function fingerprint(list: ArrayBuffer | string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", typeof list === "string" ? new TextEncoder().encode(list) : list);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

/**
 * The list's address: `{year}` becomes the current year (UTC), for lists that
 * can only be asked for one year (Brazil's Senate), so the URL needs no change
 * on 1 January.
 */
function listUrl(url: string, now: Date): string {
  return url.replaceAll("{year}", String(now.getUTCFullYear()));
}

/**
 * Wikipedia's current events (#230): the raw wikitext of the last days' pages.
 * A day page not written yet (404 early in the UTC day) is skipped; the check
 * fails only when no page could be read.
 */
async function readCurrentEvents(run: Run, source: SourceRow, lang: EventsLang, config: SourceConfig): Promise<ListResult> {
  const pages: { page: string; wikitext: string }[] = [];
  let failed: number | null = null;
  for (const raw of currentEventsPages(lang, run.now)) {
    if (run.full && (await blockedBy(run, raw))) continue;
    const res = await request(run, raw, "text/x-wiki, text/plain;q=0.9", config.crawlDelaySeconds);
    if (!res.ok) {
      failed ??= res.status;
      continue;
    }
    // The item links the page people read, not its wikitext.
    pages.push({ page: raw.replace(/\?action=raw$/, ""), wikitext: await res.text() });
  }
  if (!pages.length) return { items: [], status: failed ?? 403, etag: null, lastModified: null, hash: null };
  const hash = await fingerprint(pages.map((p) => p.wikitext).join("\n"));
  if (!run.full && hash === source.list_hash) return { items: [], status: 200, etag: null, lastModified: null, hash, unchanged: true };
  const items = pages.flatMap(({ page, wikitext }) => parseCurrentEvents(wikitext, page, lang, run.now, englishPageDay(page)));
  return { items, status: 200, etag: null, lastModified: null, hash };
}

/**
 * An event from Wikipedia's current events with its background (#230, Roman,
 * 1 Nov: «почему новости из википедии такие короткие?»): its one sentence
 * left the summary nothing to tell, so the text gets the lead of the article
 * its topics link (FoundItem.background), read as wikitext from the same wiki
 * (`/wiki/<title>?action=raw`, robots.txt checked as for any page), once per
 * title a run. A page that fails, or a run out of requests, saves the event
 * as it was.
 */
async function withBackground(run: Run, item: FoundItem, leads: Map<string, string | null>): Promise<FoundItem> {
  const title = item.background!;
  let lead = leads.get(title);
  if (lead === undefined) {
    lead = await readLead(run, item.url, title).catch(() => null);
    leads.set(title, lead);
  }
  return lead ? { ...item, text: `${item.text ?? item.title}\nBackground from Wikipedia («${title}»): ${lead}` } : item;
}

/** The lead of `title` on the wiki of `pageUrl`, following one redirect; null when there is none to read. */
async function readLead(run: Run, pageUrl: string, title: string, redirects = 1): Promise<string | null> {
  const url = articleRaw(pageUrl, title);
  if (await blockedBy(run, url)) return null;
  const res = await request(run, url, "text/x-wiki, text/plain;q=0.9");
  if (!res.ok) return null;
  const lead = leadOf(await res.text());
  if (!lead) return null;
  if ("redirect" in lead) return redirects > 0 ? readLead(run, pageUrl, lead.redirect, redirects - 1) : null;
  return lead.lead;
}

async function readList(run: Run, source: SourceRow, config: SourceConfig, url: string): Promise<ListResult> {
  if (config.currentEvents) return readCurrentEvents(run, source, config.currentEvents, config);
  // Servers often match these exactly, so we send back what they sent, never a time of our own.
  const conditional: Record<string, string> = {};
  const form = config.listPost ? new URLSearchParams(config.listPost).toString() : undefined;
  if (config.conditionalGet && form === undefined && source.list_etag) conditional["if-none-match"] = source.list_etag;
  if (config.conditionalGet && form === undefined && source.list_last_modified) conditional["if-modified-since"] = source.list_last_modified;
  const res = await request(run, url, source.kind === "api" ? "application/json" : "*/*", config.crawlDelaySeconds, conditional, form);
  const etag = res.headers.get("etag");
  const lastModified = res.headers.get("last-modified");
  // 304: nothing changed since the last check.
  if (res.status === 304) return { items: [], status: 304, etag: source.list_etag, lastModified: source.list_last_modified, hash: source.list_hash, unchanged: true };
  if (!res.ok) return { items: [], status: res.status, etag: null, lastModified: null, hash: null };
  const bytes = await res.arrayBuffer();
  const charset = charsetOf(res, config, bytes);
  const hash = await fingerprint(config.listNoise ? decodeBody(bytes, charset).replace(new RegExp(config.listNoise, "g"), "") : bytes);
  if (!run.full && hash === source.list_hash) return { items: [], status: res.status, etag, lastModified, hash, unchanged: true };
  const body = decodeBody(bytes, charset);
  const items =
    source.kind === "rss"
      ? parseFeed(body, res.url || url, config, run.now)
      : source.kind === "page"
        ? await parsePage(body, res.url || url, config, run.now)
        : parseApi(JSON.parse(body), res.url || url, config, run.now);
  return { items, status: res.status, etag, lastModified, hash };
}

const pageBudgetLeft = (run: Run) => run.pages < LIMITS.pagesPerRun && run.requests < LIMITS.requestsPerRun;

/**
 * Text reads (item pages, `fullText`) return null for "try on a later check":
 * no page budget left, the site is busy, or the item's page failed. It is asked
 * again while the item is new (LIMITS.retryHours); after that the item is saved
 * with what it has.
 */
function later(run: Run, item: FoundItem): FoundItem | null {
  const age = run.now.getTime() - Date.parse(item.publishedAt ?? "");
  return age < LIMITS.retryHours * 3_600_000 ? null : item;
}

/** Spaces and case do not count when a list text is looked for in a page's text. */
const squeeze = (text: string) => text.replace(/\s+/g, "").toLowerCase();

/**
 * Whether the read text already holds the list text: its start (a teaser cut
 * with "…"), or its end (the Commission's feed puts "Press release Brussels,
 * <date>" in front of the first paragraph).
 */
function holds(text: string, listText: string): boolean {
  const read = squeeze(text);
  const list = squeeze(listText).replace(/(\[?(…|\.\.\.)\]?)+$/, "");
  const n = Math.min(list.length, 80);
  return read.includes(list.slice(0, n)) || read.includes(list.slice(list.length - n));
}

/**
 * The read text replaces the list text when it is longer and holds it. When
 * it does not hold it, the list text stays in front (#71: Germany's lead and
 * SAIJ's summary of a norm are not in the text read).
 */
function withText(item: FoundItem, text: string, imageUrl: string | null = null): FoundItem {
  const list = item.text ?? "";
  const merged = text.length <= list.length ? list : !list || holds(text, list) ? text : `${list}\n${text}`;
  return { ...item, text: merged || null, imageUrl: item.imageUrl ?? imageUrl };
}

/**
 * A text as long as LIMITS.maxText took the most CPU a read can take (reading
 * stops there): it uses the rest of the run's pages, so a run reads at most one
 * such text (#71 review: two 198 KB norms took about 10 ms locally, one about 5).
 */
function weigh(run: Run, text: string): string {
  if (text.length >= LIMITS.maxText) run.pages = Math.max(run.pages, LIMITS.pagesPerRun);
  return text;
}

/** What a text read may do with a URL now: read it, never (robots.txt), or later (the site is busy or its robots.txt cannot be read). */
async function mayRead(run: Run, url: string): Promise<"read" | "blocked" | "later"> {
  const u = new URL(url);
  if (run.busy.has(u.host)) return "later";
  const robots = await robotsFor(run, u);
  if (robots.kind === "disallowAll") return "later";
  return isAllowed(robots, u.pathname + u.search) ? "read" : "blocked";
}

/**
 * What a `fullText` JSON read asks for. Mexico's SIDOF answers a bare
 * "application/json" with 406 and sends JSON for this (checked 21 Oct, as did
 * the Commission's and SAIJ's endpoints).
 */
const JSON_ACCEPT = "application/json, */*;q=0.1";

/** One page of a site failed; after `failedPagesPerHost` of them the site counts as busy for the rest of the run. */
function pageFailed(run: Run, host: string): "later" {
  const failed = (run.failed.get(host) ?? 0) + 1;
  run.failed.set(host, failed);
  if (failed >= LIMITS.failedPagesPerHost) run.busy.add(host);
  return "later";
}

/**
 * A GET for an item's text: an HTML page, or JSON. "later" when it is to be
 * asked again on a later check. A site that asks us to wait (429, 503) or
 * cannot be reached is not asked again in this run. Another 5xx, or no answer
 * in time, is this page only: the site's other pages are still read (#71 review:
 * gov.za answered 500 for some notices while others answered). null when the
 * answer cannot be used: another error, not HTML when a page was asked for (a
 * PDF is not downloaded), or bigger than `maxBytes`.
 */
async function getText(
  run: Run,
  url: string,
  kind: "html" | "json",
  config: SourceConfig,
  maxBytes = Infinity,
): Promise<{ res: Response; bytes: ArrayBuffer } | null | "later"> {
  const host = new URL(url).host;
  if (run.requests >= LIMITS.requestsPerRun) return "later";
  let res: Response;
  try {
    res = await request(run, url, kind === "json" ? JSON_ACCEPT : "text/html", config.crawlDelaySeconds);
  } catch (error) {
    if ((error as { name?: unknown } | null)?.name === "TimeoutError") return pageFailed(run, host);
    run.busy.add(host);
    return "later";
  }
  if (res.status === 429 || res.status === 503) {
    run.busy.add(host);
    await res.body?.cancel();
    return "later";
  }
  if (res.status >= 500) {
    await res.body?.cancel();
    return pageFailed(run, host);
  }
  const type = res.headers.get("content-type") ?? "";
  if (!res.ok || (kind === "html" && !type.includes("html")) || Number(res.headers.get("content-length") ?? 0) > maxBytes) {
    await res.body?.cancel();
    return null;
  }
  const bytes = await res.arrayBuffer();
  return bytes.byteLength > maxBytes ? null : { res, bytes };
}

/** Opens an item page for its main text and preview image, if robots.txt and the budget allow. */
async function readItemPage(run: Run, item: FoundItem, config: SourceConfig): Promise<FoundItem | null> {
  if (!pageBudgetLeft(run)) return null;
  const url = item.url.split("#")[0];
  const may = await mayRead(run, url);
  if (may !== "read") return may === "later" ? later(run, item) : item;
  run.pages++;
  const got = await getText(run, url, "html", config);
  if (got === "later") {
    // Nothing was read: the page is free for the next item.
    run.pages--;
    return later(run, item);
  }
  if (!got) return item;
  try {
    const content = await extractContent(
      decodeBody(got.bytes, charsetOf(got.res, config, got.bytes)),
      got.res.url || url,
      config.textSelector,
      LIMITS.maxText,
    );
    return withText(item, weigh(run, content.text), config.pageImage === false ? null : content.imageUrl);
  } catch {
    return item;
  }
}

/**
 * Follows a source's `fullText` steps to the item's whole text (#71), for
 * sources whose item page does not hold it: a JSON data endpoint (European
 * Commission), or a page that links to the text (Argentina). Counts as one page
 * of the budget: each answer is at most LIMITS.fullTextBytes, the steps before
 * the last read only a JSON value or one link, and the last page is read only
 * up to LIMITS.maxText characters (a 198 KB norm: about 3 ms locally, not 25).
 */
async function readFullText(run: Run, item: FoundItem, sourceUrl: string, config: SourceConfig): Promise<FoundItem | null> {
  const steps = [config.fullText ?? []].flat().slice(0, LIMITS.fullTextSteps);
  let value = item.url.split("#")[0];
  let counted = false;
  for (const [i, step] of steps.entries()) {
    const last = i === steps.length - 1;
    // An item the steps do not fit (another kind of link) is saved as it is, without waiting.
    const match = step.from ? value.match(configRegex(step.from)) : [value];
    if (!match) return item;
    const url = onSite((step.url ?? "{0}").replace(/\{(\d+)\}/g, (_, n: string) => match[Number(n)] ?? ""), sourceUrl, config);
    if (!url) return item;
    if (!counted && !pageBudgetLeft(run)) return null;
    const may = await mayRead(run, url);
    if (may !== "read") return may === "later" ? later(run, item) : item;
    if (!counted) run.pages++;
    counted = true;
    const got = await getText(run, url, step.json ? "json" : "html", config, LIMITS.fullTextBytes);
    if (got === "later") {
      // The text was not read: the page is free for the next item.
      run.pages--;
      return later(run, item);
    }
    if (!got) return item;
    try {
      const body = decodeBody(got.bytes, charsetOf(got.res, { encoding: step.encoding }, got.bytes));
      const base = got.res.url || url;
      if (step.json) {
        const data: unknown = JSON.parse(body);
        const found = [step.json].flat().flatMap((path) => getStrings(data, path));
        if (!found.length) return item;
        if (last) return withText(item, weigh(run, htmlToText(found.join("\n"))));
        value = found[0].trim();
      } else if (step.link && !last) {
        const link = await findLink(body, base, step.link);
        if (!link) return item;
        value = link;
      } else {
        return withText(item, weigh(run, (await extractContent(body, base, config.textSelector, LIMITS.maxText)).text));
      }
    } catch {
      return item;
    }
  }
  return item;
}

/** A saved link as checkSource finds it. */
interface Known {
  original_title: string;
  textless: number;
  out_of_feed: number;
  fetched_at: string;
}

/**
 * Reads a saved link again while it is out of the feed (#227), when its text
 * never came (the Élysée's page of 28 Oct, saved without text) or the list now
 * gives it another title (La Moncloa first lists a council's summary under a
 * placeholder and renames it hours later, at the same link). At most once an
 * hour per link, and only with page budget left after the new items. When the
 * text or the title changed, its summary is made again. A link in the feed is
 * never touched. Returns how many were updated.
 */
async function rereadKnown(
  run: Run,
  source: SourceRow,
  config: SourceConfig,
  recent: FoundItem[],
  known: Map<string, Known>,
  expires: string,
): Promise<number> {
  const before = toStoredTime(new Date(run.now.getTime() - LIMITS.rereadMinutes * 60_000));
  const updates: D1PreparedStatement[] = [];
  for (const found of recent) {
    const held = known.get(found.url);
    const title = found.title.slice(0, 500);
    if (!held || !held.out_of_feed || held.fetched_at > before || (!held.textless && held.original_title === title)) continue;
    let read: FoundItem | null | undefined;
    if (config.fullText) read = await readFullText(run, found, source.url, config);
    else if (config.itemPages !== false) read = await readItemPage(run, found, config);
    // No page budget left, or the site asked us to wait: the next check.
    if (read === null) break;
    const text = (read ?? found).text?.slice(0, LIMITS.maxText) || null;
    // SET reads the row as it was: `original_title` and `text` there are the saved ones.
    updates.push(
      run.env.DB.prepare(
        `UPDATE articles SET
           original_title = ?2, fetched_at = ?3, text = COALESCE(?4, text),
           text_expires_at = CASE WHEN ?4 IS NULL THEN text_expires_at ELSE ?5 END,
           summarized_at = CASE WHEN original_title IS ?2 AND text IS COALESCE(?4, text) THEN summarized_at END,
           summary_attempts = CASE WHEN original_title IS ?2 AND text IS COALESCE(?4, text) THEN summary_attempts ELSE 0 END,
           summary_claimed_at = CASE WHEN original_title IS ?2 AND text IS COALESCE(?4, text) THEN summary_claimed_at END
         WHERE url = ?1 AND feed_seq IS NULL`,
      ).bind(found.url, title, toStoredTime(run.now), text, expires),
    );
  }
  if (!updates.length) return 0;
  const results = await run.env.DB.batch(updates);
  return results.reduce((n, r) => n + (r.meta.changes ?? 0), 0);
}

async function checkSource(run: Run, source: SourceRow): Promise<SourceCheck> {
  const check: SourceCheck = { sourceId: source.id, ok: false, httpStatus: null, found: 0, saved: 0, waiting: 0, undated: 0, offSite: 0, reread: 0, error: null, full: run.full, unchanged: false };
  const config = readConfig(source);
  try {
    const url = listUrl(source.url, run.now);
    // Between full checks the list goes by robots.txt as read at the last one, at most an hour ago.
    const blocked = run.full ? await blockedBy(run, url) : null;
    if (blocked) {
      check.error = blocked;
      return check;
    }
    const { items, status, etag, lastModified, hash, unchanged } = await readList(run, source, config, url);
    check.httpStatus = status;
    if (unchanged) {
      check.ok = true;
      check.unchanged = true;
      return check;
    }
    if (status !== 304 && (status < 200 || status >= 300)) {
      check.error = `HTTP ${status}`;
      return check;
    }

    const cutoff = toStoredTime(new Date(run.now.getTime() - LIMITS.maxAgeDays * 86_400_000));
    const fetchedAt = toStoredTime(run.now);
    const seen = new Set<string>();
    const listed = items
      .filter((item) => passesFilters(item, config))
      .map((item) => onSourceSite(item, source.url, config))
      .filter((item): item is FoundItem => {
        if (item === null) check.offSite++;
        return item !== null;
      })
      .filter((item) => {
        if (item.publishedAt === null) check.undated++;
        return item.publishedAt !== null;
      })
      // A time in the future (a missing or wrong zone) would sit on top of the feed: never later than now.
      .map((item) => (item.publishedAt! > fetchedAt ? { ...item, publishedAt: fetchedAt } : item))
      .map((item) =>
        config.newStageIsNewItem && item.publishedAt ? { ...item, url: `${item.url}#${item.publishedAt.slice(0, 10)}` } : item,
      )
      .filter((item) => !seen.has(item.url) && seen.add(item.url));
    check.found = listed.length;
    check.ok = true;

    const recent = listed
      .filter((item) => item.publishedAt! >= cutoff)
      .sort((a, b) => b.publishedAt!.localeCompare(a.publishedAt!))
      .slice(0, LIMITS.itemsPerSource);
    const newest = listed.reduce<string | null>((max, i) => (i.publishedAt && (!max || i.publishedAt > max) ? i.publishedAt : max), null);

    // What is already saved of these links: not saved again, but read again by rereadKnown.
    const known = new Map<string, Known>();
    if (recent.length) {
      const { results } = await run.env.DB.prepare(
        `SELECT url, original_title, text IS NULL AS textless, feed_seq IS NULL AS out_of_feed, fetched_at
         FROM articles WHERE url IN (${recent.map(() => "?").join(", ")})`,
      )
        .bind(...recent.map((i) => i.url))
        .all<Known & { url: string }>();
      for (const r of results) known.set(r.url, r);
    }

    const expires = toStoredTime(new Date(run.now.getTime() + (config.textDays ?? LIMITS.textDays) * 86_400_000));
    const inserts: D1PreparedStatement[] = [];
    const backgrounds = new Map<string, string | null>();
    for (const found of recent.filter((i) => !known.has(i.url)).slice(0, LIMITS.newPerSource)) {
      let item = found;
      // An event's background (#230): the lead of Wikipedia's article on its story.
      if (config.currentEvents && item.background) item = await withBackground(run, item, backgrounds);
      const teaser = (item.text?.length ?? 0) < LIMITS.teaserText;
      // undefined: nothing to read; null: read it on a later check.
      let read: FoundItem | null | undefined;
      if (config.fullText) {
        if (teaser) read = await readFullText(run, item, source.url, config);
      } else if (config.itemPages !== false && (teaser || (!item.imageUrl && config.pageImage !== false))) {
        read = await readItemPage(run, item, config);
      }
      if (read) item = read;
      else if (read === null && teaser) {
        check.waiting++;
        continue;
      }
      inserts.push(
        run.env.DB.prepare(
          `INSERT OR IGNORE INTO articles
             (id, source_id, url, original_title, published_at, date_only, fetched_at, text, text_expires_at, image_url, original_language, author)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        ).bind(
          ulid(run.now.getTime()),
          source.id,
          item.url,
          item.title.slice(0, 500),
          item.publishedAt,
          item.dateOnly ? 1 : 0,
          fetchedAt,
          item.text ? item.text.slice(0, LIMITS.maxText) : null,
          item.text ? expires : null,
          config.images === false ? null : item.imageUrl,
          source.language,
          // Only a story's: a government feed's dc:creator ("admin") is nobody to name (Yurii's review of #271).
          config.stories ? (item.author ?? null) : null,
        ),
      );
    }
    if (inserts.length) {
      const results = await run.env.DB.batch(inserts);
      check.saved = results.reduce((n, r) => n + (r.meta.changes ?? 0), 0);
    }
    check.reread = await rereadKnown(run, source, config, recent, known, expires);

    await run.env.DB.prepare(
      `UPDATE sources SET last_item_at = ?1 WHERE id = ?2 AND ?1 IS NOT NULL AND (last_item_at IS NULL OR last_item_at < ?1)`,
    )
      .bind(newest, source.id)
      .run();

    // Written only when it matters, so a list that differs at every read (config.listNoise takes out
    // what it can) writes nothing between full checks. Remembered only once every new item is saved;
    // with items still waiting, the same list or a 304 next time would hide them until the list changes again.
    if (run.full || check.saved > 0 || check.waiting > 0 || source.list_hash === null) {
      const keep = check.waiting === 0;
      const listHash = keep ? hash : null;
      const listEtag = keep && config.conditionalGet ? etag : null;
      const listModified = keep && config.conditionalGet ? lastModified : null;
      if (listHash !== source.list_hash || listEtag !== source.list_etag || listModified !== source.list_last_modified) {
        await run.env.DB.prepare("UPDATE sources SET list_hash = ?, list_etag = ?, list_last_modified = ? WHERE id = ?")
          .bind(listHash, listEtag, listModified, source.id)
          .run();
      }
    }
  } catch (error) {
    check.ok = false;
    check.error = error instanceof Error ? error.message : String(error);
  }
  return check;
}

/** Whether this check reads the source in full: it was never read, its last check failed, or the last full one is an hour old. */
function isFullCheck(source: SourceRow, now: Date): boolean {
  if (source.last_checked_at === null || source.failed_checks > 0) return true;
  return now.getTime() - Date.parse(source.last_checked_at) >= LIMITS.fullCheckMinutes * 60_000;
}

/**
 * Whether a source is checked this minute: at its turn, every config.everyMinutes, and
 * whenever it is to be read in full. The turn comes from the clock, not from a stored time,
 * so a check that finds nothing new writes nothing.
 */
function isDue(source: SourceRow, now: Date): boolean {
  const every = Math.max(1, readConfig(source).everyMinutes ?? LIMITS.everyMinutes);
  return isFullCheck(source, now) || (Math.floor(now.getTime() / 60_000) + spread(source.id)) % every === 0;
}

/** A number of the source's own, so that sources checked equally often fall on different minutes. */
function spread(id: string): number {
  let n = 0;
  for (let i = 0; i < id.length; i++) n = (n * 31 + id.charCodeAt(i)) % 1_000_003;
  return n;
}

/**
 * One source's check: in production a call of its own (`SourceChecker`,
 * src/index.ts), with its own 10 ms of CPU and 50 outside requests. Every check
 * gives its source a status straight away (item 8), but one that found the same
 * list between full checks has nothing to tell: it writes nothing.
 */
export async function checkOneSource(env: Env, source: SourceRow, options: FetcherOptions = {}): Promise<SourceCheck> {
  const started = Date.now();
  const now = options.now ?? new Date();
  const run: Run = {
    env,
    now,
    full: isFullCheck(source, now),
    // Called as a plain function: Workers reject fetch called as a method of another object.
    fetch: options.fetch ?? ((input, init) => fetch(input, init)),
    sleep: options.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms))),
    requests: 0,
    pages: 0,
    robots: new Map(),
    lastRequest: new Map(),
    busy: new Set(),
    failed: new Map(),
  };
  const check = await checkSource(run, source);
  if (run.full || !check.ok || check.saved > 0) await recordChecks(env, [check], now);
  if (!check.unchanged) {
    // Wall time; Date.now() does not move during CPU work in Workers. CPU time per call is in Workers Observability.
    console.log(JSON.stringify({ message: "fetcher check", wallMs: Date.now() - started, requests: run.requests, pages: run.pages, check }));
  }
  return check;
}

/**
 * Item 6, without a line (#230, Roman, 1 Nov: «почему очередь?»). Every minute
 * each source whose turn it is gets a call of its own: every minute for those
 * that publish as things happen, every LIMITS.everyMinutes for the rest
 * (isDue), never the Kickoff seed rows or blocked sources; one that failed
 * waits LIMITS.failedCheckMinutes. New items from the last 7 days are saved
 * with their text. A call stopped by a limit stops only its own source, and
 * that source is simply checked again at its next turn: it is logged, not
 * counted as the source's failure.
 *
 * Without calls of their own (no `options.call`: no SourceChecker, as under
 * `wrangler dev --remote`), every check would share this run's 10 ms of CPU and
 * the whole run would be stopped. So such a run checks one source, the one read
 * in full longest ago, as before #230, and warns: a missing entrypoint slows the
 * fetcher instead of stopping it (Yurii's review of #274).
 */
export async function runFetcher(env: Env, options: FetcherOptions = {}): Promise<SourceCheck[]> {
  const started = Date.now();
  const now = options.now ?? new Date();
  const { results: listed } = await env.DB.prepare(
    `SELECT id, country, name, kind, url, config, language, last_checked_at, list_etag, list_last_modified, list_hash, failed_checks
     FROM sources
     WHERE status != 'blocked' AND (config IS NULL OR json_extract(config, '$.seed') IS NOT 1)
       AND (failed_checks = 0 OR last_checked_at IS NULL OR last_checked_at <= ?1)
     ORDER BY last_checked_at IS NOT NULL, last_checked_at, id`,
  )
    .bind(toStoredTime(new Date(now.getTime() - LIMITS.failedCheckMinutes * 60_000)))
    .all<SourceRow>();
  const due = listed.filter((source) => isDue(source, now));
  const sources = options.call ? due : due.slice(0, 1);
  if (sources.length < due.length) {
    console.warn(JSON.stringify({ message: "fetcher without SourceChecker: one source a run", sourceId: sources[0].id, waiting: due.length - 1 }));
  }
  const call = options.call ?? ((source: SourceRow) => checkOneSource(env, source, options));
  const settled = await Promise.allSettled(sources.map((source) => call(source)));

  const checks = settled.flatMap((result) => (result.status === "fulfilled" ? [result.value] : []));
  console.log(
    JSON.stringify({
      message: "fetcher run",
      wallMs: Date.now() - started,
      sources: sources.length,
      unchanged: checks.filter((c) => c.unchanged).length,
      saved: checks.reduce((n, c) => n + c.saved, 0),
      failed: checks.filter((c) => !c.ok).map((c) => c.sourceId),
      stopped: settled.flatMap((result, i) => (result.status === "rejected" ? [{ sourceId: sources[i].id, error: String(result.reason) }] : [])),
    }),
  );
  return checks;
}
