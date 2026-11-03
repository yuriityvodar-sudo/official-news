-- The world's stories (#230, the aggregator step 4, src/stories/world.ts): an
-- event that several countries' outlets carry, found by the English headlines
-- the model wrote for each country's first stories; the app shows them as
-- ticks. A country's titled stories are kept apart from its 50 (`top`, JSON,
-- the stories of `json` that have `titles`), so the world's build reads about
-- 150 KB instead of 900. One row, built in a call of its own.
ALTER TABLE country_stories ADD COLUMN top TEXT;

CREATE TABLE world_stories (
  id        INTEGER PRIMARY KEY CHECK (id = 1),
  -- JSON { "builtAt", "stories": [...] }, the weightiest when built.
  json      TEXT NOT NULL,
  -- JSON { "<country>/<story id>": "<world story id>" }: the next build keeps a world story's id.
  ids       TEXT NOT NULL,
  built_at  TEXT NOT NULL,
  -- A build stopped by a limit waits a few minutes, keeping the stories it has. NULL once a build works.
  failed_at TEXT
);
