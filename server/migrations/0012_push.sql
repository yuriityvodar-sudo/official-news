-- Push notifications (#62, Yurii 16 Oct): breaking decisions only, so a push
-- brings a reader back with something useful. The translator's run sends at
-- most one push per language (FCM topic breaking_<lang>), at most 2 a local day
-- per language and at least 1 (the day's top story at 18:00 when nothing went
-- out), 3 hours apart, never 21:00 to 08:00 in the language's main time zone
-- (server/src/push/index.ts, docs/contract.md).

-- Every push, sent or tried: one row per article and language, so nothing is
-- ever pushed twice in a language, and the daily cap and the spacing are read
-- here. The row is written BEFORE the request to FCM (the claim) and completed
-- after it with message_id or error, so a run cut off in between never sends a
-- second time: a row with neither is counted as sent. When FCM or the setup
-- could not take the message just then (HTTP 401, 403, 408, 429 or 5xx), the
-- claim is deleted again, so a later run tries that article again. No foreign
-- key to articles: it is a log, and stays if an article row is ever removed.
CREATE TABLE push_log (
  article_id TEXT NOT NULL,
  lang       TEXT NOT NULL,           -- 'en' or one of LANGS in server/src/translator/languages.ts
  sent_at    TEXT NOT NULL,           -- when the run claimed it, just before the request to FCM
  topic      TEXT NOT NULL,           -- the FCM topic it went to, e.g. 'breaking_uk'
  message_id TEXT,                    -- FCM's name for the message ('projects/…/messages/…') once FCM accepted it
  error      TEXT,                    -- why it was not sent: FCM refused it, or no answer came; never tried again
  -- 1 when FCM answered that it refused the message itself (HTTP 400 and the
  -- other 4xx it does not retry): it surely did not go out, so it is the only
  -- row the daily cap does not count. A request without an answer (a network
  -- error, the timeout) stays 0: FCM may have sent it.
  refused    INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (article_id, lang)
);

-- A language's pushes by time: the day's count and the last push, a few rows each run.
CREATE INDEX push_log_lang_time ON push_log (lang, sent_at);

-- Released decisions of importance 4 or 5 (BREAKING_IMPORTANCE in
-- server/src/push/index.ts; change both together), by when they were released:
-- each run looks for breaking news in every language here, a few rows instead
-- of the day's 50 decisions.
CREATE INDEX articles_breaking ON articles (added_at) WHERE feed_seq IS NOT NULL AND importance >= 4;

-- Small values the Worker keeps between runs, each with its expiry. Holds the
-- FCM access token (key 'fcm_token:<service account email>'), which Google
-- issues for about an hour: so most runs make no token request and spend no
-- CPU on signing. It is a short-lived token, never the service account's key
-- (that is only the Worker secret FCM_SERVICE_ACCOUNT). Also the push step's
-- pause (key 'fcm_pause:<service account email>', the value says why) after
-- Google gave no token or FCM could not take a message. No API reads this table.
CREATE TABLE kv_cache (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  expires_at TEXT NOT NULL
);
