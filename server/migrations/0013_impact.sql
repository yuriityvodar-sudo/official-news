-- #63: what a decision means in practice, written by the summarizer with the
-- summary: JSON {"general", "byTopic": [{"topic", "text"}], "residents",
-- "abroad"} (docs/contract.md), NULL when the article is not news, nothing
-- follows directly from it, or it was summarized before #63.
ALTER TABLE articles ADD COLUMN impact TEXT;
