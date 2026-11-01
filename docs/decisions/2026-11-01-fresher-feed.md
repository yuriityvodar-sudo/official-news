# A day of age costs 2 points, not half a point (#230)

- **Decision:** For you's score, the top stories' (#164, every feed) and the website's take 2 points off for each day since publication (`AGE_PER_DAY` in `server/src/api/foryou.ts`), in place of half a point. A fresh 3 now beats a 4 from yesterday, and a day-old 5 ties a fresh 3. Replaces the half point of #164 (26 Oct) and of #230 step 5 (30 Oct).
- **Why:** Roman, 1 Nov: «в ленте должны быть более новые новости, а не трехдневней давности». With half a point, a 5 from three days ago (3.5) beat a fresh 3, and For you's first ten for Czechia were 67 hours old at the middle on 1 Nov (live API, 08:30 UTC). Ranked again with 2 points a day the same list's first ten are 33 hours old at the middle. The rest of the gap is supply: the sources gave 16 articles in the last 24 hours (a Sunday), not the ranking.
- **Status:** Proposed (Roman's Claude, on Roman's word of 1 Nov)
