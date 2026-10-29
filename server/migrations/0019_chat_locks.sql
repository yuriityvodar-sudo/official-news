-- #219: one question of a subscription at a time takes its share of the AI
-- chat's limit (docs/contract.md, Database), so questions sent together never
-- pass the check together. `token` is the question holding it; a lock left by
-- a Worker that stopped ends at `until`.
CREATE TABLE chat_locks (
  original_transaction_id TEXT PRIMARY KEY,
  token TEXT NOT NULL,
  until TEXT NOT NULL
);
