-- Schema from docs/contract.md.

CREATE TABLE sources (
  id              TEXT PRIMARY KEY,
  country         TEXT NOT NULL,
  name            TEXT NOT NULL,
  kind            TEXT NOT NULL CHECK (kind IN ('rss', 'page', 'api')),
  url             TEXT NOT NULL,
  config          TEXT,                 -- JSON: selectors for pages
  language        TEXT,
  verified_by     TEXT CHECK (verified_by IN ('domain', 'portal', 'wikidata')),
  verified_at     TEXT,
  licence         TEXT,
  status          TEXT NOT NULL DEFAULT 'active'
                  CHECK (status IN ('active', 'stale', 'moved', 'broken', 'blocked')),
  last_checked_at TEXT,
  last_item_at    TEXT
);

CREATE INDEX sources_last_checked ON sources (last_checked_at);

CREATE TABLE articles (
  id                TEXT PRIMARY KEY,
  source_id         TEXT NOT NULL REFERENCES sources (id),
  url               TEXT NOT NULL UNIQUE,
  original_title    TEXT NOT NULL,
  published_at      TEXT NOT NULL,      -- ISO 8601, UTC
  date_only         INTEGER NOT NULL DEFAULT 0,
  fetched_at        TEXT NOT NULL,
  text              TEXT,
  text_expires_at   TEXT,
  headline          TEXT,
  short_summary     TEXT,
  summary           TEXT,               -- news-style
  image_url         TEXT,
  original_language TEXT,
  topics            TEXT,               -- JSON: 1-3 ids from the fixed topic list
  tags              TEXT,               -- JSON
  importance        INTEGER,
  is_news           INTEGER,            -- NULL until the AI decides; 1 = official decision (shown), 0 = hidden
  decision_type     TEXT,               -- one id from the fixed decision-type list; NULL until the AI decides
  summarized_at     TEXT,
  model             TEXT
);

CREATE INDEX articles_feed ON articles (is_news, published_at DESC);
CREATE INDEX articles_unsummarized ON articles (summarized_at) WHERE summarized_at IS NULL;
