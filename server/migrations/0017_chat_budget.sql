-- #146, Roman 27 Oct: the AI chat's limit counts what the answers cost, not
-- how many there are (docs/contract.md, Database). Each day's cost per
-- subscription, the questions bought in packs (a wallet that never expires),
-- and each pack credited once, so a refund can take it back.
ALTER TABLE chat_usage ADD COLUMN spent_micros INTEGER NOT NULL DEFAULT 0;

CREATE TABLE chat_wallet (
  original_transaction_id TEXT PRIMARY KEY,
  extra_micros INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL
);

CREATE TABLE chat_credits (
  transaction_id TEXT PRIMARY KEY,
  original_transaction_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  micros INTEGER NOT NULL,
  environment TEXT NOT NULL CHECK (environment IN ('Production', 'Sandbox')),
  revoked_at TEXT,
  created_at TEXT NOT NULL
);
