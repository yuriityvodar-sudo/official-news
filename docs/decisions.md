# Decisions

Newest first. Every decision that changes how we build goes here, through a pull request, with its date and reason. "Proposed" means waiting for the other person's confirmation.

| Date | Decision | Why | Status |
| --- | --- | --- | --- |
| 2026-10-14 | Start with the plan's owners (Yurii 2, 3, 5, 6; Roman 1, 4, 7, 8) and share as we go: an item moves to the other person by agreeing in its issue, then reassigning; one person per issue at a time | Roman wants to share the work as we go (#3); Yurii wants it clear who builds what, so we never build the same thing | Agreed |
| 2026-10-14 | The MVP is the feed and the article detail screen, the same for every user, with images on cards and the ministry as publisher with an "Official source" mark. After the MVP: onboarding with topics and a "For you" feed, a full summary per topic and topic analysis, country choice and Local / Global, registration / Sign in with Apple, Saved, Countries tab | Yurii (review of PR #12): topics and countries are a separate feature; keep the MVP small and improve later | Proposed |
| 2026-10-14 | Sources publish official decisions only: laws, amendments, proposals, government and ministry meeting agendas, minutes and outcomes; opinion pieces, interviews and commentary are hidden | Roman (review of PR #12) | Agreed |
| 2026-10-14 | AI summary written as news, facts from the article only, one summary for everyone; the same single call tags 1 to 3 topics from the fixed list of 12 | Roman (#8): the summary is the most valuable part; topic summaries wait for the topic feature | Proposed |
| 2026-10-14 | Article format: `summary` becomes news-style text, new `topics` (fixed list of 12) and `imageUrl` | Follows from #8 and #11 | Proposed |
| 2026-10-14 | G20 only in the MVP; disputed-territory labels after the MVP | #9, #10 | Agreed |
| 2026-10-14 | `docs/plan.md` is accepted by both of us as the starting point for the MVP; remaining open questions are tracked as issues labelled `decision` | Approved by Roman in this pull request | Agreed |
| 2026-10-14 | Roman chooses the bundle ID and creates the app in App Store Connect (RS Elite Pro team), with a TestFlight internal group for both of us | His Apple account hosts the app; Yurii asked Roman to own this step | Agreed |
| 2026-10-13 | Until Roman joins the repo, setup changes (accounts, docs) go straight to `main` by Yurii and are listed in `docs/setup.md`. From Roman's first access, every change goes through a pull request | Roman reads the repo as it stands; nothing waits in an open pull request | Agreed |
| 2026-10-13 | Cloudflare account `NewsApp` created by Yurii; workers.dev address `officialnews.workers.dev` | Agreed on our call that Yurii creates Cloudflare | Agreed |
| 2026-10-13 | Repo `yuriityvodar-sudo/official-news`, public, no licence for now | Public makes branch protection and Actions minutes free; no licence keeps all rights while the business model is open. A licence can be added later | Agreed |
| 2026-10-13 | Accounts: Yurii creates the GitHub repo and the Cloudflare account and invites Roman. Roman's Apple Developer account hosts App Store Connect and TestFlight, with Yurii added as Admin. Roman creates the App Store Connect API key for CI | Agreed on our call; Yurii as Admin can upload builds and manage TestFlight on his own | Agreed |
| 2026-10-14 | Google Play: Yurii's account hosts the Android app, with Roman added as Admin | Apple is on Roman's account; this keeps one store each | Agreed |
| 2026-10-13 | The plan is a proposal, not a constraint; documentation lives in the repo and is updated in the same pull request as the change | Roman asked that decisions stay documented and current | Agreed |
| 2026-10-12 | TestFlight builds on demand (manual GitHub Actions run, any branch); CI checks run automatically on every pull request | Avoid a new build on every merge; we build when we want to test | Agreed |
| 2026-10-12 | Shared Flutter core (`app/lib/core/`) and the scheduled handler stubs are built in the Kickoff | Both screens and both scheduled jobs depend on them | Agreed |
| 2026-10-12 | Secrets: five rules (nothing in the repo; one home per secret; own logins; shared keys via a Bitwarden vault; spending limits and rotation) | Public repo; Bitwarden chosen by Roman (#6) | Agreed |
| 2026-10-11 | Stack: Flutter app; Cloudflare Workers, Cron Triggers and D1; AI via Workers AI or Claude Haiku, chosen by the summary test in item 7 | One place for the backend, free tier covers the MVP, existing Cloudflare experience | Agreed |
| 2026-10-11 | Fetcher runs every minute and checks 2 sources per run | Stays within the free plan's per-run limits (50 requests, 10 ms CPU) | Agreed |
| 2026-10-11 | MVP = Kickoff + 8 items (split changed on 2026-10-14, see above) | Keep the MVP to the core loop | Agreed |
| 2026-10-11 | Favorites, country filter, search, accounts and push notifications move after the MVP | Keep the MVP to the core loop: news in, summarized, shown | Agreed |
| 2026-10-11 | Official sources only; show the latest published items by date; never trending or media sites | The product is what governments officially say | Agreed |
| 2026-10-11 | GitHub flow: one repo, protected `main`, every pull request approved by the other person | First team project for both; every change seen by both | Agreed |
