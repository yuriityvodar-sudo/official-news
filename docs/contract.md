# Contract

The shared definitions both the app and the backend build against. Changed only by agreement, in a pull request that also updates `docs/decisions.md`. The code that implements it: `app/lib/core/article.dart`, `app/lib/core/decision_types.dart`, `app/lib/core/topics.dart`, `server/src/api/index.ts`, `server/src/translator/index.ts` (languages), `server/migrations/`.

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
- Translations (#46, after the MVP): with `?lang=uk` or `?lang=ru` the API returns only articles fully translated into that language. Their `headline`, `shortSummary` and `summary` are in that language, and they have `"lang"` (`"uk"` or `"ru"`). `"feedSeq"` and `"addedAt"` are the article's place in that language's feed (a whole number, higher for a later translation: `lang_seq`) and when it appeared there (UTC: `translated_at`), so the app reads every feed the same way (the English feed gets the same two fields from #38). Every other field stays as it is (`originalTitle` in the original language). With `lang=en`, or without `lang`, the article is exactly as above, without `lang`.

## Decision types

A fixed list. The AI gives each news article one of them; the app shows its label above the headline. Code: `app/lib/core/decision_types.dart`.

`law` (Law), `bill` (Bill), `amendment` (Amendment), `proposal` (Proposal), `cabinet-decision` (Cabinet decision), `decision` (Decision), `meeting-agenda` (Meeting agenda), `meeting-outcome` (Meeting outcome)

## Topics

A fixed list. The AI gives each article 1 to 3 of them; topic features (onboarding, a topic feed) come after the MVP.

`foreign-affairs`, `economy`, `security-defence`, `health`, `climate`, `trade`, `technology`, `energy`, `migration`, `elections`, `human-rights`, `science`

## API

Base URL: `https://api.officialnews.workers.dev` (deployed), `http://localhost:8787` (local, `npm run dev` in `server/`).

- `GET /articles?limit=20&cursor=<c>` → `{ "items": [Article], "nextCursor": "…" | null, "top": [Article] }`: news from the last 7 days where `is_news = 1`, newest first (same time: by `id`). `limit` is 1 to 50, default 20. `nextCursor` is an opaque string to send back as `cursor` for the next page, `null` on the last page. `top` is filled only on the first page (no `cursor`, no `since`): last 24 hours, highest importance, at most 2 per country, up to 5; otherwise `[]`. It may be empty, so the app must not depend on it. Top articles also appear in `items`.
- `GET /articles?since=<ISO time>` → only articles published after that time, for the "new updates" check; pages with `cursor` like the feed.
- `GET /articles/:id` → `Article` shown in the feed, or 404 (hidden articles too).
- `lang` (#46) on both: `en`, `uk` or `ru` (the list is `LANGS` in `server/src/translator/index.ts`, plus `en`). `en`, or no `lang`, is the English feed above, unchanged. With `uk` or `ru`, consistency comes first: an article shows in that language only when its translation is finished, never as English mixed in.
  - `GET /articles?lang=uk&limit=20&cursor=<c>` → the same shape, with only the news above (last 7 days, `is_news = 1`) that has a finished translation into that language, the latest translated first (`feedSeq` of that feed), so one translated late lands on top, never between ones already read. `nextCursor` and `cursor` page that language's feed; a cursor of another feed is a 400. `after=<feedSeq>` (of that language's feed) returns only articles translated after that one (the "N new" check), late ones included. `since` keeps only articles published after that time. `top` (first page only: no `cursor`, `since` or `after`) is chosen as above from the translated articles.
  - `GET /articles/:id?lang=uk` → the translated `Article`, or 404 when the article is not translated into that language: not yet, or never (after 3 unusable answers).
- `GET /health` → `{ "sources": { "<status>": <count> }, "lastFetcherRun": "<ISO time>" | null }`.
- Errors are JSON `{ "error": "<message>" }`: 400 for a bad `limit`, `cursor`, `since`, `lang` or (with `lang`) `after`, 404, 405 for any method other than GET, 500.

## Database (D1)

Defined in `server/migrations/0001_init.sql`.

- `sources`: id, country, name, kind (`rss` | `page` | `api`), url, config (JSON: selectors for pages), language, verified_by (`domain` | `portal` | `wikidata`), verified_at, licence, status (`active` | `stale` | `moved` | `broken` | `blocked`), last_checked_at, last_item_at, list_etag, list_last_modified (the list's validators, kept by the fetcher for sources with `conditionalGet`; migration `0003`)
  - The source list lives in `docs/sources.csv` (one row per source, with how it was verified as official). The deploy loads it into the live database on every change (`npm run sources:local` for a laptop). Loading adds or updates rows and never changes `status` or the check times, which the fetcher and health checks own.
  - Rows with `config` `{"seed": true}` come from the Kickoff seed so the app has data; the fetcher and the health checks skip them.
- `articles`: id, source_id, url (unique), original_title, published_at, date_only, fetched_at, text, text_expires_at, headline, short_summary, summary, image_url, original_language, topics (JSON), tags (JSON), importance, decision_type, is_news (NULL until the AI decides, 1 = official decision shown in the feed, 0 = hidden), summarized_at, model, summary_attempts (migration `0004`), summary_claimed_at (migration `0005`)
- `article_translations` (migration `0007`, #46): article_id, lang, headline, short_summary, summary, model (`groq:<model>` that wrote it), source_summarized_at (the article's `summarized_at` when the English was translated), lang_seq, translated_at, claimed_at, attempts, attempts_source (the `summarized_at` the attempts count for). One row per article and language (primary key `article_id, lang`). A row exists from the moment a translator run claims it, and is finished once `lang_seq` is set.
  - `lang_seq`: the order of that language's feed. When an article's first translation into a language is stored, the same statement gives it the language's highest `lang_seq` plus 1, and `translated_at`; neither ever changes. A unique index on (`lang`, `lang_seq`) refuses a number given twice.
  - All or nothing: a CHECK constraint lets a row have either none of headline, short_summary, summary, model, source_summarized_at, lang_seq and translated_at, or all of them (the three texts not empty).

Times (`published_at`, `fetched_at`, `summarized_at`, `text_expires_at`, `translated_at`, `claimed_at`, `source_summarized_at`, `attempts_source`) are stored in UTC as `YYYY-MM-DDTHH:MM:SSZ`, without milliseconds, so they sort and compare as text.

## Scheduled job

Two cron triggers (`server/wrangler.jsonc`), each its own run with its own free-plan budget of at most 50 outside requests and 10 ms of CPU. Every minute (`* * * * *`), `runFetcher(env)` (item 6) takes the source with the oldest `last_checked_at`. Every odd minute (`1-59/2 * * * *`), `runSummarizer(env, { maxArticles: 5 })` (item 7) makes one AI call per article. `server/src/index.ts` picks the step by `controller.cron` (`CRONS`). Locally: `npx wrangler dev --test-scheduled`, then open `/__scheduled?cron=1-59/2+*+*+*+*` for the summarizer (any other `cron` runs the fetcher).

The translator (#46) has no trigger of its own: a newly added Cloudflare trigger never activated (#50). It joins the one-trigger step rotation that #50 brings, as `runTranslator(env, { maxTranslations: TRANSLATIONS_PER_RUN })` (2: one article in both languages).

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

What the translator writes (`server/src/translator/`). Consistency first, speed second: an article shows in a language only once its translation is complete and checked.
- News articles in the feed (`is_news = 1`, summary fields and `summarized_at` filled, last 7 days), newest `published_at` first. One AI call per article and language: headline, short summary and summary from English into the language, nothing else. The other fields are never translated.
- Providers per language, in order, from one constant (`TRANSLATORS`): Ukrainian `groq:qwen/qwen3.8-27b`, then `groq:openai/gpt-oss-120b`; Russian `groq:openai/gpt-oss-120b`, then `groq:qwen/qwen3.8-27b`; `max_tokens` 700 (Groq counts it against Qwen's free 1,000 output tokens a minute). Groq needs the Worker secret `GROQ_API_KEY`; without it nothing is claimed and the run logs `translator skipped`. No Workers AI for translations for now (`workers-ai:<model>` works in the same constant if that changes).
- The answer is checked as a whole: valid JSON with all three fields, not cut off, each at most twice the English length (plus 20 characters), the summary with the English's number of paragraphs, and in the language: Cyrillic letters in every field; for Ukrainian at least one of і, ї, є, ґ and none of ы, э, ъ, ё; for Russian none of і, ї, є, ґ. Latin names and acronyms are fine.
- No missing information: every number of each English field must be in the same translated field, compared by value, so the language's own format passes (1,250,000 = 1 250 000, 3.5% = 3,5 %, 11:59pm = 23:59). A date written 15.10.2026 needs each of its parts; 5575/2026 is two numbers (`server/src/translator/numbers.ts`).
- All or nothing: the three fields, the model and `source_summarized_at` are stored in one statement, which also gives a first translation its `lang_seq` and `translated_at`. A partial or unusable answer stores nothing.
- English changes: when the article's `summarized_at` is newer than the translation's `source_summarized_at`, it is translated again. The old translation is served until the new one is stored in its place (same `lang_seq` and `translated_at`); a translation of an older English never replaces a newer one.
- A run claims its translations first (inserts or updates the rows with `claimed_at` in the same statement that picks them), so an overlapping run takes other ones; a claim older than 10 minutes no longer counts.
- A provider that fails for a reason that is not the article's (HTTP 429, 5xx, network, quota) is skipped for the rest of the run and the next one is tried; when none answers, the claims are freed at once (by primary key), no attempt is counted, and the translation waits for a later run.
- An unusable answer adds 1 to `attempts` and keeps the claim, so the next try waits 10 minutes. After 3 the article does not show in that language, until its English changes (the attempts count per English version, `attempts_source`).
- Logs one `translator start` line (what it claimed) before any AI call and one `translator run` line with the result per article and language and the provider used.
