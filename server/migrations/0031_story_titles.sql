-- A story's headline in every language (#230, the aggregator step 3): one
-- Workers AI call per story writes it in en, uk, ru, es and de at once, for a
-- country's first stories (src/stories/titles.ts). Kept per story id, so a
-- story is written once; the daily cleanup drops ids older than 3 days.
CREATE TABLE story_titles (
  story_id   TEXT PRIMARY KEY,
  country    TEXT NOT NULL,
  -- JSON {"en", "uk", "ru", "es", "de"}; NULL while no usable answer came.
  titles     TEXT,
  attempts   INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL
);
