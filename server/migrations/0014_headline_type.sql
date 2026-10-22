-- The kind of hook headline the summary has (#133): question, consequence,
-- contrast or plain. NULL for articles summarized before #133. The app's
-- analytics compare how often each kind is opened.
ALTER TABLE articles ADD COLUMN headline_type TEXT;
