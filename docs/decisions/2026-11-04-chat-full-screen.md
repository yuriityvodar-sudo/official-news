# The AI chat opens over the whole screen (#146)

- **Decision:** the AI chat comes up from the bottom over the whole screen, as iOS's full-screen views do, instead of as a sheet with the article stepping back above it. It covers the status bar too and sets the status bar's words itself, and it closes with its glass close button (a full-screen view is not pulled down). The rest of 30 Oct's "The AI chat moves like ChatGPT's" (`docs/decisions.md`) stays: the header folding into the title, the question at the top with its answer written under it, the breathing dot, the answer's Markdown. The paywall, the consent and the top-up stay sheets.
- **Why:** Roman, 4 Nov: «чат должен открываться во весь екран».
- **Status:** Proposed (Roman's Claude, on Roman's word of 4 Nov)
