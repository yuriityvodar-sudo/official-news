import type { Env } from "../env";
import { parseApi } from "./api";
import { parseFeed } from "./feed";
import { extractContent, findLink, parsePage } from "./page";
import { type Robots, isAllowed, robotsFromResponse } from "./robots";
import { decodeBody, getStrings, htmlToText, toStoredTime, ulid } from "./text";
import { type FilterField, type FoundItem, type SourceConfig, type SourceRow, configRegex, readConfig } from "./types";

export const USER_AGENT = "OfficialNewsBot/0.1 (+https://github.com/yuriityvodar-sudo/official-news)";

/** Limits that keep one run inside the free plan (50 outside requests, 10 ms CPU). */
export const LIMITS = {
  /** One source per run: two often went over 10 ms of CPU and the run was stopped (#40). */
  sourcesPerRun: 1,
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
  error: string | null;
}

export interface FetcherOptions {
  fetch?: typeof fetch;
  now?: Date;
  sleep?: (ms: number) => Promise<void>;
}

/** Per-run state: request budget, robots.txt per site, last request per site. */
interface Run {
  env: Env;
  now: Date;
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

async function request(run: Run, url: string, accept: string, crawlDelaySeconds = 0, extraHeaders: Record<string, string> = {}): Promise<Response> {
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
    headers: { "user-agent": USER_AGENT, accept, ...extraHeaders },
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
}

/**
 * The list's address: `{year}` becomes the current year (UTC), for lists that
 * can only be asked for one year (Brazil's Senate), so the URL needs no change
 * on 1 January.
 */
function listUrl(url: string, now: Date): string {
  return url.replaceAll("{year}", String(now.getUTCFullYear()));
}

async function readList(run: Run, source: SourceRow, config: SourceConfig, url: string): Promise<ListResult> {
  // Servers often match these exactly, so we send back what they sent, never a time of our own.
  const conditional: Record<string, string> = {};
  if (config.conditionalGet && source.list_etag) conditional["if-none-match"] = source.list_etag;
  if (config.conditionalGet && source.list_last_modified) conditional["if-modified-since"] = source.list_last_modified;
  const res = await request(run, url, source.kind === "api" ? "application/json" : "*/*", config.crawlDelaySeconds, conditional);
  const etag = res.headers.get("etag");
  const lastModified = res.headers.get("last-modified");
  // 304: nothing changed since the last check.
  if (res.status === 304) return { items: [], status: 304, etag: source.list_etag, lastModified: source.list_last_modified };
  if (!res.ok) return { items: [], status: res.status, etag: null, lastModified: null };
  const bytes = await res.arrayBuffer();
  const body = decodeBody(bytes, charsetOf(res, config, bytes));
  const items =
    source.kind === "rss"
      ? parseFeed(body, res.url || url, config, run.now)
      : source.kind === "page"
        ? await parsePage(body, res.url || url, config, run.now)
        : parseApi(JSON.parse(body), res.url || url, config, run.now);
  return { items, status: res.status, etag, lastModified };
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

async function checkSource(run: Run, source: SourceRow): Promise<SourceCheck> {
  const check: SourceCheck = { sourceId: source.id, ok: false, httpStatus: null, found: 0, saved: 0, waiting: 0, undated: 0, offSite: 0, error: null };
  const config = readConfig(source);
  try {
    const url = listUrl(source.url, run.now);
    const blocked = await blockedBy(run, url);
    if (blocked) {
      check.error = blocked;
      return check;
    }
    const { items, status, etag, lastModified } = await readList(run, source, config, url);
    check.httpStatus = status;
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

    const known = new Set<string>();
    if (recent.length) {
      const { results } = await run.env.DB.prepare(
        `SELECT url FROM articles WHERE url IN (${recent.map(() => "?").join(", ")})`,
      )
        .bind(...recent.map((i) => i.url))
        .all<{ url: string }>();
      for (const r of results) known.add(r.url);
    }

    const expires = toStoredTime(new Date(run.now.getTime() + (config.textDays ?? LIMITS.textDays) * 86_400_000));
    const inserts: D1PreparedStatement[] = [];
    for (const found of recent.filter((i) => !known.has(i.url)).slice(0, LIMITS.newPerSource)) {
      let item = found;
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
             (id, source_id, url, original_title, published_at, date_only, fetched_at, text, text_expires_at, image_url, original_language)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
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
          item.imageUrl,
          source.language,
        ),
      );
    }
    if (inserts.length) {
      const results = await run.env.DB.batch(inserts);
      check.saved = results.reduce((n, r) => n + (r.meta.changes ?? 0), 0);
    }

    await run.env.DB.prepare(
      `UPDATE sources SET last_item_at = ?1 WHERE id = ?2 AND ?1 IS NOT NULL AND (last_item_at IS NULL OR last_item_at < ?1)`,
    )
      .bind(newest, source.id)
      .run();

    if (config.conditionalGet) {
      // Remember the validators only once every new item is saved; with items still waiting,
      // a 304 next time would hide them until the list changes again.
      const keep = check.waiting === 0;
      await run.env.DB.prepare("UPDATE sources SET list_etag = ?, list_last_modified = ? WHERE id = ?")
        .bind(keep ? etag : null, keep ? lastModified : null, source.id)
        .run();
    }
  } catch (error) {
    check.ok = false;
    check.error = error instanceof Error ? error.message : String(error);
  }
  return check;
}

/**
 * Item 6. Takes the sources with the oldest `last_checked_at` (never the Kickoff
 * seed rows or blocked sources), reads their lists, and saves new items from
 * the last 7 days with their text. Every check moves `last_checked_at`, so a
 * broken source never blocks the others.
 */
export async function runFetcher(env: Env, options: FetcherOptions = {}): Promise<SourceCheck[]> {
  const started = Date.now();
  const run: Run = {
    env,
    now: options.now ?? new Date(),
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

  // Claim the sources before reading them, in one statement: a run that is cut off
  // (CPU or time limit) still moves them to the back of the line, and an overlapping
  // run cannot pick the same sites.
  const { results: sources } = await env.DB.prepare(
    `UPDATE sources SET last_checked_at = ?1
     WHERE id IN (
       SELECT id FROM sources
       WHERE status != 'blocked' AND (config IS NULL OR json_extract(config, '$.seed') IS NOT 1)
       ORDER BY last_checked_at IS NOT NULL, last_checked_at, id
       LIMIT ?2
     )
     RETURNING id, country, name, kind, url, config, language, last_checked_at, list_etag, list_last_modified`,
  )
    .bind(toStoredTime(run.now), LIMITS.sourcesPerRun)
    .all<SourceRow>();
  // Logged before the work: a run stopped for CPU writes no "fetcher run" line, and this
  // one still shows which source it was on.
  if (sources.length) console.log(JSON.stringify({ message: "fetcher start", sources: sources.map((s) => s.id) }));

  const checks = await Promise.all(sources.map((source) => checkSource(run, source)));

  console.log(
    JSON.stringify({
      message: "fetcher run",
      // Wall time; Date.now() does not move during CPU work in Workers. CPU time per run is in Workers Observability.
      wallMs: Date.now() - started,
      requests: run.requests,
      pages: run.pages,
      checks,
    }),
  );
  return checks;
}
