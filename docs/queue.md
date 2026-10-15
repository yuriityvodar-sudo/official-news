# The translation queue

How to see and manage the translations (#46). What the states mean, and the tables, are in `docs/contract.md` (Database, and "What the translator writes").

Every news article of the 7-day feed waits in the queue once per enabled language: `queued` → `translating` → `published`. On the way it can be `retrying` (an unusable answer, or no provider answered), `failed` (3 unusable answers, with the reason), `updating` (its English was summarized again; the old text stays visible until the new one is published) or `skipped` (it left the feed). Every change of state is logged with its time.

**Release together** (Yurii, 15 Oct): the feed is the same in every language. A summarized decision is shown nowhere, English included, until every enabled language that is not paused has published it (or failed it 3 times). Then the translator's run releases it: it gets its `feed_seq` and appears in English and every language at once. A post that failed 3 times in a language is released anyway and is missing from that language only. So a language that cannot translate holds back the whole feed, until it is paused: automatically after 2 hours of its provider being down, or by hand.

## See it

`GET /queue` on the API shows each language: its switch (`paused`, `pausedReason`: `manual` or `auto: provider down since …`; `downSince`: since when its provider has not answered), how many translations are in each state, how many were published in the last 24 hours, how long the oldest waiting one has waited, and when the last one was published. `release` shows how many summarized decisions wait for their release, and for how long the oldest has waited.

```sh
curl -s https://api.officialnews.workers.dev/queue
```

A growing `oldestWaitingAgeMinutes` with nothing `translating` means the language is paused, has no provider key (the `translator skipped` or `waiting` lines in `wrangler tail` say so), or its provider is down (`retrying`, with `last_error`, and `downSince`). A growing `release.oldestWaitingAgeMinutes` means some language is holding the feed back: look for the one with `downSince` set or a backlog. After 2 hours down it is paused by itself and the feed goes on without it.

## Automatic pause

- A language is **down** from the first try that no provider answered (every model down, rate limited, out of quota; or no key at all). Any answer clears it, also an unusable one: bad answers count as attempts, not as an outage.
- Down for more than **2 hours**: the translator pauses it (`paused_reason` = `auto: provider down since <time>`), so the release stops waiting for it, and `GET /articles?lang=xx` says `"translationsDelayed": true`.
- While paused automatically, it is still **probed**: one translation a run. The first answer unpauses it, and its missing translations fill in at the articles' own places in the feed, so its order still matches English. New articles are taken first, so the catch-up holds back nothing.
- A pause **by hand** (`pause`) is never probed nor undone by the translator; `resume` ends either kind of pause and starts a fresh 2 hours.

## Manage it

`server/scripts/queue.mjs` runs `npx wrangler d1 execute` on the database, so `--remote` needs a wrangler login (`npx wrangler login`). Run it from `server/`, with `--remote` for the live database or `--local` for the one of `npm run dev`; `--db <name>` picks another database from `wrangler.jsonc`. Each write prints the rows it changed.

| What | Command |
| --- | --- |
| Each language's switch and its count per state | `npm run queue -- status --remote` |
| Translations in a state, in a language | `npm run queue -- list --state failed --lang es --remote` (`--limit 50` by default) |
| Every state change of one article, with times and reasons | `npm run queue -- history <article-id> [lang] --remote` |
| One translation again, with fresh tries (a failed one, a stuck one, or a published one to redo) | `npm run queue -- requeue <article-id> <lang> --remote` |
| A whole language again, for example after a prompt change (published ones stay visible until redone, and also if the redo fails; a run translating one at that moment does not store its old answer) | `npm run queue -- requeue-lang <lang> --remote` |
| Only a language's failed ones | `npm run queue -- requeue-lang <lang> --failed --remote` |
| Stop a language for a while: still queued, nothing translated, the feed no longer waits for it | `npm run queue -- pause <lang> --remote`, then `resume <lang>` (also ends an automatic pause) |
| Turn a language off: no longer queued nor waited for; what is published stays | `npm run queue -- disable <lang> --remote` |
| Turn a language on, with its backlog of the feed's 7 days (new articles then wait for it too) | `npm run queue -- enable <lang> --remote` |
| Queue the feed's 7 days for a language again (what is already queued for its English is left alone) | `npm run queue -- backlog <lang> --remote` |

The languages are `uk`, `ru`, `es` and `de` (`LANGS` in `server/src/translator/languages.ts`); German is off by default (Z.ai blocks requests from Cloudflare Workers). Adding one means adding it to `LANGS`, `LANGUAGES` and `TRANSLATORS` in a pull request, then `enable <lang>` once it is deployed: new articles are translated first (the feed waits for them), its 7-day backlog oldest first in between, and each post shows in that language once it is published, at its place in the English feed.

## Timing and limits

- The translator runs every even minute (`0-58/2 * * * *`), up to 4 translations a run: one article in each language, articles waiting for release first, then the oldest English, so a backlog or an outage in one language (a language just enabled, a provider down) never holds back the others' translations. Each run ends with the release. Groq (Ukrainian, Russian, Spanish) and Z.ai (German) each get one request at a time.
- A language back from a long pause (or a key set late) may find articles that left the feed meanwhile: a run marks them `skipped`, up to 4 a run, and they take no place among its translations.
- A new Cloudflare cron schedule can take about an hour to start firing after the deploy (#50). Check `wrangler tail` for `translator` lines an hour after the first deploy before calling it broken.
- Waits: after an unusable answer 10, then 20 minutes; after a try no provider answered 2, 4, 8 … up to 60 minutes, without counting an attempt. A claim older than 10 minutes (a run that was cut off) goes back to `queued`.
- Keys: `GROQ_API_KEY` and `ZAI_API_KEY` are Worker secrets (`docs/setup.md`). Without one, its languages wait in the queue (nothing is lost) and count as down: after 2 hours they are paused automatically.
