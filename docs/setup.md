# Setup status

What exists right now, outside the code. Update this file whenever an account, service or resource is created or changed, in the same commit or pull request. Secrets never go here, only names and where they live.

Last updated: 2026-10-14 (Kickoff skeleton)

## Accounts and services

| What | Status | Owner | Details |
| --- | --- | --- | --- |
| GitHub repo | Created 2026-10-13 | Yurii | `yuriityvodar-sudo/official-news`, public, no licence. Secret scanning and push protection on. Branch protection: not yet, switched on right after the Kickoff skeleton |
| Roman's access to the repo | Active since 2026-10-14 | Yurii | GitHub user `surynets-git`, write access |
| Cloudflare account | Created 2026-10-13 | Yurii (Super Administrator) | Name `NewsApp`, account ID `8dc93578877d397a693094f3e2b01029` (not a secret; it goes in the Worker config) |
| Roman's access to Cloudflare | Active since 2026-10-14 | Yurii | Role Administrator, scope NewsApp account only (cannot manage members or billing) |
| workers.dev address | Created 2026-10-13 | Yurii | `officialnews.workers.dev`; a Worker named `api` would be served at `api.officialnews.workers.dev` |
| Cloudflare Worker | Code ready, not deployed | Item 1 | Worker `api` in `server/`; first deploy and deploy-on-merge come with item 1 (needs a Cloudflare API token as a GitHub Secret) |
| D1 database | Created 2026-10-14 | Kickoff | Name `official-news`, ID `67052e61-5544-4c6d-a182-1321192f3d0a`, region Western Europe. Migrations not applied to it yet (local only so far) |
| Apple Developer team | Yurii joined 2026-10-14 | Roman (Account Holder) | Team "RS Elite Pro s.r.o." (Roman's). Yurii's role: Admin, all apps (checked in App Store Connect, Users and Access, 2026-10-14) |
| App Store Connect app and TestFlight | Not yet | Roman | Roman picks the bundle ID and creates the app on the RS Elite Pro team, plus an internal testing group with both of us |
| App Store Connect API key (for CI uploads) | Not yet | Roman | GitHub Secrets `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`, used by `.github/workflows/testflight.yml`; the key file goes to Yurii through Bitwarden, Yurii adds the secrets |
| Google Play app | Not yet | Open decision | Whose account is still to decide |
| Bundle ID and package name | Placeholder | Roman | The code uses `dev.officialnews.officialNews` (iOS) and `dev.officialnews.official_news` (Android) until Roman picks the final ID; permanent once the App Store app exists. Before creating the app, Roman (Account Holder) must accept Apple's updated developer agreement, shown as a banner in App Store Connect |

## Developer machines

| Tool | Yurii's Mac | Roman's Mac |
| --- | --- | --- |
| Flutter | 3.44.6 (stable) | to check |
| Xcode | 26.3 | to check |
| Node | 24 | to check |
| GitHub CLI | installed | to check |
| CocoaPods | installed | to check |
| Android SDK | installed | to check |
| Java | 8 (Android builds need 17; install at Kickoff) | to check |
