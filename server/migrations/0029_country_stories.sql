-- Each country's stories (#230, the aggregator, step 2): its outlets' headlines
-- of the last day grouped into stories (src/stories/), one row per country, so
-- GET /stories reads one row. Built by the api Worker's cron when the country's
-- outlets have new headlines; `version` is the newest headline it was built from.
CREATE TABLE country_stories (
  country  TEXT PRIMARY KEY,
  json     TEXT NOT NULL,
  version  TEXT NOT NULL,
  built_at TEXT NOT NULL
);
