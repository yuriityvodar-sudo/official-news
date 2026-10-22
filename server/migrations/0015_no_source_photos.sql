-- #119: no pictures from gov.pl (photos CC BY-NC-ND 4.0) or the Élysée (photos
-- outside its open licence). docs/sources.csv sets pageImage false for both
-- sources, so new articles come without one; this clears the stored ones.
UPDATE articles SET image_url = NULL
WHERE source_id IN ('pl-council-of-ministers', 'fr-council-of-ministers');
