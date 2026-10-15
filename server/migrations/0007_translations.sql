-- Translations (#46, proposed): an article's headline, short summary and
-- summary in another language, written by the translator step from the English
-- ones. One row per article and language. A row exists from the moment a run
-- claims it; it is finished once translated_at is set. The API shows only
-- finished rows and falls back to English for the rest.
-- (0006 is taken by the open feed-order pull request, #38.)
CREATE TABLE article_translations (
  article_id    TEXT NOT NULL REFERENCES articles (id),
  lang          TEXT NOT NULL,              -- e.g. 'uk'; the list is LANGS in server/src/translator/index.ts
  headline      TEXT,
  short_summary TEXT,
  summary       TEXT,
  model         TEXT,                       -- provider and model that wrote it, e.g. 'groq:qwen/qwen3.8-27b'
  translated_at TEXT,                       -- NULL until the translation is stored
  claimed_at    TEXT,                       -- when a run took it; older than 10 minutes means that run was cut off
  attempts      INTEGER NOT NULL DEFAULT 0, -- unusable answers so far; after 3 the article stays in English
  PRIMARY KEY (article_id, lang)
);
