# Website: search engines index only the best article pages

**Decision (26 Nov 2026, Yurii: "ok do it", #350).** An article page is indexable, and in the sitemap, only when it is an official decision (not an event from Wikipedia or the media) of importance 3 and up, and only in English and in the source's own language. Every other article page stays on the site with `noindex`, out of the sitemap, with no hreflang alternates. One rule, `mayIndex` in `server/src/api/indexing.ts`, for the page, its alternates and both sitemaps. It replaces "every article is indexed" (Yurii, 29 Oct).

**Why.** Measured on 26 Nov 2026:
- Search Console: the sitemap index was last read on 7 Nov and its three files on 11–12 Nov; crawl requests fell from about 1,300 on 3 Nov and 500–600 a day to almost none from 10 Nov; 1,650 pages indexed, 4,170 "Discovered – currently not indexed"; articles of 12 and 20 Nov were "unknown to Google". No manual action, no security issue, host healthy.
- Cloudflare's logs, 18–26 Nov: Googlebot made 6–29 requests a day, about half for robots.txt, none for a sitemap.
- Google's status page: the November 2026 core update began on 10 Nov.
- The site listed about 9,300 article pages for 2,394 items (most in 4 languages); 514 of the items were events. Of the 1,885 official items, 834 have importance 3 or more.
- Before the drop, official decisions (UK, South Korea, EU, Argentina, Mexico) drew most impressions.

Google's guidance treats many machine-written and machine-translated pages with little of their own as low value; fewer, stronger pages is the first step of the plan in #350.

**Not decided here.** An automatic second check of each summary against the official text (a second AI call per article, so a change to a fixed principle; to agree with Roman), country pages in the sitemap, Bing and IndexNow: later steps of #350.

**Status.** Built in this pull request. To judge it: Search Console's crawl requests and "last read" of the sitemap files, weekly.
