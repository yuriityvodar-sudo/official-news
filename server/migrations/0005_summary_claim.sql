-- Item 7: when a summarizer run took the article. A run claims its articles
-- before calling the model, so an overlapping run cannot summarize them twice;
-- a claim older than 10 minutes is from a run that was cut off.
ALTER TABLE articles ADD COLUMN summary_claimed_at TEXT;
