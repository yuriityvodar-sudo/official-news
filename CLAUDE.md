# Official News: working rules

Two people build this app, Yurii and Roman, each with their own Claude Code. These rules keep both setups in step. `docs/plan.md` has the full plan; this file is the short version Claude Code must follow.

## Documentation is part of every change

- `docs/plan.md` is the plan and `docs/decisions.md` is the decision log. They are the single source of truth.
- A pull request that changes a decision (scope, the article format, the API, the database, an account, a tool) updates `docs/decisions.md`, and `docs/plan.md` where it is affected, in the same pull request.
- Decisions made on a call go into `docs/decisions.md` the same day, through a pull request.
- The website (`server/src/site/`, #88) shows the app's texts (`app/lib/l10n/app_*.arb`, the publisher and dates in `info_pages.dart`, the languages in `feed_language.dart`) and `docs/source-credits.csv` through generated files: after changing a text the site shows, run `npm run site:texts` in `server/` and commit the result (`npm test` says when).
- Anything created outside the code (an account, a Worker, a database, a key, an App Store entry) is recorded in `docs/setup.md` in the same change: what it is, who owns it, where it lives. Never the secret value itself.
- The plan proposes approaches; it does not restrict how something is built. A better approach is welcome: propose it in the pull request or an issue, and record it once agreed.

## How we work (GitHub flow)

- `main` always works. No direct pushes; every change goes through a pull request approved by the other person.
- One branch per issue: `feature/<issue#>-short-name` or `fix/<issue#>-short-name`.
- Small pull requests, each ending with a visible result: under about 500 changed lines of code (tests and docs aside); bigger work is split by screen or by step. Reviewed within a day; reviewing is planned work, not an interruption.
- At most three open pull requests per person. Past that, the next piece waits (research, docs, a prototype) until one merges.
- Merging (changed 30 Oct 2026): every merge goes through GitHub's merge queue ("Merge when ready"; `gh pr merge` does the same). The queue tests each approved pull request on top of the latest `main` and merges it, one at a time, so a branch never has to be updated by hand and nobody re-approves a change because `main` moved. A new commit on a pull request still clears its approval. Before: branches had to be up to date with `main`, and 14 merges on 30 Oct took over 20 re-approvals.
- The reviewer's Claude Code leaves review comments on GitHub; the author's Claude Code works through them and flags anything that needs a human decision; the reviewer approves.
- CI checks run on every pull request. TestFlight builds are on demand only (manual GitHub Actions run).
- One person per issue at a time: assign yourself before starting. Never push to someone else's branch; comment on their pull request instead.
- **Messages between us are issues labelled `message`, assigned to the person they are for.** A comment on a pull request can be missed; a message issue cannot. At the start of every session, before any other work, each Claude Code runs `gh issue list --label message --assignee <its human's GitHub login> --state open`, shows each open message to its human word for word (quotes included), and asks for an answer. The human, or their Claude on their word, comments "Acknowledged (name, date)" and closes the issue. A message counts as delivered only once it is acknowledged; the sender's Claude checks for that.

## Who builds what

We start with these owners and can change them as we go (agreed 14 Oct 2026). To take over an item owned by the other person, agree in its issue first, then reassign it. One person per issue at a time: the assignee is the only one building it, and the other person reviews the pull request.

| Item | Owner |
| --- | --- |
| 0 Kickoff | Yurii and Roman together |
| 1 API on Cloudflare | Roman |
| 2 Design of feed and article detail | Yurii |
| 3 Feed screen | Yurii |
| 4 Article detail screen | Roman |
| 5 Source list | Yurii |
| 6 Fetcher | Yurii |
| 7 AI summaries | Roman |
| 8 Source health and cleanup | Roman |
| 9 Translations | Yurii |

After the MVP, towards the App Store release (call, 16 Oct; each is an issue assigned to its owner, details in `docs/plan.md`):

| Item | Owner |
| --- | --- |
| #63 Better AI headlines and summaries (prompt), backward compatible | Roman |
| #56 Article text layout | Roman |
| #64 Settings screen (no login) | Yurii |
| #65 Domain and app name | Yurii |
| #66 Feed redesign (cards, font, UI) | Yurii |
| #60 Analytics, #62 Push notifications | Yurii |
| #67 Categories, #68 Where filter (all countries, groups, one country) | Yurii |

## Fixed principles (change only by agreement, in a pull request)

- Reliable sources, with their licences respected (#230, Roman, 29 Oct; replaces "official sources only"): official websites for decisions, Wikipedia's current events and open-licensed news for events, open data for popularity (Wikipedia page views, GDELT). Other media only as a headline and a link, never their text. Every item shows where it comes from.
- The shared definitions in `docs/plan.md` (repo layout, article format, API, database). From the Kickoff they live in `docs/contract.md`.
- One AI call per article for its summary, run once on the server and stored (an unusable answer is asked again, at most 3 tries in all); translations add one call per language (#46).
- Paid AI only for the chat: the AI chat by subscription (#146) is the one exception to the line above, one call per subscriber's question, paid for by the subscription. Summaries and translations stay on free tiers.
- The fetcher works in small runs (every minute, 1 source) to stay within Cloudflare's free limits.
- Never bypass CAPTCHAs or bot checks on source websites; respect `robots.txt`.

## Secrets (the repo is public)

- Nothing secret is ever committed: no keys, tokens, certificates or passwords.
- CI keys live in GitHub Secrets; runtime keys are Cloudflare Worker secrets; local keys go in `.dev.vars` or `.env`, which git ignores.
- A key never travels between us (no chat, email or shared vault): whoever creates it puts it straight into its home. Only Yurii, the repo owner, can add GitHub Secrets, so he creates the keys CI needs.
- Commit a `.env.example` with variable names and empty values instead.
- If a secret is ever committed, rotate it at once and tell the other person; deleting the commit is not enough.
