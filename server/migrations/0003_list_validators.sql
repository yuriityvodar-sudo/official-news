-- Item 6: what a source's server sent with its last list (ETag, Last-Modified),
-- sent back as If-None-Match / If-Modified-Since so an unchanged list answers
-- 304 instead of being downloaded again. Only for sources with conditionalGet.
ALTER TABLE sources ADD COLUMN list_etag TEXT;
ALTER TABLE sources ADD COLUMN list_last_modified TEXT;
