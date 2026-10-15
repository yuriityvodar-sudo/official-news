# The translation queue

How to see and manage the translations (#46). What the states mean, and the tables, are in `docs/contract.md` (Database, and "What the translator writes").

Every news article of the 7-day feed waits in the queue once per enabled language: `queued` → `translating` → `published`. On the way it can be `retrying` (an unusable answer, or no provider answered), `failed` (3 unusable answers, with the reason), `updating` (its English was summarized again; the old text stays visible until the new one is published) or `skipped` (it left the feed). Every change of state is logged with its time.

## See it

`GET /queue` on the API shows each language: its switch, how many translations are in each state, how many were published in the last 24 hours, how long the oldest waiting one has waited, and when the last one was published.

```sh
curl -s https://api.officialnews.workers.dev/queue
```

A growing `oldestWaitingAgeMinutes` with nothing `translating` means the language is paused, has no provider key (the `translator skipped` or `waiting` lines in `wrangler tail` say so), or its provider is down (`retrying`, with `last_error`).

## Manage it

`server/scripts/queue.mjs` runs `npx wrangler d1 execute` on the database, so `--remote` needs a wrangler login (`npx wrangler login`). Run it from `server/`, with `--remote` for the live database or `--local` for the one of `npm run dev`; `--db <name>` picks another database from `wrangler.jsonc`. Each write prints the rows it changed.

| What | Command |
| --- | --- |
| Each language's switch and its count per state | `npm run queue -- status --remote` |
| Translations in a state, in a language | `npm run queue -- list --state failed --lang es --remote` (`--limit 50` by default) |
| Every state change of one article, with times and reasons | `npm run queue -- history <article-id> [lang] --remote` |
| One translation again, with fresh tries (a failed one, a stuck one, or a published one to redo) | `npm run queue -- requeue <article-id> <lang> --remote` |
| A whole language again, for example after a prompt change (published ones stay visible until redone) | `npm run queue -- requeue-lang <lang> --remote` |
| Only a language's failed ones | `npm run queue -- requeue-lang <lang> --failed --remote` |
| Stop a language for a while: still queued, nothing translated | `npm run queue -- pause <lang> --remote`, then `resume <lang>` |
| Turn a language off: no longer queued; what is published stays | `npm run queue -- disable <lang> --remote` |
| Turn a language on, with its backlog of the feed's 7 days | `npm run queue -- enable <lang> --remote` |
| Queue the feed's 7 days for a language again (what is already queued for its English is left alone) | `npm run queue -- backlog <lang> --remote` |

The languages are `uk`, `ru`, `es` and `de` (`LANGS` in `server/src/translator/languages.ts`). Adding one means adding it to `LANGS`, `LANGUAGES` and `TRANSLATORS` in a pull request, then `enable <lang>` once it is deployed: its 7-day backlog is translated oldest first, and each post shows in that language once it is published, in the language's own order.

## Timing and limits

- The translator runs every even minute (`0-58/2 * * * *`), up to 4 translations a run: one article in each language. Groq (Ukrainian, Russian) and Z.ai (Spanish, German) each get one request at a time.
- A new Cloudflare cron schedule can take about an hour to start firing after the deploy (#50). Check `wrangler tail` for `translator` lines an hour after the first deploy before calling it broken.
- Waits: after an unusable answer 10, then 20 minutes; after a try no provider answered 2, 4, 8 … up to 60 minutes, without counting an attempt. A claim older than 10 minutes (a run that was cut off) goes back to `queued`.
- Keys: `GROQ_API_KEY` and `ZAI_API_KEY` are Worker secrets (`docs/setup.md`). Without one, its languages wait in the queue; nothing is lost.
