-- Messages from readers (#220, Yurii 29 Oct): a reader writes from the app
-- (POST /v1/support/messages), we reply on the admin page, and the reply goes
-- back to the app with a push (docs/contract.md). No login: the phone keeps a
-- random id, stored here only as its SHA-256. A conversation is deleted 90
-- days after it was closed or got its last message (the daily cleanup).

-- One conversation. A phone has at most one that is not closed: writing again
-- continues it, writing after it was closed starts a new one.
CREATE TABLE support_threads (
  id                 TEXT PRIMARY KEY,   -- a random UUID, never shown to the app
  device_hash        TEXT NOT NULL,      -- SHA-256 (hex) of the phone's id; the id itself is never stored
  status             TEXT NOT NULL CHECK (status IN ('waiting', 'answered', 'closed')),
  lang               TEXT NOT NULL,      -- the app's language at the reader's latest message: en, uk, ru, es or de
  app                TEXT NOT NULL,      -- the app's version at the reader's latest message, e.g. '1.0.0 (47)'
  push_token         TEXT,               -- the phone's FCM token from its latest message that had one
  reply_push_pending INTEGER NOT NULL DEFAULT 0, -- 1 after a reply from us, until the cron sent its push
  created_at         TEXT NOT NULL,
  updated_at         TEXT NOT NULL,      -- the latest message, from either side
  closed_at          TEXT
);

-- A phone's conversations, newest first: each request reads its latest one.
CREATE INDEX support_threads_device ON support_threads (device_hash, created_at);
-- The replies waiting for their push: a few rows at most, read by every push step.
CREATE INDEX support_threads_push ON support_threads (updated_at) WHERE reply_push_pending = 1;

CREATE TABLE support_messages (
  id          TEXT PRIMARY KEY,          -- a random UUID
  thread_id   TEXT NOT NULL REFERENCES support_threads (id) ON DELETE CASCADE,
  sender      TEXT NOT NULL CHECK (sender IN ('reader', 'team')),
  text        TEXT NOT NULL,
  -- A reader's message: SHA-256 (hex) of the network address and the UTC day,
  -- to count 5 messages a day per address; the address itself is never
  -- stored, and the daily cleanup clears this once the day is over.
  ip_day_hash TEXT,
  created_at  TEXT NOT NULL
);

CREATE INDEX support_messages_thread ON support_messages (thread_id, created_at);
CREATE INDEX support_messages_ip_day ON support_messages (ip_day_hash) WHERE ip_day_hash IS NOT NULL;
