import type { Env } from "../env";
import { parseApi } from "./api";
import { parseFeed } from "./feed";
import { extractContent, parsePage } from "./page";
import { type Robots, isAllowed, robotsFromResponse } from "./robots";
import { decodeBody, toStoredTime, ulid } from "./text";
import { type FoundItem, type SourceConfig, type SourceRow, configRegex, readConfig } from "./types";

export const USER_AGENT = "OfficialNewsBot/0.1 (+https://github.com/yuriityvodar-sudo/official-news)";

/** Limits that keep one run inside the free plan (50 outside requests, 10 ms CPU). */
export const LIMITS = {
  sourcesPerRun: 2,
  /** Newest items looked at per check. */
  itemsPerSource: 20,
  /** New items saved per check; the rest are saved on the next check. */
  newPerSource: 10,
  /** Item pages opened per run, for text and image. */
  pagesPerRun: 4,
  requestsPerRun: 40,
  /** The feed shows 7 days, so older items are never saved. */
  maxAgeDays: 7,
  /** List text shorter than this is completed from the item page. */
  minText: 200,
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
  /** New items left for the next check (no page budget left to read their text). */
  waiting: number;
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
}

async function request(run: Run, url: string, accept: string, crawlDelaySeconds = 0): Promise<Response> {
  if (run.requests >= LIMITS.requestsPerRun) throw new Error("request budget for this run used up");
  const host = new URL(url).host;
  const last = run.lastRequest.get(host);
  if (crawlDelaySeconds && last !== undefined) {
    const wait = last + crawlDelaySeconds * 1000 - Date.now();
    if (wait > 0) await run.sleep(wait);
  }
  run.requests++;
  run.lastRequest.set(host, Date.now());
  return run.fetch(url, {
    headers: { "user-agent": USER_AGENT, accept },
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

function passesFilters(item: FoundItem, config: SourceConfig): boolean {
  for (const [field, pattern] of Object.entries(config.match ?? {})) {
    if (!configRegex(pattern).test(item[field as "title" | "category"] ?? "")) return false;
  }
  for (const [field, pattern] of Object.entries(config.exclude ?? {})) {
    if (configRegex(pattern).test(item[field as "title" | "category"] ?? "")) return false;
  }
  return true;
}

async function readList(run: Run, source: SourceRow, config: SourceConfig): Promise<{ items: FoundItem[]; status: number }> {
  const res = await request(run, source.url, source.kind === "api" ? "application/json" : "*/*", config.crawlDelaySeconds);
  if (!res.ok) return { items: [], status: res.status };
  const bytes = await res.arrayBuffer();
  const body = decodeBody(bytes, charsetOf(res, config, bytes));
  const items =
    source.kind === "rss"
      ? parseFeed(body, res.url || source.url, config, run.now)
      : source.kind === "page"
        ? await parsePage(body, res.url || source.url, config, run.now)
        : parseApi(JSON.parse(body), res.url || source.url, config, run.now);
  return { items, status: res.status };
}

/** Opens an item page for its main text and preview image, if robots.txt and the budget allow. */
async function readItemPage(run: Run, item: FoundItem, config: SourceConfig): Promise<FoundItem | null> {
  if (run.pages >= LIMITS.pagesPerRun || run.requests >= LIMITS.requestsPerRun) return null;
  if (await blockedBy(run, item.url)) return item;
  run.pages++;
  try {
    const res = await request(run, item.url.split("#")[0], "text/html", config.crawlDelaySeconds);
    if (!res.ok || !(res.headers.get("content-type") ?? "").includes("html")) return item;
    const bytes = await res.arrayBuffer();
    const content = await extractContent(decodeBody(bytes, charsetOf(res, config, bytes)), res.url || item.url, config.textSelector);
    const text = (content.text.length > (item.text?.length ?? 0) ? content.text : item.text) || null;
    return { ...item, text, imageUrl: item.imageUrl ?? content.imageUrl };
  } catch {
    return item;
  }
}

async function checkSource(run: Run, source: SourceRow): Promise<SourceCheck> {
  const check: SourceCheck = { sourceId: source.id, ok: false, httpStatus: null, found: 0, saved: 0, waiting: 0, error: null };
  const config = readConfig(source);
  try {
    const blocked = await blockedBy(run, source.url);
    if (blocked) {
      check.error = blocked;
      return check;
    }
    const { items, status } = await readList(run, source, config);
    check.httpStatus = status;
    if (status < 200 || status >= 300) {
      check.error = `HTTP ${status}`;
      return check;
    }

    const cutoff = toStoredTime(new Date(run.now.getTime() - LIMITS.maxAgeDays * 86_400_000));
    const seen = new Set<string>();
    const listed = items
      .filter((item) => passesFilters(item, config))
      .map((item) =>
        config.newStageIsNewItem && item.publishedAt ? { ...item, url: `${item.url}#${item.publishedAt.slice(0, 10)}` } : item,
      )
      .filter((item) => !seen.has(item.url) && seen.add(item.url));
    check.found = listed.length;
    check.ok = true;

    const recent = listed
      .filter((item) => item.publishedAt === null || item.publishedAt >= cutoff)
      .sort((a, b) => (b.publishedAt ?? "").localeCompare(a.publishedAt ?? ""))
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

    const fetchedAt = toStoredTime(run.now);
    const expires = toStoredTime(new Date(run.now.getTime() + (config.textDays ?? LIMITS.textDays) * 86_400_000));
    const inserts: D1PreparedStatement[] = [];
    for (const found of recent.filter((i) => !known.has(i.url)).slice(0, LIMITS.newPerSource)) {
      let item = found;
      const shortText = (item.text?.length ?? 0) < LIMITS.minText;
      if (config.itemPages !== false && (shortText || !item.imageUrl)) {
        const read = await readItemPage(run, item, config);
        if (read) item = read;
        else if (shortText) {
          check.waiting++;
          continue;
        }
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
          item.publishedAt ?? fetchedAt,
          item.publishedAt === null || item.dateOnly ? 1 : 0,
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
  };

  const { results: sources } = await env.DB.prepare(
    `SELECT id, country, name, kind, url, config, language FROM sources
     WHERE status != 'blocked' AND (config IS NULL OR json_extract(config, '$.seed') IS NOT 1)
     ORDER BY last_checked_at IS NOT NULL, last_checked_at, id
     LIMIT ?`,
  )
    .bind(LIMITS.sourcesPerRun)
    .all<SourceRow>();

  const checks = await Promise.all(sources.map((source) => checkSource(run, source)));

  const checkedAt = toStoredTime(run.now);
  if (sources.length) {
    await env.DB.batch(
      sources.map((s) => env.DB.prepare("UPDATE sources SET last_checked_at = ? WHERE id = ?").bind(checkedAt, s.id)),
    );
  }

  console.log(
    JSON.stringify({
      message: "fetcher run",
      ms: Date.now() - started,
      requests: run.requests,
      pages: run.pages,
      checks,
    }),
  );
  return checks;
}
