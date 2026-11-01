-- News outlets (#230, the aggregator, Roman, 1 Nov): their headlines and links
-- only, never their text (docs/outlets.csv). Checked by the fetcher like the
-- sources, with the same status columns, but kept apart from `sources`: the
-- API's country filters read every row of `sources`.
--
-- One row per outlet: `headlines` holds its last 48 hours as JSON, newest
-- first ([{"title", "url", "publishedAt"}]), so a check that finds new ones
-- writes this one row, and nothing needs cleaning up (D1's free 100,000 rows
-- written and 5 million read a day).
CREATE TABLE outlets (
  id                 TEXT PRIMARY KEY,
  country            TEXT NOT NULL,
  name               TEXT NOT NULL,
  -- The feed.
  url                TEXT NOT NULL,
  -- The outlet's own site: a link elsewhere is not kept.
  site               TEXT NOT NULL,
  language           TEXT NOT NULL,
  config             TEXT,
  status             TEXT NOT NULL DEFAULT 'active'
                     CHECK (status IN ('active', 'stale', 'moved', 'broken', 'blocked')),
  failed_checks      INTEGER NOT NULL DEFAULT 0,
  last_checked_at    TEXT,
  last_ok_at         TEXT,
  last_error         TEXT,
  last_item_at       TEXT,
  list_hash          TEXT,
  list_etag          TEXT,
  list_last_modified TEXT,
  headlines          TEXT NOT NULL DEFAULT '[]'
);

CREATE INDEX outlets_country ON outlets (country);
