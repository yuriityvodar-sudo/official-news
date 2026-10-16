# Official News

A cross-platform app (iOS and Android) that shows what governments and international bodies officially publish, summarized and translated by AI, newest first. Sources are verified official websites only, never media or trending lists.

Built by Yurii and Roman.

## Where things are

- [`docs/plan.md`](docs/plan.md): the MVP plan: scope, who builds what, shared definitions, costs
- [`docs/decisions.md`](docs/decisions.md): every decision, with its date and reason
- [`docs/contract.md`](docs/contract.md): article format, topics, API, database: what app and backend build against
- [`docs/setup.md`](docs/setup.md): which accounts and services exist right now
- [`CLAUDE.md`](CLAUDE.md): how we work, read automatically by Claude Code
- [`docs/research/`](docs/research): research and tests, such as the live source test of 11 Oct 2026 (`2026-10-11 Live source test.html`, open it in a browser)

## Run it locally

Backend (Cloudflare Worker, needs Node 24):

```bash
cd server && npm install && npm run db:migrate:local && npm run dev
```

It serves the API on http://localhost:8787 with 20 seed articles. Try http://localhost:8787/articles.

App (Flutter 3.44.6, see `app/.fvmrc`), with the backend running:

```bash
cd app && flutter run
```

On the Android emulator add `--dart-define=API_URL=http://10.0.2.2:8787`.

## Status

Kickoff skeleton: app and backend talk to each other locally; CI checks every pull request; the TestFlight workflow is ready for the App Store Connect key. Next: the items in the plan.
