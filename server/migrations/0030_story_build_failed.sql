-- A country whose stories' build failed (its call stopped by a limit) waits
-- 30 minutes before it is tried again, instead of taking a call every run
-- (Yurii's review of #281). NULL once a build works.
ALTER TABLE country_stories ADD COLUMN failed_at TEXT;
