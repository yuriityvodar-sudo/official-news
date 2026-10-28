-- #146: the AI chat by subscription. Each subscription's status, from the
-- signed transactions the app sends and Apple's notifications, and the
-- questions asked per day (docs/contract.md, Database).
CREATE TABLE subscriptions (
  original_transaction_id TEXT PRIMARY KEY,
  transaction_id TEXT NOT NULL,
  app_account_token TEXT,
  product_id TEXT NOT NULL,
  environment TEXT NOT NULL CHECK (environment IN ('Production', 'Sandbox')),
  expires_at TEXT NOT NULL,
  revoked_at TEXT,
  last_notification TEXT,
  updated_at TEXT NOT NULL
);

CREATE TABLE chat_usage (
  original_transaction_id TEXT NOT NULL,
  day TEXT NOT NULL,
  questions INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (original_transaction_id, day)
);
