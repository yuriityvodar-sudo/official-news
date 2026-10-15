# Contract

The shared definitions both the app and the backend build against. Changed only by agreement, in a pull request that also updates `docs/decisions.md`. The code that implements it: `app/lib/core/article.dart`, `app/lib/core/decision_types.dart`, `app/lib/core/topics.dart`, `server/src/api/index.ts`, `server/migrations/`.

## Article

What the API returns and both screens read.

```json
{
  "id": "01JA2B3C4D5E6F7G8H9J",
  "country": "PL",
  "source": { "id": "pl-mfa", "name": "Ministry of Foreign Affairs", "url": "https://www.gov.pl/web/dyplomacja" },
  "publishedAt": "2026-10-11T14:05:00Z",
  "dateOnly": false,
  "headline": "Poland condemns attack on Riyadh airport",
  "shortSummary": "Poland condemned the attack, which killed 12 people and injured more than 300.",
  "summary": "Poland's foreign ministry condemned … (news-style, 2 to 4 short paragraphs)",
  "decisionType": "decision",
  "originalTitle": "Oświadczenie MSZ ws. ataku w Rijadzie",
  "originalLanguage": "pl",
  "topics": ["foreign-affairs", "security-defence"],
  "tags": ["Saudi Arabia", "Houthis", "aviation"],
  "importance": 4,
  "imageUrl": "https://www.gov.pl/photo/… or null",
  "originalUrl": "https://www.gov.pl/web/dyplomacja/oswiadczenie-msz-ws-ataku-w-rijadzie",
  "feedSeq": 1204,
  "addedAt": "2026-10-11T15:20:00Z"
}
```

- The feed card reads `headline`, `shortSummary` and `imageUrl`; both show `decisionType` as a red label above the headline ("DECISION"); the detail screen reads `summary`. `topics` is set by the AI; the MVP app does not use it yet.
- `feedSeq` is the article's place in the feed: a number given when it becomes visible (the AI marks it an official decision), only ever rising and never changed afterwards. `addedAt` is when that happened (column `added_at`, set with `feed_seq` and, like it, never changed by a later re-summary). The card shows `publishedAt`; the feed order follows `feedSeq`, so an article that appears late lands on top, not among the ones already read (docs/research/2026-10-15 Feed ordering for late items.md).
- Before the AI step has run, `headline`, `shortSummary`, `summary`, `decisionType` and `importance` are `null` and `topics` is `[]`; the app shows `originalTitle` instead.
- `publishedAt` is UTC. `dateOnly: true` means the source gave no time.

## Decision types

A fixed list. The AI gives each news article one of them; the app shows its label above the headline. Code: `app/lib/core/decision_types.dart`.

`law` (Law), `bill` (Bill), `amendment` (Amendment), `proposal` (Proposal), `cabinet-decision` (Cabinet decision), `decision` (Decision), `meeting-agenda` (Meeting agenda), `meeting-outcome` (Meeting outcome)

## Topics

A fixed list. The AI gives each article 1 to 3 of them; topic features (onboarding, a topic feed) come after the MVP.

`foreign-affairs`, `economy`, `security-defence`, `health`, `climate`, `trade`, `technology`, `energy`, `migration`, `elections`, `human-rights`, `science`

## API

Base URL: `https://api.officialnews.workers.dev` (deployed), `http://localhost:8787` (local, `npm run dev` in `server/`).

- `GET /articles?limit=20&cursor=<c>` → `{ "items": [Article], "nextCursor": "…" | null, "top": [Article] }`: news from the last 7 days where `is_news = 1`, in the order they appeared in the feed, newest `feedSeq` first. `limit` is 1 to 50, default 20. `nextCursor` is an opaque string to send back as `cursor` for the next page, `null` on the last page. `top` is filled only on the first page (no `cursor`, no `since`): last 24 hours, highest importance, at most 2 per country, up to 5, listed newest `feedSeq` first; otherwise `[]`. It may be empty, so the app must not depend on it. Top articles also appear in `items`.
- `GET /articles?after=<feedSeq>` → only articles that appeared after that `feedSeq`, late ones included: the "N new" check. The app sends the highest `feedSeq` it holds.
- `GET /articles?since=<ISO time>` → kept for app builds before `after`, which send the publication time of the first article they show: returns articles with a higher `feedSeq` than the newest article published at or before that time (the one those builds show first), so late articles count once and only when they are new.
- `GET /articles/:id` → `Article` shown in the feed, or 404 (hidden articles too).
- `GET /health` → `{ "sources": { "<status>": <count> }, "lastFetcherRun": "<ISO time>" | null }`.
- Errors are JSON `{ "error": "<message>" }`: 400 for a bad `limit`, `cursor`, `after` or `since`, 404, 405 for any method other than GET, 500.

## Database (D1)

Defined in `server/migrations/0001_init.sql`.

- `sources`: id, country, name, kind (`rss` | `page` | `api`), url, config (JSON: selectors for pages), language, verified_by (`domain` | `portal` | `wikidata`), verified_at, licence, status (`active` | `stale` | `moved` | `broken` | `blocked`), last_checked_at, last_item_at, list_etag, list_last_modified (the list's validators, kept by the fetcher for sources with `conditionalGet`; migration `0003`)
  - The source list lives in `docs/sources.csv` (one row per source, with how it was verified as official). The deploy loads it into the live database on every change (`npm run sources:local` for a laptop). Loading adds or updates rows and never changes `status` or the check times, which the fetcher and health checks own.
  - Rows with `config` `{"seed": true}` come from the Kickoff seed so the app has data; the fetcher and the health checks skip them.
- `articles`: id, source_id, url (unique), original_title, published_at, date_only, fetched_at, text, text_expires_at, headline, short_summary, summary, image_url, original_language, topics (JSON), tags (JSON), importance, decision_type, is_news (NULL until the AI decides, 1 = official decision shown in the feed, 0 = hidden), summarized_at, model, summary_attempts (migration `0004`), summary_claimed_at (migration `0005`), feed_seq (unique; migration `0006`, given by the summarizer in the same statement that sets `is_news = 1`), added_at (when feed_seq was given)

Times (`published_at`, `fetched_at`, `summarized_at`, `text_expires_at`) are stored in UTC as `YYYY-MM-DDTHH:MM:SSZ`, without milliseconds, so they sort and compare as text.

## Scheduled job

Two cron triggers (`server/wrangler.jsonc`), each its own run with its own free-plan budget of at most 50 outside requests and 10 ms of CPU. Every minute (`* * * * *`), `runFetcher(env)` (item 6) takes the source with the oldest `last_checked_at`. Every odd minute (`1-59/2 * * * *`), `runSummarizer(env, { maxArticles: 5 })` (item 7) makes one AI call per article. `server/src/index.ts` picks the step by `controller.cron` (`CRONS`). Locally: `npx wrangler dev --test-scheduled`, then open `/__scheduled?cron=1-59/2+*+*+*+*` for the summarizer (any other `cron` runs the fetcher).

What the fetcher writes (`server/src/fetcher/`):
- Only items published in the last 7 days; an item already stored (same `url`) is never saved again. Items without a date are skipped, and a time later than the fetch is stored as the fetch time.
- Only links on the source's own site (its host or a subdomain, or a host in `config.allowedHosts`), always as `https`.
- A run claims its sources first (sets `last_checked_at` in the same statement that picks them), so a run cut off by a limit never blocks the others.
- New articles: `is_news` `NULL` (the AI decides), `original_language` from the source, `text` up to 20,000 characters with `text_expires_at` 30 days after `fetched_at`, `image_url` from the list or the item page's preview image.
- A date without a time is stored at 12:00 UTC (or the fetch time if that is earlier) with `date_only = 1`.
- `url` may end in `#…` when one link holds several items (bill stages); the part before `#` is the page.
- Every check sets `last_checked_at`; `last_item_at` is the newest item seen. `runFetcher` returns one `SourceCheck` per source (`ok`, `httpStatus`, `found`, `saved`, `waiting`, `undated`, `offSite`, `error`), which source health (item 8) can use, and logs it as JSON.

What the summarizer writes (`server/src/summarizer/`, rules in `docs/style-guide.md`):
- It takes articles with no `summarized_at`, newest `fetched_at` first, also those with only a title.
- One call to Workers AI (`@cf/zai-org/glm-4.7-flash`) fills `headline`, `short_summary`, `summary`, `decision_type`, `topics`, `tags`, `importance`, `is_news`, `summarized_at` and `model`. `is_news` 1 puts the article in the feed.
- An unusable answer adds 1 to `summary_attempts`; after 3 the article stays hidden. An error from Workers AI itself (an outage, or the day's free allocation used up) costs no attempt and ends the run.
- A run claims its articles first (sets `summary_claimed_at` in the same statement that picks them), so an overlapping run takes other ones. A claim older than 10 minutes is from a run that was cut off and no longer counts; an error from Workers AI frees the claims at once.
