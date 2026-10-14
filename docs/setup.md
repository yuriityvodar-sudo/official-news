# Setup status

What exists right now, outside the code. Update this file whenever an account, service or resource is created or changed, in the same commit or pull request. Secrets never go here, only names and where they live.

Last updated: 2026-10-14

## Accounts and services

| What | Status | Owner | Details |
| --- | --- | --- | --- |
| GitHub repo | Created 2026-10-13 | Yurii | `yuriityvodar-sudo/official-news`, public, no licence. Secret scanning and push protection on. Branch protection: not yet, switched on right after the Kickoff skeleton |
| Roman's access to the repo | Not yet | Yurii | Waiting for Roman's GitHub username (an invite sent to a wrong guess was cancelled on 2026-10-14) |
| Cloudflare account | Created 2026-10-13 | Yurii (Super Administrator) | Name `NewsApp`, account ID `8dc93578877d397a693094f3e2b01029` (not a secret; it goes in the Worker config) |
| Roman's access to Cloudflare | Not yet | Yurii | Invite as Administrator once Roman shares his email |
| workers.dev address | Created 2026-10-13 | Yurii | `officialnews.workers.dev`; a Worker named `api` would be served at `api.officialnews.workers.dev` |
| Cloudflare Worker | Not yet | Kickoff | Created with the backend skeleton |
| D1 database | Not yet | Kickoff | Created with the first migration |
| Apple Developer team | Yurii invited 2026-10-14 | Roman | Team "RS Elite Pro s.r.o." (Roman's); Yurii accepts the email invite within 3 days |
| App Store Connect app and TestFlight | Not yet | Roman | Roman's Apple Developer account; Yurii invited as Admin; internal testing group with both of us |
| App Store Connect API key (for CI uploads) | Not yet | Roman | Stored only as GitHub Secrets |
| Google Play app | Not yet | Open decision | Whose account is still to decide |
| Bundle ID and package name | Not yet | Kickoff | Permanent once created; to agree before creating the app |

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
