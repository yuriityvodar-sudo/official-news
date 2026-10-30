// How popular an item is in a country (#230 step 4), 0 to 2 in For you's
// score (step 5): what its readers look up on Wikipedia (up to 1.5) and what
// its own media publish (up to 1), together at most 2.

/** The most a country's popularity adds to an item's score. */
export const POPULARITY_MAX = 2;

/** Fewer views than this in the usual day count as this many: a jump from 1 to 30 is noise. */
const USUAL_FLOOR = 5;

/**
 * Wikipedia's part: the most views in a day since the item was published
 * against the usual day before. Lagarde's resignation on 29 Oct 2026: 545
 * views on cs.wikipedia against a usual 6, so 1.
 */
export function viewsScore(views: number, usual: number): number {
  const jump = views / Math.max(usual, USUAL_FLOOR);
  if (views >= 1000 && jump >= 30) return 1.5;
  if (views >= 300 && jump >= 10) return 1;
  if (views >= 100 && jump >= 3) return 0.5;
  return 0;
}

/** The media's part: how many of GDELT's articles about the item come from the country's own outlets. */
export function mediaScore(count: number): number {
  if (count >= 10) return 1;
  if (count >= 3) return 0.5;
  return 0;
}
