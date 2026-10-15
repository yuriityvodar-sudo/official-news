-- Translations (#46): an article's headline, short summary and summary in
-- another language, written by the translator step from the English ones.
-- One row per article and language, which is also its place in the
-- translation queue: a row exists from the moment the translator queues the
-- article for that language; it is finished once lang_seq is set. The API shows
-- an article in a language only when its row is finished (docs/contract.md).
-- This migration changes nothing in articles but one new index, so it works
-- with or without 0006 (#38, feed_seq), which is why it is 0007.
CREATE TABLE article_translations (
  article_id           TEXT NOT NULL REFERENCES articles (id),
  lang                 TEXT NOT NULL,     -- e.g. 'uk'; the list is LANGS in server/src/translator/index.ts
  headline             TEXT,
  short_summary        TEXT,
  summary              TEXT,
  model                TEXT,              -- provider and model that wrote it, e.g. 'groq:qwen/qwen3.8-27b'
  source_summarized_at TEXT,              -- articles.summarized_at of the English it was translated from. When the
                                          -- article's is newer, the English changed: it is translated again, and
                                          -- this text is served until the new one is stored
  lang_seq             INTEGER,           -- the order of this language's feed: MAX + 1 for the language when the
                                          -- first translation is stored, never changed, so a late one lands on top
  translated_at        TEXT,              -- when it appeared in this language: set with lang_seq, never changed
  claimed_at           TEXT,              -- when a run took it, or last got an unusable answer for it; older than
                                          -- 10 minutes means it is free again
  attempts             INTEGER NOT NULL DEFAULT 0, -- unusable answers for the English of attempts_source; after 3
                                                   -- it leaves the queue until the English changes
  attempts_source      TEXT,              -- articles.summarized_at of the English the queue holds for it, and the
                                          -- attempts count for; the queue's order, oldest first
  queued_at            TEXT,              -- when that English was queued; NULL when nothing is waiting: translated,
                                          -- out of tries, or the article left the feed
  PRIMARY KEY (article_id, lang),
  -- All or nothing: a row has no translation at all, or every field of one.
  CHECK (
    (lang_seq IS NULL AND translated_at IS NULL AND headline IS NULL AND short_summary IS NULL
     AND summary IS NULL AND model IS NULL AND source_summarized_at IS NULL)
    OR (lang_seq IS NOT NULL AND translated_at IS NOT NULL
        AND headline IS NOT NULL AND headline <> '' AND short_summary IS NOT NULL AND short_summary <> ''
        AND summary IS NOT NULL AND summary <> '' AND model IS NOT NULL AND source_summarized_at IS NOT NULL)
  )
);

-- One number per language: a duplicate would be a bug, so the database refuses it.
-- A language's feed page walks this index newest first, and MAX + 1 reads its last entry.
CREATE UNIQUE INDEX article_translations_lang_seq ON article_translations (lang, lang_seq) WHERE lang_seq IS NOT NULL;

-- translated_at rises with lang_seq, so the first translation of the last 7 days
-- bounds a page's walk from below: one row read instead of every older one.
CREATE INDEX article_translations_lang_time ON article_translations (lang, translated_at, lang_seq) WHERE lang_seq IS NOT NULL;

-- The queue: what waits, oldest English first. A run claims from here, so it
-- reads about what it takes, not the feed's 7 days.
CREATE INDEX article_translations_queue ON article_translations (attempts_source, article_id, lang) WHERE queued_at IS NOT NULL;

-- The newest English queued for a language, where the next run starts looking.
CREATE INDEX article_translations_source ON article_translations (lang, attempts_source);

-- News by when its English was written, so the translator finds what is new
-- or re-summarized without reading the feed's 7 days.
CREATE INDEX articles_news_summarized ON articles (summarized_at) WHERE is_news = 1;
