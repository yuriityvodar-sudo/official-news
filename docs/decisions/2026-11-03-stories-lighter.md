# A country's stories' build made lighter for a cold call (#230, the aggregator)

- **Decision:** Four changes. The stories stay the same, in the same order, in all 23 countries. This was checked on the live rows of 3 Nov, 07:20 UTC, read both as they were kept until now and as they will be kept from now on.
  - **A day of headlines.** An outlet's row keeps its last 24 hours (`LIMITS.headlineHours`, 48 before), the stories' window.
    - A build reads its country's rows whole: Germany's held 1,714 headlines for the day's 1,052.
    - `GET /headlines` gives the last 24 hours too.
  - **Words as one string.** A headline's `words` is one string, the words separated by spaces, a name's with `^` first (`"zemře texta ^pavel ^žák"`), instead of a list: fewer strings to parse.
    - The fetcher turns the lists kept before into strings when it saves the outlet's row again; until then a build reads both.
    - Also in the fetcher: headlines are ordered by their times' text instead of `localeCompare`. The order is the same, since every stored time is `toStoredTime`'s, and it costs less.
    - A headline retitled after the check has read its 40 loses its old words until a later check reads the new ones. Until now it kept the old title's words.
  - **Words numbered in WebAssembly.** The build writes the 300 headlines' words into the module's memory as UTF-8, a line each. `number` (`server/assembly/stories.ts`) numbers them by a hash of their bytes, in the order a Map numbered them, so the grouping gets the same numbers.
  - **A warm-up at the Worker's start.** The top level of `server/src/stories/index.ts` builds the stories of three made-up headlines (`warmUp`), so a build's call finds its code compiled. Workers do not count a Worker's start in a call's CPU: on a test Worker (2 Nov), a start of about 36 ms showed 1 ms on its call.
- **Why:** Yurii's message #286 asks for the live builds within the 10 ms a call has. After #287 and #288, with every headline's words filled, 20 live builds (2 Nov, 15:58–16:13 UTC) took a median of 14 ms, 5 of them under 10.
  - **What the test Worker showed** (2 Nov, 16:36–16:50 UTC, deleted after): the same work spreads from 7 to 54 ms. A call almost always lands in a fresh isolate, often on another machine (13 isolates for 27 calls), and its code runs there cold. A second build in the same isolate took Germany 8–9 ms. Germany's parse of its rows took 3–7 ms, the grouping 5–12 ms cold.
  - **Cold builds after this change.** Measured on the laptop, one build per fresh process, the median of 5, with the parse of D1's answer included, on the live rows of 3 Nov:

    | Country | Before | After |
    | --- | --- | --- |
    | Germany | 6.8 ms | 3.8 ms |
    | India | 6.3 ms | 3.7 ms |
    | Ukraine | 6.2 ms | 3.9 ms |
    | France | 5.9 ms | 3.5 ms |
    | Spain | 5.9 ms | 3.3 ms |
    | Czechia | 4.8 ms | 2.8 ms |
    | US | 5.2 ms | 2.8 ms |
    | Great Britain | 4.1 ms | 2.4 ms |
    | South Africa | 2.5 ms | 1.2 ms |

    Every country takes 36–52% less.
  - **Where it went,** in Germany's build:
    - D1's answer and the headlines' parse: 4.2 → 2.1 ms, from the day and the one string.
    - The words' numbers: 1.0 → 0.3 ms.
    - The rest of the grouping: 2.0 → 1.3 ms, warmed up by the start.
    - The warm-up adds about 1.8 ms to a Worker's start.
  - **Tried and dropped:** merging the outlets' lists, each kept newest first, instead of sorting a day's thousand headlines. It saved 0.1 ms, since a cold loop is no faster than the sort.
  - **Some calls will still go over 10 ms** on slow machines. Cloudflare tolerates that while it is not consistent: all of 2 Nov's builds were `ok`.
- **Proposed with it,** for Yurii's check of #286: a tail's median build under 10 ms, and no call stopped (`exceededCpu`). Asking every call to be under 10 ms is not something any build can meet when the same work spreads from 7 to 54 ms.
- **Status:** Agreed (Yurii, 3 Nov: his tail after #289's deploy, 08:45 to 08:52 UTC, 33 builds, median 8 ms, none stopped, passed the check agreed on #288)
