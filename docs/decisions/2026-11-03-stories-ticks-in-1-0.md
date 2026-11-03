# Stories and ticks are in iOS 1.0

- **Decision:** the first App Store release (1.0, #137) includes the aggregator's stories in For you (the cards and the story's page, #284, #285) and the ticks (the world stories in the feed with the AI chat about them, #291, #293; the app part still to build).
- **Why:** Yurii, 3 Nov: "let's add it to our first version". The stories are on `main` already and the free limits hold with them: on 3 Nov, D1 read 2.2 million rows in 24 hours of 5 million and wrote 29,000 of 100,000; Worker requests are about 42,000 a day of 100,000 (estimated in #274, #279, #281); story builds' median CPU is 8 ms (#289); the AI headlines are capped at 24 calls an hour, after the summaries (#290, #292).
- **What it means for the release:** the submission waits for the ticks' app part and a `store` build from `main` that has both, checked on the phone. The App Store listing's content rights and description mention the news outlets' headlines and links (never their text), and the AI chat about a tick.
- **Status:** Agreed (Yurii, 3 Nov).
