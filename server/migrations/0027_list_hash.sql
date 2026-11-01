-- The fetcher without a line (#230, Roman, 1 Nov): a fingerprint of the list a
-- source answered with, so a check that finds it unchanged parses nothing and
-- writes nothing.
ALTER TABLE sources ADD COLUMN list_hash TEXT;
