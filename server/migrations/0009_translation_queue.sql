-- The explicit translation queue (#46): a state per article and language, a
-- switch per language (was 0008 until #55 took 0007), every state change logged with its time, and counts per
-- state that GET /queue reads without counting the table. 0008 created the
-- rows; this gives them their state. States (docs/contract.md):
--   queued       waiting for its first translation
--   updating     its English was summarized again; the old translation is shown until the new one is published
--   translating  claimed by a run (claimed_at); after 10 minutes it goes back to queued or updating
--   retrying     waiting until next_attempt_at: an unusable answer (attempts + 1) or no provider answered (outage_retries + 1)
--   published    the translation of the current English is shown
--   failed       3 unusable answers for this English (last_error says why); not shown, until the English changes
--   skipped      the article left the feed (hidden, older than 7 days) or its English is being redone
ALTER TABLE article_translations ADD COLUMN state TEXT NOT NULL DEFAULT 'queued'
  CHECK (state IN ('queued', 'updating', 'translating', 'retrying', 'published', 'failed', 'skipped'));
ALTER TABLE article_translations ADD COLUMN state_at TEXT;            -- when it entered its state
ALTER TABLE article_translations ADD COLUMN next_attempt_at TEXT;     -- retrying: not claimed before this
ALTER TABLE article_translations ADD COLUMN last_error TEXT;          -- why it is retrying, failed or skipped
ALTER TABLE article_translations ADD COLUMN published_at TEXT;        -- when the text shown was published (translated_at: the first time)
ALTER TABLE article_translations ADD COLUMN outage_retries INTEGER NOT NULL DEFAULT 0; -- tries no provider answered, for the backoff; no attempt

-- Rows written by 0008's translator (a preview database) get the state their columns describe.
UPDATE article_translations SET
  state = CASE
    WHEN queued_at IS NOT NULL AND claimed_at IS NOT NULL AND attempts > 0 THEN 'retrying'
    WHEN queued_at IS NOT NULL AND claimed_at IS NOT NULL THEN 'translating'
    WHEN queued_at IS NOT NULL AND lang_seq IS NOT NULL THEN 'updating'
    WHEN queued_at IS NOT NULL THEN 'queued'
    WHEN lang_seq IS NOT NULL AND source_summarized_at IS attempts_source THEN 'published'
    WHEN attempts >= 3 THEN 'failed'
    ELSE 'skipped'
  END,
  next_attempt_at = CASE WHEN queued_at IS NOT NULL AND claimed_at IS NOT NULL AND attempts > 0
                         THEN strftime('%Y-%m-%dT%H:%M:%SZ', claimed_at, '+10 minutes') END,
  claimed_at = CASE WHEN queued_at IS NOT NULL AND attempts > 0 THEN NULL ELSE claimed_at END,
  published_at = translated_at,
  state_at = COALESCE(claimed_at, queued_at, translated_at, strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));

-- The switch per language. Only an enabled language is queued; a paused one is
-- queued but nothing of it is claimed. Changed with server/scripts/queue.mjs.
CREATE TABLE translation_langs (
  lang       TEXT PRIMARY KEY,            -- one of LANGS in server/src/translator/languages.ts
  enabled    INTEGER NOT NULL DEFAULT 0 CHECK (enabled IN (0, 1)),
  paused     INTEGER NOT NULL DEFAULT 0 CHECK (paused IN (0, 1)),
  updated_at TEXT NOT NULL
);
INSERT INTO translation_langs (lang, enabled, paused, updated_at) VALUES
  ('uk', 1, 0, strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  ('ru', 1, 0, strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  ('es', 1, 0, strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  ('de', 1, 0, strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));

-- Every state change, with its time: what the translator did with each article
-- and language. `detail` is the model for published, the reason for retrying,
-- failed, skipped, and for a claim that ran out. Kept 30 days.
CREATE TABLE translation_events (
  article_id TEXT NOT NULL,
  lang       TEXT NOT NULL,
  state      TEXT NOT NULL,
  at         TEXT NOT NULL,
  attempts   INTEGER NOT NULL,
  detail     TEXT
);
CREATE INDEX translation_events_item ON translation_events (article_id, lang, at);
CREATE INDEX translation_events_at ON translation_events (at);

-- How many rows each language has in each state, kept by the triggers below,
-- so GET /queue reads a few rows instead of counting the table.
CREATE TABLE translation_counts (
  lang  TEXT NOT NULL,
  state TEXT NOT NULL,
  n     INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (lang, state)
);
INSERT INTO translation_counts (lang, state, n) SELECT lang, state, COUNT(*) FROM article_translations GROUP BY lang, state;
INSERT INTO translation_events (article_id, lang, state, at, attempts, detail)
  SELECT article_id, lang, state, state_at, attempts, 'migration 0009' FROM article_translations;

-- The database itself logs and counts every state change, whoever makes it
-- (the translator or queue.mjs). A new English for a row in the same state
-- (queued again) is logged too. No INSERT OR IGNORE here: a trigger takes the
-- conflict policy of the statement that fires it (an upsert), so a missing
-- count row is added with NOT EXISTS instead.
CREATE TRIGGER article_translations_insert AFTER INSERT ON article_translations
BEGIN
  INSERT INTO translation_events (article_id, lang, state, at, attempts, detail)
    VALUES (NEW.article_id, NEW.lang, NEW.state, COALESCE(NEW.state_at, strftime('%Y-%m-%dT%H:%M:%SZ', 'now')), NEW.attempts,
            CASE NEW.state WHEN 'published' THEN NEW.model WHEN 'translating' THEN NULL ELSE NEW.last_error END);
  INSERT INTO translation_counts (lang, state, n) SELECT NEW.lang, NEW.state, 0
    WHERE NOT EXISTS (SELECT 1 FROM translation_counts WHERE lang = NEW.lang AND state = NEW.state);
  UPDATE translation_counts SET n = n + 1 WHERE lang = NEW.lang AND state = NEW.state;
END;

CREATE TRIGGER article_translations_state AFTER UPDATE OF state, attempts_source ON article_translations
  WHEN OLD.state IS NOT NEW.state OR OLD.attempts_source IS NOT NEW.attempts_source
BEGIN
  INSERT INTO translation_events (article_id, lang, state, at, attempts, detail)
    VALUES (NEW.article_id, NEW.lang, NEW.state, COALESCE(NEW.state_at, strftime('%Y-%m-%dT%H:%M:%SZ', 'now')), NEW.attempts,
            CASE NEW.state WHEN 'published' THEN NEW.model WHEN 'translating' THEN NULL ELSE NEW.last_error END);
  UPDATE translation_counts SET n = n - 1 WHERE lang = OLD.lang AND state = OLD.state;
  INSERT INTO translation_counts (lang, state, n) SELECT NEW.lang, NEW.state, 0
    WHERE NOT EXISTS (SELECT 1 FROM translation_counts WHERE lang = NEW.lang AND state = NEW.state);
  UPDATE translation_counts SET n = n + 1 WHERE lang = NEW.lang AND state = NEW.state;
END;

CREATE TRIGGER article_translations_delete AFTER DELETE ON article_translations
BEGIN
  UPDATE translation_counts SET n = n - 1 WHERE lang = OLD.lang AND state = OLD.state;
END;

-- The claim reads each language's waiting rows in the order to take them:
-- oldest English first for queued and updating, the earliest due for retrying.
-- Each reads about what it takes, also with a backlog of a paused language.
DROP INDEX article_translations_queue;
CREATE INDEX article_translations_ready ON article_translations (lang, attempts_source, article_id)
  WHERE state IN ('queued', 'updating');
CREATE INDEX article_translations_retry ON article_translations (lang, next_attempt_at) WHERE state = 'retrying';
-- Claims that ran out: each run sends them back to queued.
CREATE INDEX article_translations_claims ON article_translations (claimed_at) WHERE state = 'translating';
-- GET /queue: the oldest waiting per language, and the last published and those of the last 24 hours.
CREATE INDEX article_translations_waiting ON article_translations (lang, queued_at) WHERE queued_at IS NOT NULL;
CREATE INDEX article_translations_published ON article_translations (lang, published_at) WHERE published_at IS NOT NULL;
