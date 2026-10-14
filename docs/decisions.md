# Decisions

Newest first. Every decision that changes how we build goes here, through a pull request, with its date and reason. "Proposed" means waiting for the other person's confirmation.

| Date | Decision | Why | Status |
| --- | --- | --- | --- |
| 2026-10-14 | Roman chooses the bundle ID and creates the app in App Store Connect (RS Elite Pro team), with a TestFlight internal group for both of us | His Apple account hosts the app; Yurii asked Roman to own this step | Agreed |
| 2026-10-13 | Until Roman joins the repo, setup changes (accounts, docs) go straight to `main` by Yurii and are listed in `docs/setup.md`. From Roman's first access, every change goes through a pull request | Roman reads the repo as it stands; nothing waits in an open pull request | Agreed |
| 2026-10-13 | Cloudflare account `NewsApp` created by Yurii; workers.dev address `officialnews.workers.dev` | Agreed on our call that Yurii creates Cloudflare | Agreed |
| 2026-10-13 | Repo `yuriityvodar-sudo/official-news`, public, no licence for now | Public makes branch protection and Actions minutes free; no licence keeps all rights while the business model is open. A licence can be added later | Agreed |
| 2026-10-13 | Accounts: Yurii creates the GitHub repo and the Cloudflare account and invites Roman. Roman's Apple Developer account hosts App Store Connect and TestFlight, with Yurii added as Admin. Roman creates the App Store Connect API key for CI | Agreed on our call; Yurii as Admin can upload builds and manage TestFlight on his own | Agreed |
| 2026-10-13 | Google Play: whose account hosts the Android app | Not discussed yet | Open |
| 2026-10-13 | The plan is a proposal, not a constraint; documentation lives in the repo and is updated in the same pull request as the change | Roman asked that decisions stay documented and current | Agreed |
| 2026-10-12 | TestFlight builds on demand (manual GitHub Actions run, any branch); CI checks run automatically on every pull request | Avoid a new build on every merge; we build when we want to test | Agreed |
| 2026-10-12 | Shared Flutter core (`app/lib/core/`) and the scheduled handler stubs are built in the Kickoff | Both screens and both scheduled jobs depend on them | Proposed |
| 2026-10-12 | Secrets: five rules (nothing in the repo; one home per secret; own logins; shared keys via a password-manager vault; spending limits and rotation) | Public repo | Proposed |
| 2026-10-11 | Stack: Flutter app; Cloudflare Workers, Cron Triggers and D1; AI via Workers AI or Claude Haiku, chosen by the summary test in item 7 | One place for the backend, free tier covers the MVP, existing Cloudflare experience | Agreed |
| 2026-10-11 | Fetcher runs every minute and checks 2 sources per run | Stays within the free plan's per-run limits (50 requests, 10 ms CPU) | Proposed |
| 2026-10-11 | MVP = Kickoff + 8 items; Yurii owns 2, 3, 5, 6; Roman owns 1, 4, 7, 8 | Balanced split; each owner builds a whole story | Proposed |
| 2026-10-11 | Favorites, country filter, search, accounts and push notifications move after the MVP | Keep the MVP to the core loop: news in, summarized, shown | Agreed |
| 2026-10-11 | Official sources only; show the latest published items by date; never trending or media sites | The product is what governments officially say | Agreed |
| 2026-10-11 | GitHub flow: one repo, protected `main`, every pull request approved by the other person | First team project for both; every change seen by both | Agreed |
