# The fetcher has no line: every source every minute, each in a call of its own (#230)

- **Decision:** Every minute the cron run calls `SourceChecker.check` (a `WorkerEntrypoint`, through `ctx.exports`) once per source. The check compares the list with the last one: the SHA-256 of the answer, or a 304 where `conditionalGet` is on. The same list costs one outside request, with nothing parsed and nothing written. New items are saved at once. Once an hour a source is read in full: robots.txt, the list parsed, known items read again (#227). Between full checks the list goes by robots.txt as read at the last one, at most about an hour ago (RFC 9309 allows 24 hours); item pages always read it. A failed source is asked again after 10 minutes, in full, and is broken after 6 failures in a row, about an hour as before. A call stopped by a limit is logged and not counted against its source. `config.listNoise` takes out of the comparison what differs at every read: 4 of the 32 lists read this way need it (Canada's build time, Turkey's token, Korea's counters, Indonesia's category order); the other 28 were the same byte for byte. Replaces "every minute, 1 source" (#40, 15 Oct) and the fast sources of #273, which sped up the line instead of removing it.
- **Why:** Roman, 1 Nov: «кто сказал что один источник за запуск? за какой запуск? почему очередь? скорость должна быть моментальной и не выходить за пределы лимитов». One source a minute made a source wait up to about 40 minutes. The rule dates from 15 Oct, when 267 of 1,066 runs were stopped for CPU with 2 sources and the summarizer in one run.
- **Measured on a temporary Worker** (`cpu-probe`, free plan, deployed on Roman's word and deleted within the hour; a burn of 1 million steps is 4 to 9 ms):

  | Work | Result |
  | --- | --- |
  | 200 calls of about 7 ms each (1.4 s in all) | all 200 finished, 3 rounds of 3 |
  | 100 calls of about 7 ms each (700 ms in all) | all 100 finished, 3 rounds of 3 |
  | One call of 1.4 s | stopped in 2 rounds of 3 |
  | One call of 700 ms | stopped in 2 rounds of 3 |
  | 5 calls forced over the limit | each fails alone (`Worker exceeded CPU time limit`); the caller answers 200 |
  | One call with 60 outside requests | `Too many subrequests by single Worker invocation` |
  | 10 calls with 45 outside requests each (450 in all) | all finished |
  | The caller of 60 calls | 6 ms of CPU |

  So CPU and outside requests are counted per call. Cloudflare's docs mention 32 Worker invocations per request; 200 parallel calls went through, so that limit did not apply here. The probe's own cron did not fire before it was deleted (a new schedule can take about an hour, #50), so a cron-started run is to be checked on the deployed Worker with `wrangler tail api`: `stopped` in the `fetcher run` line, and the CPU of each `SourceChecker` call. Real runs before this change (18 fetcher runs, 1 Nov, one source each): median 18 ms, p90 27, none stopped.
- **Limits per day after this:** Worker calls about 58,000 of 100,000 (37 sources x 1,440 minutes, if calls through `ctx.exports` count: our Worker has Workers Caching on; 4,664 before). The app keeps the other 42,000; if it needs more, sources that publish rarely can be checked less often. D1 rows read about 1.1M of 5M (the run reads the sources table once a minute, unchanged lists read nothing). D1 rows written fall below today's 8,087: a check that finds nothing writes nothing. AI calls do not change. Each site sees one request a minute instead of about one in 40 minutes; one that answers with an error is asked again after 10 minutes.
- **Status:** Proposed (Roman's Claude, on Roman's word of 1 Nov)
