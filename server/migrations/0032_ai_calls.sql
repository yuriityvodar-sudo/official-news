-- The Workers AI calls of the stories' headlines in each hour of the clock
-- (#230, src/stories/titles.ts): at most TITLES.perHour, all countries
-- together, so the summaries always have room in the free 10,000 neurons a
-- day. On 3 Nov the headlines' calls used them up by 08:30 UTC. One row an
-- hour; the daily cleanup drops those older than 2 days.
CREATE TABLE ai_calls (
  -- The hour in UTC, as "2026-11-03T10".
  hour   TEXT PRIMARY KEY,
  titles INTEGER NOT NULL DEFAULT 0
);
