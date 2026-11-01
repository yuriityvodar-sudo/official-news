-- #230: the author of a story under an open licence (Global Voices, CC BY:
-- its republishing guidelines ask for the author's name and a link to the
-- original at the top), from the feed's dc:creator; NULL for every other source.
ALTER TABLE articles ADD COLUMN author TEXT;
