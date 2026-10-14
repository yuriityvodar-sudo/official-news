# Setup status

What exists right now, outside the code. Update this file whenever an account, service or resource is created or changed, in the same commit or pull request. Secrets never go here, only names and where they live.

Last updated: 2026-10-14 (item 1)

## Accounts and services

| What | Status | Owner | Details |
| --- | --- | --- | --- |
| GitHub repo | Created 2026-10-13 | Yurii | `yuriityvodar-sudo/official-news`, public, no licence. Secret scanning and push protection on. Branch protection on `main` since 2026-10-14 (after #13): pull request with 1 approval, checks `App (Flutter)` and `Server (Worker)` must pass on an up-to-date branch, new commits dismiss the approval, conversations resolved, applies to admins, no force pushes or deletion |
| Roman's access to the repo | Active since 2026-10-14 | Yurii | GitHub user `surynets-git`, write access |
| Cloudflare account | Created 2026-10-13 | Yurii (Super Administrator) | Name `NewsApp`, account ID `8dc93578877d397a693094f3e2b01029` (not a secret; it goes in the Worker config) |
| Roman's access to Cloudflare | Active since 2026-10-14 | Yurii | Role Administrator, scope NewsApp account only (cannot manage members or billing) |
| workers.dev address | Created 2026-10-13 | Yurii | `officialnews.workers.dev`; a Worker named `api` would be served at `api.officialnews.workers.dev` |
| Cloudflare Worker | Deployed 2026-10-14 | Roman (item 1) | Worker `api` in `server/`, live at `https://api.officialnews.workers.dev`. `.github/workflows/deploy.yml` applies D1 migrations and deploys on every merge to `main` that touches `server/` |
| Cloudflare API token for deploys | Created 2026-10-14 | Yurii | Account API token `github-deploy` on NewsApp ("Edit Cloudflare Workers" template plus D1: Edit). Stored only as the GitHub Secret `CLOUDFLARE_API_TOKEN` (as repo owner, only Yurii can manage secrets) |
| D1 database | Created 2026-10-14 | Kickoff | Name `official-news`, ID `67052e61-5544-4c6d-a182-1321192f3d0a`, region Western Europe. Migrations `0001_init` and `0002_seed` applied 2026-10-14 by the deploy workflow |
| Apple Developer team | Yurii joined 2026-10-14 | Roman (Account Holder) | Team "RS Elite Pro s.r.o." (Roman's). Yurii's role: Admin, all apps (checked in App Store Connect, Users and Access, 2026-10-14) |
| App Store Connect app and TestFlight | Not yet | Roman | Roman picks the bundle ID and creates the app on the RS Elite Pro team, plus an internal testing group with both of us |
| App Store Connect API key (for CI uploads) | Not yet | Roman | GitHub Secrets `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`, used by `.github/workflows/testflight.yml`; the key file goes to Yurii through Bitwarden, Yurii adds the secrets |
| Google Play app | Not yet | Open decision | Whose account is still to decide |
| Bundle ID and package name | Placeholder | Roman | The code uses `dev.officialnews.officialNews` (iOS) and `dev.officialnews.official_news` (Android) until Roman picks the final ID; permanent once the App Store app exists. Before creating the app, Roman (Account Holder) must accept Apple's updated developer agreement, shown as a banner in App Store Connect |

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
