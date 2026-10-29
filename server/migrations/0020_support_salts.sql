-- The daily limit of readers' messages (#220, Roman's review of #221): the
-- network address is counted as SHA-256 of a random salt for the UTC day and
-- the address (an IPv6 address by its /64 network). The salt is made on the
-- day's first message and deleted by the daily cleanup once the day is over,
-- with that day's address hashes, so a hash cannot be turned back into the
-- address by trying every address with the day.
CREATE TABLE support_salts (
  day  TEXT PRIMARY KEY,   -- the UTC day, YYYY-MM-DD
  salt TEXT NOT NULL       -- 32 random bytes (hex), never sent anywhere
);

-- The hashes written before this migration were made without a salt: clear
-- them (today's count starts again, under the new hash).
UPDATE support_messages SET ip_day_hash = NULL WHERE ip_day_hash IS NOT NULL;
