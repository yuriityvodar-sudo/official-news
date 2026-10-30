-- #230 step 3b: Wikipedia's current events are shown from now on (docs/sources.csv
-- no longer hides them). While hidden, an event the summarizer judged news was
-- stored as not news with decision_type 'event'; those published in the last 2
-- days become news, so the translator translates and releases them. Older ones
-- stay out of the feed: released together they would all come in as the newest.
UPDATE articles SET is_news = 1
WHERE decision_type = 'event' AND is_news = 0 AND feed_seq IS NULL
  AND published_at >= strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-2 days');
