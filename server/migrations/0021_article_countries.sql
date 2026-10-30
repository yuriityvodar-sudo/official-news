-- #230, step 2: the countries each article concerns, from the summarizer's
-- `countries` (docs/contract.md, Database), so For you asks by them and not by
-- the source's country: a US tariff on Canadian cars reaches readers in Canada.
CREATE TABLE article_countries (
  article_id TEXT NOT NULL REFERENCES articles (id) ON DELETE CASCADE,
  country    TEXT NOT NULL,   -- ISO 3166-1 alpha-2, or EU for the Union
  PRIMARY KEY (article_id, country)
);

CREATE INDEX article_countries_country ON article_countries (country, article_id);

-- How far it reaches: national, regional or global (the summarizer's `reach`); NULL before #230.
ALTER TABLE articles ADD COLUMN reach TEXT CHECK (reach IN ('national', 'regional', 'global'));

-- The articles summarized before: their source's country, as For you read them until now.
INSERT OR IGNORE INTO article_countries (article_id, country)
  SELECT a.id, s.country FROM articles a JOIN sources s ON s.id = a.source_id WHERE a.summarized_at IS NOT NULL;
