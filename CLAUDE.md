# Official News: working rules

Two people build this app, Yurii and Roman, each with their own Claude Code. These rules keep both setups in step. `docs/plan.md` has the full plan; this file is the short version Claude Code must follow.

## Documentation is part of every change

- `docs/plan.md` is the plan and `docs/decisions.md` is the decision log. They are the single source of truth.
- A pull request that changes a decision (scope, the article format, the API, the database, an account, a tool) updates `docs/decisions.md`, and `docs/plan.md` where it is affected, in the same pull request.
- Decisions made on a call go into `docs/decisions.md` the same day, through a pull request.
- Anything created outside the code (an account, a Worker, a database, a key, an App Store entry) is recorded in `docs/setup.md` in the same change: what it is, who owns it, where it lives. Never the secret value itself.
- The plan proposes approaches; it does not restrict how something is built. A better approach is welcome: propose it in the pull request or an issue, and record it once agreed.

## How we work (GitHub flow)

- `main` always works. No direct pushes; every change goes through a pull request approved by the other person.
- One branch per issue: `feature/<issue#>-short-name` or `fix/<issue#>-short-name`.
- Small pull requests, each ending with a visible result. Reviewed within a day.
- The reviewer's Claude Code leaves review comments on GitHub; the author's Claude Code works through them and flags anything that needs a human decision; the reviewer approves.
- CI checks run on every pull request. TestFlight builds are on demand only (manual GitHub Actions run).
- One person per issue at a time: assign yourself before starting. Never push to someone else's branch; comment on their pull request instead.

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

## Fixed principles (change only by agreement, in a pull request)

- Official sources only: verified government and international-body websites, never media, aggregators or trending lists.
- The shared definitions in `docs/plan.md` (repo layout, article format, API, database). From the Kickoff they live in `docs/contract.md`.
- One AI call per article, run once on the server.
- The fetcher works in small runs (every 2 minutes, 1 source) to stay within Cloudflare's free limits.
- Never bypass CAPTCHAs or bot checks on source websites; respect `robots.txt`.

## Secrets (the repo is public)

- Nothing secret is ever committed: no keys, tokens, certificates or passwords.
- CI keys live in GitHub Secrets; runtime keys are Cloudflare Worker secrets; local keys go in `.dev.vars` or `.env`, which git ignores.
- A key never travels between us (no chat, email or shared vault): whoever creates it puts it straight into its home. Only Yurii, the repo owner, can add GitHub Secrets, so he creates the keys CI needs.
- Commit a `.env.example` with variable names and empty values instead.
- If a secret is ever committed, rotate it at once and tell the other person; deleting the commit is not enough.
