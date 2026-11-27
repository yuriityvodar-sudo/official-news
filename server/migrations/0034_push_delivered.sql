-- How many phones received a notification, per day, language and platform
-- (Yurii, 27 Nov 2026). A phone says only "one arrived" (POST
-- /v1/push/delivered, server/src/push/delivered.ts): no id, no token, no
-- article, so the count cannot be tied to anyone. One row a day per
-- language and platform; each notification received adds 1.
CREATE TABLE push_delivered (
  day       TEXT NOT NULL,              -- UTC date, 'YYYY-MM-DD'
  lang      TEXT NOT NULL,              -- the notification's language: 'en' or one of LANGS
  platform  TEXT NOT NULL,              -- 'ios' or 'android'
  received  INTEGER NOT NULL DEFAULT 0, -- notifications received that day
  PRIMARY KEY (day, lang, platform)
);
