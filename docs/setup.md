# Setup status

What exists right now, outside the code. Update this file whenever an account, service or resource is created or changed, in the same commit or pull request. Secrets never go here, only names and where they live.

Last updated: 2026-10-15 (#46, translations)

## Accounts and services

| What | Status | Owner | Details |
| --- | --- | --- | --- |
| GitHub repo | Created 2026-10-13 | Yurii | `yuriityvodar-sudo/official-news`, public, no licence. Secret scanning and push protection on. Branch protection on `main` since 2026-10-14 (after #13): pull request with 1 approval, checks `App (Flutter)` and `Server (Worker)` must pass on an up-to-date branch, new commits dismiss the approval, conversations resolved, applies to admins, no force pushes or deletion |
| Roman's access to the repo | Active since 2026-10-14 | Yurii | GitHub user `surynets-git`, write access |
| Cloudflare account | Created 2026-10-13 | Yurii (Super Administrator) | Name `NewsApp`, account ID `8dc93578877d397a693094f3e2b01029` (not a secret; it goes in the Worker config) |
| Roman's access to Cloudflare | Active since 2026-10-14 | Yurii | Role Administrator, scope NewsApp account only (cannot manage members or billing) |
| workers.dev address | Created 2026-10-13 | Yurii | `officialnews.workers.dev`; a Worker named `api` would be served at `api.officialnews.workers.dev` |
| Cloudflare Worker | Deployed 2026-10-14 | Roman (item 1) | Worker `api` in `server/`, live at `https://api.officialnews.workers.dev`. `.github/workflows/deploy.yml` applies D1 migrations and deploys on every merge to `main` that touches `server/` |
| Workers AI | In use from item 7 | Roman | Binding `AI` in `server/wrangler.jsonc`, model `@cf/zai-org/glm-4.7-flash`. No key; it runs on the NewsApp account's free 10,000 Neurons a day (usage under AI, Workers AI in the dashboard). More than that needs the Workers Paid plan |
| Groq account and API key (`GROQ_API_KEY`) | Account created 2026-10-15; Worker secret not yet | Yurii | Free plan, Yurii's own account at console.groq.com. Locally: one test key, `official-news-test`, kept only in Yurii's `server/.dev.vars` as `GROQ_API_KEY` (see `server/.dev.vars.example`), read by `server/scripts/translate-test.mjs` (`docs/research/2026-10-15 Translation model test.md`) and by the local Worker (`npm run dev`). Deployed: for the translations (#46, after the MVP) Yurii creates a fresh key in the Groq console and puts it straight into the Worker with `npx wrangler secret put GROQ_API_KEY` from `server/`. The value is never in the repo and never passes between us. Without the Worker secret the translator claims nothing, so `?lang=uk` and `?lang=ru` return empty feeds |
| Cloudflare API token for deploys | Created 2026-10-14 | Yurii | Account API token `github-deploy` on NewsApp ("Edit Cloudflare Workers" template plus D1: Edit). Stored only as the GitHub Secret `CLOUDFLARE_API_TOKEN` (as repo owner, only Yurii can manage secrets) |
| D1 database | Created 2026-10-14 | Kickoff | Name `official-news`, ID `67052e61-5544-4c6d-a182-1321192f3d0a`, region Western Europe. Migrations `0001_init` and `0002_seed` applied 2026-10-14 by the deploy workflow |
| Apple Developer team | Yurii joined 2026-10-14 | Roman (Account Holder) | Team "RS Elite Pro s.r.o." (Roman's), team ID `YSF2FQGT86`. Yurii's role: Admin, all apps (checked in App Store Connect, Users and Access, 2026-10-14). Roman accepted the updated Program License Agreement on 2026-10-14. The Paid Applications Schedule still waits in App Store Connect, Business: needed before an App Store submission, not for TestFlight |
| App Store Connect app and TestFlight | Created 2026-10-14 | Roman | App "Official News: Decisions" ("Official News" is taken in the App Store), Apple ID `6822820350`, bundle ID `com.officialnews.app`, SKU `officialnews-ios`, iOS, primary language English (U.S.). Internal TestFlight group "Official News team" with Roman and Yurii; every uploaded build goes to it automatically |
| App Store Connect API key (for CI uploads) | Not yet | Yurii | Yurii creates it himself with his Admin role on the RS Elite Pro team (App Store Connect, Users and Access, Integrations, Team Keys, access App Manager; API access is already enabled for the team) and adds it straight to the GitHub Secrets `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`, used by `.github/workflows/testflight.yml`. The key never passes through Roman |
| Mistral account (translation test) | Created 2026-10-15 | Yurii | Free plan, Yurii's own account at console.mistral.ai. No key: the free plan no longer allows API keys |
| Google Play app | Not yet | Open decision | Whose account is still to decide |
| Bundle ID and package name | Created 2026-10-14 | Roman | `com.officialnews.app` on both platforms: the iOS App ID is registered on the RS Elite Pro team (explicit, no extra capabilities yet), and it is the Android `applicationId`. Permanent |

## Developer machines

| Tool | Yurii's Mac | Roman's Mac |
| --- | --- | --- |
| Flutter | 3.44.6 (stable) | not installed yet |
| Xcode | 26.3 | 27.0 |
| Node | 24 | 22.16 |
| GitHub CLI | installed | installed |
| CocoaPods | installed | installed |
| Android SDK | installed | not installed yet |
| Java | 8 (Android builds need 17; install at Kickoff) | not installed yet |
