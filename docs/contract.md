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
  "originalUrl": "https://www.gov.pl/web/dyplomacja/oswiadczenie-msz-ws-ataku-w-rijadzie"
}
```

- The feed card reads `headline`, `shortSummary` and `imageUrl`; both show `decisionType` as a red label above the headline ("DECISION"); the detail screen reads `summary`. `topics` is set by the AI; the MVP app does not use it yet.
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

- `GET /articles?limit=20&cursor=<c>` → `{ "items": [Article], "nextCursor": "…" | null, "top": [Article] }`: news from the last 7 days where `is_news = 1`, newest first. `cursor` is an opaque string. `top` only on the first page (last 24 hours, highest importance, at most 2 per country, up to 5) and may be empty, so the app must not depend on it.
- `GET /articles?since=<ISO time>` → only articles newer than that time, for the "new updates" check.
- `GET /articles/:id` → `Article`, or 404.
- `GET /health` → `{ "sources": { "<status>": <count> }, "lastFetcherRun": "<ISO time>" | null }`.

Kickoff state: `/articles` returns the newest 20 news articles and ignores the parameters; item 1 adds the 7-day window, paging, `since` and `top`.

## Database (D1)

Defined in `server/migrations/0001_init.sql`.

- `sources`: id, country, name, kind (`rss` | `page` | `api`), url, config (JSON: selectors for pages), language, verified_by (`domain` | `portal` | `wikidata`), verified_at, licence, status (`active` | `stale` | `moved` | `broken` | `blocked`), last_checked_at, last_item_at
- `articles`: id, source_id, url (unique), original_title, published_at, date_only, fetched_at, text, text_expires_at, headline, short_summary, summary, image_url, original_language, topics (JSON), tags (JSON), importance, decision_type, is_news (NULL until the AI decides, 1 = official decision shown in the feed, 0 = hidden), summarized_at, model

## Scheduled job

`server/src/index.ts` runs every minute: `runFetcher(env)` (item 6) takes the 2 sources with the oldest `last_checked_at`; then `runSummarizer(env, { maxArticles: 5 })` (item 7) makes one AI call per article. One run stays within the free plan: at most 50 outside requests and 10 ms of CPU.
