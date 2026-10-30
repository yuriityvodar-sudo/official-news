-- #230 step 5, Yurii's review of #260: For you's ranking is kept 5 minutes for
-- each country, language, topic and page size, so its later pages, and other
-- readers in the same country, read their page's articles by id instead of
-- ranking For you's whole 7 days again (about 1,500 D1 rows for Czechia).
-- The Cache API, as the site's menus use it (#251), does nothing on
-- workers.dev, where the API answers. Rows older than an hour are deleted when
-- a new one is written (api/foryou.ts).
CREATE TABLE for_you_rankings (
  home     TEXT NOT NULL,     -- the reader's country (for=)
  lang     TEXT NOT NULL,     -- en, or the feed's language
  topic    TEXT NOT NULL,     -- '' for every topic
  size     INTEGER NOT NULL,  -- the page size it was ranked in (limit)
  at       INTEGER NOT NULL,  -- the moment it was ranked at, in ms (the cursor's `at`)
  seq      INTEGER NOT NULL,  -- the feed's newest feed_seq then (the cursor's `seq`)
  ids      TEXT NOT NULL,     -- JSON: the articles' ids, in order
  top      TEXT NOT NULL,     -- JSON: the top stories' ids, best first
  built_at TEXT NOT NULL,
  PRIMARY KEY (home, lang, topic, size, at)
);
