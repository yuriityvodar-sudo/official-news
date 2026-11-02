# The stories' grouping in WebAssembly (#230, the aggregator)

- **Decision:** The loops of a country's stories' grouping run in WebAssembly. They are the first pass, the second pass for headlines left alone, and each group's headlines in time order with the one nearest its centre.
  - **Source:** `server/assembly/stories.ts`, written in AssemblyScript, a TypeScript-like language. AssemblyScript is pinned as a dev dependency (0.28.20).
  - **Build:** the source is built into `server/src/stories/group.wasm` (3.7 KB, no imports) by `npm run build:wasm`. The built file is committed, so the Worker, its deploy and its tests need no build step. `npm test` checks that the committed file is the source's build (`scripts/wasm.check.mjs`).
  - **What stays in JavaScript (`cluster.ts`):** sorting the headlines, turning their words into numbers, the logs of the weights, and making the 50 weightiest groups into stories.
  - **Equal sums:** the module adds and multiplies in the same order as before, so its sums are the same.
  - **Memory:** one instance per isolate; a build lays out its arrays in the instance's memory and clears its work areas first.
  - This replaces the JavaScript loops of `docs/decisions/2026-11-02-stories-cold-cpu.md`. That decision's other changes stay: the fetcher's words, building only the weightiest stories, and the headlines' check.
- **Why:** With #287 alone, the biggest countries' builds still took 10 to 13 ms cold, against the 10 ms a call has on the free plan: JavaScript runs slowly until it has warmed up, and every StoryBuilder call starts cold. WebAssembly runs at full speed from the start. Roman, 2 Nov: «Подтверди, делай WASM».
  - **Cold builds:** measured on the laptop, one fresh process per build, 5 builds each, with two of the model's answers to check. Each row is main, then #287, then WebAssembly:

    | Country | main | #287 | WebAssembly |
    | --- | --- | --- | --- |
    | India (300 headlines) | 36 ms | 12.6 ms | 5.7 ms |
    | Germany | 26 ms | 12.2 ms | 5.2 ms |
    | Ukraine | 28 ms | 11.5 ms | 4.9 ms |
    | Spain | 30 ms | 11.7 ms | 4.9 ms |
    | France | 24 ms | 10.1 ms | 4.7 ms |
    | Czechia | 17.5 ms | 4.6 ms | 3.8 ms |
    | South Africa | 12 ms | 2.1 ms | 1.7 ms |

    Main's numbers on the laptop are close to Workers' (Yurii: Germany 40, India 29, South Africa 12).
  - **The same stories:** all 23 countries of 1 Nov give main's stories, in main's order.
  - **The alternative, rejected:** fewer headlines per country also fits within 10 ms, but it lost big stories.
- **Status:** Proposed (Roman's Claude, on Roman's word of 2 Nov)
