-- Item 8: what source health needs to give each source a status after every
-- check. failed_checks counts checks that failed in a row, last_ok_at is the
-- last check that worked, last_error is why the last one failed.
-- Numbered 0007: 0006 is taken by the open feed-order pull request (#38).
ALTER TABLE sources ADD COLUMN failed_checks INTEGER NOT NULL DEFAULT 0;
ALTER TABLE sources ADD COLUMN last_ok_at TEXT;
ALTER TABLE sources ADD COLUMN last_error TEXT;
