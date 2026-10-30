// Shared by the website tests (#88): the site's handler on the test database,
// articles with their own texts, translations in each queue state, and HTML readers.
import { env } from "cloudflare:workers";
import { vi } from "vitest";
import { handleSite } from "../src/site/handler";
import { CACHE } from "../src/site/respond";
import type { SiteLang } from "../src/site/texts";
import { rowsRead } from "./helpers";
import { CONSENT_JS } from "../src/site/consent";

export const ORIGIN = "https://site.test";

/** A page without our one inline script, the analytics banner's (consent.ts), which every page carries; what is left must have no script at all. */
export const withoutConsentScript = (body: string) => body.replace(`<script>${CONSENT_JS}</script>`, "");
export const siteEnv = () => ({ DB: env.DB, SITE_ORIGIN: ORIGIN });

export async function site(path: string, init: RequestInit = {}, host = "site.test", e = siteEnv()) {
  const response = await handleSite(new Request(`https://${host}${path}`, init), e);
  return { status: response.status, headers: response.headers, body: await response.text() };
}

/**
 * A page as a reader reaches it from a link: an article address without its
 * slug, or with another country or slug, is the site's 301 to the article's
 * own URL (cache kind `moved`), followed once; any other answer is returned
 * as it is. `movedFrom` is set when it was followed.
 */
export async function reach(path: string, init: RequestInit = {}) {
  const first = await site(path, init);
  const location = first.headers.get("location");
  if (first.status !== 301 || first.headers.get("cloudflare-cdn-cache-control") !== CACHE.moved.edge) return first;
  if (!location?.startsWith(`${ORIGIN}/`)) throw new Error(`${path}: a 301 to ${location}`);
  return { ...(await site(location.slice(ORIGIN.length), init)), movedFrom: path };
}

export const stored = (date: Date) => `${date.toISOString().slice(0, 19)}Z`;
export const hoursAgo = (hours: number) => stored(new Date(Date.now() - hours * 3_600_000));

export interface Fixture {
  id: string;
  publishedAt?: string;
  isNews?: number | null;
  released?: boolean;
  sourceId?: string;
  headline?: string | null;
  shortSummary?: string;
  summary?: string;
  decisionType?: string | null;
  originalLanguage?: string;
  originalUrl?: string;
  importance?: number | null;
  /** The AI's topics; `["economy"]` by default. */
  topics?: string[];
}

/** 26-character ids for tests: "01JTEST" and a padded number. */
export const testId = (n: number) => `01JTEST${String(n).padStart(19, "0")}`;

/** An article as the summarizer leaves it (headline, summaries, summarized 1 hour ago); `released` gives it the next feed_seq. */
export async function insertArticle(f: Fixture) {
  const headline = f.headline === undefined ? `Cabinet decision ${f.id.slice(-4)} on the budget` : f.headline;
  await env.DB.prepare(
    `INSERT INTO articles (id, source_id, url, original_title, published_at, fetched_at, headline, short_summary, summary,
                           is_news, importance, decision_type, original_language, summarized_at, topics, tags, feed_seq, added_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?15, '[]',
             CASE WHEN ?14 THEN (SELECT COALESCE(MAX(feed_seq), 0) + 1 FROM articles WHERE feed_seq IS NOT NULL) END,
             CASE WHEN ?14 THEN strftime('%Y-%m-%dT%H:%M:%SZ', 'now') END)`,
  )
    .bind(
      f.id,
      f.sourceId ?? "de-federal-government",
      f.originalUrl ?? `https://www.bundesregierung.de/${f.id}`,
      `Kabinett beschließt ${f.id.slice(-4)}`,
      f.publishedAt ?? hoursAgo(2),
      headline,
      f.shortSummary ?? `The cabinet decided item ${f.id.slice(-4)}.`,
      f.summary ?? `The cabinet decided item ${f.id.slice(-4)}.\n\nThe Bundestag debates it next.`,
      f.isNews === undefined ? 1 : f.isNews,
      f.importance === undefined ? 3 : f.importance,
      f.decisionType === undefined ? "cabinet-decision" : f.decisionType,
      f.originalLanguage ?? "de",
      hoursAgo(1),
      f.released === false ? 0 : 1,
      JSON.stringify(f.topics ?? ["economy"]),
    )
    .run();
}

export type TranslationCase = "published" | "updating" | "failed-same" | "failed-newer" | "queued";

/**
 * A translation row as the translator leaves it: `published`; `updating` (a
 * newer English waits, the old text is shown); `failed-same` (failed for the
 * English its text is of: shown); `failed-newer` (the newer English failed:
 * not shown); `queued` (no text yet).
 */
export async function insertTranslation(id: string, lang: Exclude<SiteLang, "en">, kind: TranslationCase = "published") {
  const hasText = kind !== "queued";
  const state = kind.startsWith("failed") ? "failed" : kind;
  // The text's English: the current one, or an older one for updating / failed-newer.
  const older = kind === "updating" || kind === "failed-newer";
  await env.DB.prepare(
    `INSERT INTO article_translations (article_id, lang, headline, short_summary, summary, model, source_summarized_at,
                                       lang_seq, translated_at, attempts, attempts_source, state, state_at)
     SELECT id, ?2,
            CASE WHEN ?3 THEN ?4 END, CASE WHEN ?3 THEN ?5 END, CASE WHEN ?3 THEN ?6 END, CASE WHEN ?3 THEN 'groq:test' END,
            CASE WHEN ?3 THEN (CASE WHEN ?8 THEN '2026-01-01T00:00:00Z' ELSE summarized_at END) END,
            CASE WHEN ?3 THEN (SELECT COALESCE(MAX(lang_seq), 0) + 1 FROM article_translations WHERE lang = ?2) END,
            CASE WHEN ?3 THEN summarized_at END,
            CASE WHEN ?7 = 'failed' THEN 3 ELSE 0 END, summarized_at, ?7, summarized_at
     FROM articles WHERE id = ?1`,
  )
    .bind(
      id,
      lang,
      hasText ? 1 : 0,
      `[${lang}] Рішення ${id.slice(-4)} про бюджет`,
      `[${lang}] Уряд ухвалив пункт ${id.slice(-4)}.`,
      `[${lang}] Уряд ухвалив пункт ${id.slice(-4)}.\n\nДалі його обговорює Бундестаг.`,
      state,
      older ? 1 : 0,
    )
    .run();
}

/** Article ids linked from a part of a page, in order: `/{lang}/{cc}/{id}…`. */
export const linkedIds = (html: string) => [...html.matchAll(/href="\/[a-z]{2}\/[a-z]{2}\/([0-9A-Z]{26})[^"]*"/g)].map((m) => m[1]);

/** The page's hreflang alternates, without x-default. */
export const hreflangs = (html: string) =>
  [...html.matchAll(/<link rel="alternate" hreflang="([^"]+)" href="([^"]+)">/g)].map((m) => m[1]).filter((l) => l !== "x-default");

/** What the site escapes, for comparing API text with a page. */
export const escaped = (text: string) =>
  text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");

/**
 * The D1 rows `work` reads, `first()` included: the API reads one article with
 * `first()`, which returns no `meta`, so it is run as `all()` here (same rows,
 * same statement) and counted with the rest (helpers.ts counts `all`, `run`
 * and `batch`).
 */
export async function siteRowsRead(work: () => Promise<unknown>): Promise<number> {
  const statement = Object.getPrototypeOf(env.DB.prepare("SELECT 1"));
  const first = vi.spyOn(statement, "first").mockImplementation(async function (this: D1PreparedStatement, column?: unknown) {
    const { results } = await this.all<Record<string, unknown>>();
    const row = results[0] ?? null;
    return typeof column === "string" ? (row?.[column] ?? null) : row;
  });
  try {
    return await rowsRead(work);
  } finally {
    first.mockRestore();
  }
}
