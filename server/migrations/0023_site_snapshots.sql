-- The website's snapshot of the feed (#88): one row per site language (en, uk,
-- ru, es, de) with everything its list pages show, as JSON (server/src/api/
-- snapshot.ts). The api Worker's cron gives each language a run every 5
-- minutes, which rebuilds its row when the feed changed (`version`: the newest
-- release and the language's newest translation) or the row is 20 minutes
-- old; the site Worker reads one row per list page, whatever the filter, the
-- page or the traffic. On 30 Oct, the site's first day live, crawlers opened about
-- 4,800 list pages in two hours, each running the API's queries (about 960
-- rows a page), and the free plan's 5 million rows a day ran out.
CREATE TABLE site_snapshots (
  lang TEXT PRIMARY KEY,
  json TEXT NOT NULL,
  version TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
