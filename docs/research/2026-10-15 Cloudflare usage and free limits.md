# Cloudflare usage and free limits

Measured on 2026-10-15 for the NewsApp account (Worker `api`, D1 `official-news`, Workers AI), from Cloudflare's GraphQL Analytics API and `wrangler d1 info`. Time window: the last 24 hours up to about 10:20 UTC. The cron trigger has run since about 16:30 UTC on 14 Oct.

## Summary

Every layer is far below its free limit except CPU per run, which is the one wall today. Issues: #40 (fetcher), #41 (summarizer), #42 (Russia source).

| Layer | Use per day | Free limit | Share |
|---|---|---|---|
| Worker invocations (1,440 cron + about 600 app requests) | about 2,000 | 100,000 | 2% |
| Cron triggers | 1 | 5 per account | |
| Subrequests per run | about 3 on average | 50 | |
| D1 rows read | 64,968 (15 Oct, partial day) | 5,000,000 | 1.3% |
| D1 rows written | 2,670 | 100,000 | 2.7% |
| D1 size | 0.9 MB | 5 GB | ~0% |
| Workers AI | 2,615 Neurons for 167 summaries (14 Oct) | 10,000 Neurons | 26% |
| **CPU per run** | **median 18.6 ms** | **10 ms** | **almost 2× over** |

## CPU per cron run

- 1,066 cron runs: 797 finished, **267 stopped for CPU** (`exceededResources`), 2 client disconnects.
- Finished runs: p25 10 ms, median 18.6 ms, p75 29.5 ms, p90 54 ms, max 210 ms. 74% of them were over the 10 ms limit, so Cloudflare usually lets a run go over.
- Stopped runs by hour (UTC): 22:00 12, 00:00 25, 01:00 36, 04:00 44, 05:00 22, 07:00 54, **08:00 59 of 60**, 09:00 17. Every run watched with `wrangler tail` from 10:25 to 10:40 UTC was stopped, and nothing was saved after 10:05 UTC.
- The stops don't follow our load. The busiest hours (18:00 and 19:00 UTC on 14 Oct, about 70 new articles each) had no stops; 08:00 UTC had 59 stops and 1 new article. Cloudflare seems to enforce the limit at some times and not others, so a run that needs about 19 ms works until it doesn't.
- App (HTTP) requests were not stopped.

### What a stopped run costs

Nothing is lost, but new decisions arrive late:

- The fetcher claims its sources before any request, so the next run moves on to the next sources.
- The list validators (ETag, Last-Modified) are saved only after the new articles, so a stopped run reads the same list again next time.
- The summarizer frees its claims after an error that isn't the article's fault, and such errors don't count as attempts.

At 10:40 UTC: 179 articles, 0 waiting for a summary, and every source checked within the last 10 minutes.

### Where the CPU goes (from the code, to be measured in #40)

- `parseFeed` turns the HTML of **every** item in a feed into text on every check, before keeping the 20 most recent and skipping the ones already saved. Big feeds (Canada's bills, 191 items; Japan, 102) pay for this every time.
- Two sources and up to 5 summaries in one run add up.

## Workers AI

On 14 Oct: 167 calls to `@cf/zai-org/glm-4.7-flash`, 2,615 Neurons, 234,379 input and 36,429 output tokens. That is **about 15.7 Neurons per article** (about 1,400 tokens in, 220 out).

- English only, the free 10,000 Neurons fit about 640 articles a day. Today we make 70 to 170.
- Each extra language written in the same call adds about 8 Neurons. This is an estimate: 220 output tokens at 36,400 Neurons per million output tokens, assuming a translation is about as long as the English. That gives about 420 articles a day with one extra language and about 250 with three.
- Past the daily limit, Workers AI refuses calls until 00:00 UTC. The summarizer treats that as "not the article's fault", so articles wait and nothing is skipped.

## The next limits (in order)

1. **CPU per run:** today (#40, #41).
2. **AI Neurons:** about 640 articles a day in English, fewer with translations (see `Languages and countries to add.md`).
3. **Worker requests:** 100,000 a day, shared by the app and the cron. At a few API calls per app open, that is tens of thousands of opens a day.

## How to check again

From `server/` (Yurii's or Roman's own wrangler login on the NewsApp account):

```bash
npx wrangler d1 info official-news
```

```bash
npx wrangler tail api --format json
```

The CPU and AI numbers come from `POST https://api.cloudflare.com/client/v4/graphql` with the token from `npx wrangler auth token`, using the datasets `workersInvocationsAdaptive` (status, cpuTime quantiles), `workersInvocationsScheduled` (per cron run: status, cpuTimeUs), `aiInferenceAdaptiveGroups` (totalNeurons, tokens) and `d1AnalyticsAdaptiveGroups` (rowsRead, rowsWritten), filtered on account `8dc93578877d397a693094f3e2b01029`.
