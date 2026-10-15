-- Item 7: how many times the AI gave an unusable answer for an article. After
-- 3 the summarizer stops trying, so one bad article cannot block the queue.
ALTER TABLE articles ADD COLUMN summary_attempts INTEGER NOT NULL DEFAULT 0;
