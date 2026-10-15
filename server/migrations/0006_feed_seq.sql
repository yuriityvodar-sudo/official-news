-- The feed's order: a number given to an article when it becomes visible
-- (the AI marks it as an official decision), never changed afterwards. It only
-- goes up, so an article that appears late lands on top of the feed, never in
-- the middle of what a reader already saw (docs/research/2026-10-15 Feed
-- ordering for late items.md). The publication date stays on the card.
ALTER TABLE articles ADD COLUMN feed_seq INTEGER;

-- Articles already visible get numbers in the order they became visible.
UPDATE articles
SET feed_seq = (
  SELECT COUNT(*) FROM articles b
  WHERE b.is_news = 1
    AND (b.summarized_at < articles.summarized_at
         OR (b.summarized_at = articles.summarized_at AND b.id <= articles.id))
)
WHERE is_news = 1;

-- One number per article; a duplicate would be a bug, so the database refuses it.
CREATE UNIQUE INDEX articles_feed_seq ON articles (feed_seq) WHERE feed_seq IS NOT NULL;
