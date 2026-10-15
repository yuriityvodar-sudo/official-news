-- The feed's order: a number given to an article when it becomes visible
-- (the AI marks it as an official decision), never changed afterwards. It only
-- goes up, so an article that appears late lands on top of the feed, never in
-- the middle of what a reader already saw (docs/research/2026-10-15 Feed
-- ordering for late items.md). The publication date stays on the card.
ALTER TABLE articles ADD COLUMN feed_seq INTEGER;
-- When the article appeared in the feed: set together with feed_seq and, like it,
-- never changed by a later re-summary (summarized_at is).
ALTER TABLE articles ADD COLUMN added_at TEXT;

-- Articles already visible get numbers in the order they became visible. A visible
-- row without summarized_at counts by fetched_at, so no two rows share a number and
-- the unique index below cannot fail the deploy.
UPDATE articles
SET feed_seq = (
      SELECT COUNT(*) FROM articles b
      WHERE b.is_news = 1
        AND (COALESCE(b.summarized_at, b.fetched_at) < COALESCE(articles.summarized_at, articles.fetched_at)
             OR (COALESCE(b.summarized_at, b.fetched_at) = COALESCE(articles.summarized_at, articles.fetched_at)
                 AND b.id <= articles.id))
    ),
    added_at = COALESCE(summarized_at, fetched_at)
WHERE is_news = 1;

-- One number per article; a duplicate would be a bug, so the database refuses it.
-- A feed page walks this index newest first.
CREATE UNIQUE INDEX articles_feed_seq ON articles (feed_seq) WHERE feed_seq IS NOT NULL;

-- added_at rises with feed_seq, so the first number given at or after the 7-day edge
-- bounds a page's walk from below: one row read instead of every older one.
CREATE INDEX articles_added_at ON articles (added_at, feed_seq) WHERE feed_seq IS NOT NULL;

-- Visible articles without a number: normally none. An older Worker can still mark
-- articles visible after this migration and before the new code is live (the deploy
-- runs migrations first); the summarizer numbers them through this small index.
CREATE INDEX articles_unnumbered ON articles (id) WHERE is_news = 1 AND feed_seq IS NULL;
