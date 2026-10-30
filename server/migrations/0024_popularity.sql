-- #230 step 4: how much a country's readers and media follow an item, from
-- open data (server/src/popularity/), for For you's order (step 5).

-- What the summarizer's one call names for it: up to 2 English Wikipedia
-- articles about what it is about most, and up to 4 English words its news
-- coverage would contain (JSON lists; NULL before #230 step 4).
ALTER TABLE articles ADD COLUMN wikipedia TEXT;
ALTER TABLE articles ADD COLUMN keywords TEXT;
-- When the popularity step last looked at it; NULL: not yet.
ALTER TABLE articles ADD COLUMN popularity_at TEXT;

-- Wikipedia's page views of the item's first Wikipedia article, per language
-- (cs.wikipedia for Czechia, uk for Ukraine…): the readers of that language.
CREATE TABLE article_views (
  article_id TEXT NOT NULL REFERENCES articles (id) ON DELETE CASCADE,
  lang       TEXT NOT NULL,     -- a Wikipedia language: cs, uk, de…
  title      TEXT NOT NULL,     -- the article's title in that language
  views      INTEGER NOT NULL,  -- the most views in one day since the item was published
  usual      INTEGER NOT NULL,  -- the middle day (median) of the 7 days before it
  score      REAL NOT NULL,     -- 0 to 1.5 (popularity/score.ts)
  checked_at TEXT NOT NULL,
  PRIMARY KEY (article_id, lang)
);

-- What a country's own media published about it in the last 48 hours (GDELT):
-- how many of GDELT's answer, and up to 3 of them, headline, outlet and link
-- only (never their text: EU Directive 2019/790, art. 15).
CREATE TABLE article_media (
  article_id TEXT NOT NULL REFERENCES articles (id) ON DELETE CASCADE,
  country    TEXT NOT NULL,     -- ISO 3166-1 alpha-2
  count      INTEGER NOT NULL,
  links      TEXT NOT NULL,     -- JSON: [{"title", "outlet", "url"}]
  score      REAL NOT NULL,     -- 0 to 1 (popularity/score.ts)
  checked_at TEXT NOT NULL,
  PRIMARY KEY (article_id, country)
);
