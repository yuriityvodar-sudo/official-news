-- Release together (#46, Yurii 15 Oct): the feed is the same in every
-- language. A summarized decision gets its feed_seq only when every enabled,
-- not paused language has published its translation (or failed it 3 times);
-- the translator's run releases it (server/src/translator/release.ts), no
-- longer the summarizer. Every language feed is ordered by feed_seq;
-- article_translations.lang_seq is kept (the all-or-nothing CHECK reads it) but
-- no longer orders anything.

-- Why a language is paused: 'manual' (queue.mjs) or 'auto: provider down since <time>'.
-- An automatic pause ends by itself on the provider's first answer; a manual one does not.
ALTER TABLE translation_langs ADD COLUMN paused_reason TEXT;
-- Since when the language's providers have not answered (outage, quota, no key);
-- NULL once one answers. After 2 hours the language is paused automatically.
ALTER TABLE translation_langs ADD COLUMN down_since TEXT;
UPDATE translation_langs SET paused_reason = 'manual' WHERE paused = 1;

-- German stays configured but off for now (Yurii, 15 Oct): Z.ai blocks requests
-- from Cloudflare Workers. `npm run queue -- enable de` turns it on with its backlog.
UPDATE translation_langs SET enabled = 0, updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE lang = 'de';

-- The language feeds walk articles_feed_seq like the English one, so the index
-- that bounded a lang_seq walk is no longer used.
DROP INDEX article_translations_lang_time;

-- Articles waiting for release, oldest English first: the release step and
-- the claim read them here (a handful, normally). Replaces 0006's index of
-- visible rows without a number, which the summarizer no longer heals.
DROP INDEX articles_unnumbered;
CREATE INDEX articles_unreleased ON articles (summarized_at, id) WHERE is_news = 1 AND feed_seq IS NULL;
