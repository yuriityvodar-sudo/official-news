-- #230 step 3b: Wikipedia's current events are shown from now on (docs/sources.csv
-- no longer hides them; the deploy loads it right after this). The events of the
-- last 2 days are summarized again as shown ones: with the event prompt of #244,
-- and an event both Wikipedias report once (summarizer/twins.ts). They are marked
-- claimed now, so the summarizer takes them after CLAIM_MINUTES (10), when the
-- Worker of this deploy runs, not the one before it. Older events stay out of the
-- feed: released together, they would all come in as the newest.
UPDATE articles SET summarized_at = NULL, summary_attempts = 0, summary_claimed_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
WHERE source_id IN ('ww-wikipedia-en', 'ww-wikipedia-ru') AND feed_seq IS NULL
  AND published_at >= strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-2 days');
