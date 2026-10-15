# How news aggregators, RSS readers and link sites order "latest" lists and treat late-discovered items

Research date: 2026-10-15. Most sources are vendor docs, project PRs and forum posts by the developers. Where a fact came only from a search-engine summary and not from a page I fetched, it is marked "(search summary, not fetched)".

## 1. Which date do RSS readers sort by: published date or received/crawled date? (Feedly, Inoreader, NewsBlur, Miniflux, FreshRSS, The Old Reader)

### Takeaway
The large synced readers (FreshRSS by default, Feedly, Inoreader) order "latest" by when the service received the item, not by the date the publisher claims. The publisher date is treated as display-only. FreshRSS documents why. Received order is unique and only ever increases, so new items always land on top and nothing appears in the middle of an already-read list. Publication-date sorting is offered only as an option, and FreshRSS lists what it breaks: mark-all-read safety, Today/Yesterday headers, and API sync.

### Cited Findings
**FreshRSS (the clearest primary source)**
- FreshRSS PR #7149 "Implement custom order-by", by Alkarex, merged into `edge` on 2025-01-06, added sort options. They are received date (`sort=id`, the existing default), publication date (`sort=date`), title, link and random. Each can be sorted ascending or descending. — [FreshRSS PR #7149](https://github.com/FreshRSS/FreshRSS/pull/7149)
- The PR's rationale: received date is the best sort because "new entries always have a higher received date". Publication date is not unique and not monotonic, because "multiple articles may share the same publication date" and "we may receive articles with a publication date far in the future". Per the mirrored commit notes, it can also be followed "later [by] some new articles with a publication date far in the past". — [FreshRSS PR #7149](https://github.com/FreshRSS/FreshRSS/pull/7149); [mirror of commit notes](https://git.rdnlsmith.com/fresh-rss-custom/atom/app/Models/EntryDAO.php?h=1.26.1)
- The URL parameter is documented as `&sort=date` (publication date), "which is not indicative of how new an article is". This is from a search summary of a mirror of FreshRSS source, not fetched. — [mirror](https://git.rdnlsmith.com/fresh-rss-custom/atom/config-user.default.php?h=1.26.2)
- Features that only work with received-date sort:
  - "the menus to mark-as-read before 1 day and before 1 week are disabled when sorting by anything else"
  - the "Today", "Yesterday" and "Before yesterday" headers appear only with received-date sort
  - "Sorting by anything else than received date breaks the guarantees needed for a successful synchronisation via API."

  — [FreshRSS PR #7149](https://github.com/FreshRSS/FreshRSS/pull/7149)
- In the current default user config, `'sort' => 'id'` (received) and `'sort_order' => 'DESC'`, with a secondary sort that also defaults to `id`. Allowed criteria are `'id'|'c.name'|'date'|'f.name'|'length'|'link'|'rand'|'title'`. — [FreshRSS config-user.default.php (edge)](https://raw.githubusercontent.com/FreshRSS/FreshRSS/edge/config-user.default.php)

**Feedly**
- Feedly's help page says the date it shows is not the publication date: "the date that we give the articles is not the date at which they have been published", it is "the date at which we added them to our system". Dates can be "slightly off by a few minutes or even sometimes by a few hours". — [Feedly help: My article is showing the wrong date](https://docs.feedly.com/article/323-my-article-is-showing-the-wrong-date)
- Feedly API: "Articles are always returned in reverse-chronological order (newest first) by default". Results are paged with an "opaque continuation object", and each later page holds older articles. The page does not say whether the order uses `crawled` or `published`. — [Feedly developers: Understanding Continuation](https://developers.feedly.com/docs/understanding-continuation)
- `GET /v3/streams/contents` takes `count` (1–100, default 20), `newerThan` (Unix epoch in milliseconds, at most 31 days back) and `continuation`. — [Feedly developers: Building your first TI integration](https://developers.feedly.com/reference/building-your-first-ti-integration)
- The Teams API docs list `count`, `unreadOnly`, `ranked` and `newerThan` as stream contents parameters, without defining `ranked`. — (search summary, not fetched) [Feedly Teams API](https://feedly.com/new-features/posts/introducing-the-feedly-teams-api)
- Feedly entries carry separate `crawled`, `published` and `recrawled` millisecond timestamps. This is confirmed only by a third-party client that parses them. — [seymour R client, feedly-entry.R](https://git.rud.is/hrbrmstr/seymour/src/commit/83a41922c94d019e91c0f39e325ca7796c02538d/R/feedly-entry.R)
- The old official page developer.feedly.com/v3/streams/ now 301-redirects to developers.feedly.com/v3/streams/, which returns 404. I could not read Feedly's original field definitions. — fetched 2026-10-15

**Inoreader**
- Inoreader API stream contents, item fields:
  - `published` is the publisher's date and "may only be used for display purposes"
  - `crawlTimeMsec` and `timestampUsec` record the same moment, when Inoreader received the item. The docs say "Use `timestampUsec` whenever possible".
  - `updated` is set only if the article changed after it was fetched

  — [Inoreader API: Stream contents](https://www.inoreader.com/developers/stream-contents)
- Inoreader API paging and filters:
  - `n` is "Number of items to return (default `20`, max `100`)"
  - `r=o` gives oldest first, with a lookback of about one month
  - `ot` is a start time in seconds or in microseconds "matching `timestampUsec`" ("Only articles newer than this timestamp will be returned")
  - `c` is a continuation token ("If the `continuation` string is missing, then you are at the end of the stream")
  - `xt=user/-/state/com.google/read` excludes read items

  — [Inoreader API: Stream contents](https://www.inoreader.com/developers/stream-contents)
- Inoreader help: sort order is set per feed, folder or tag. The default "newest first" means "the last article received will be shown first". — (search summary, not fetched) [Inoreader blog, 2020](https://inoreader.com/blog/2020/10/organize-and-customize-feeds.html)
- A 2014 Inoreader post says articles "were sorted by their received date (very close to the published date)". Favorites are now sorted by starred date. — (search summary, not fetched) [Inoreader blog, 2014-09](https://www.inoreader.com/blog/2014/09/group-articles-by-feed-and-more-updates.html)

**Miniflux**
- Miniflux API `GET /v1/entries`:
  - `order` is one of `"id"`, `"status"`, `"published_at"`, `"category_title"` or `"category_id"`; `direction` is `asc` or `desc`
  - cursor filters `before_entry_id` and `after_entry_id` (since 2.0.9)
  - time filters `before` and `after` (since 2.0.9), and `published_before`, `published_after`, `changed_before` and `changed_after` (since 2.0.49)

  — [Miniflux API reference](https://miniflux.app/docs/api.html)
- Each entry has both `published_at` (example "2016-12-12T16:15:19Z") and `created_at` (example "2016-12-27T16:15:19Z", the time Miniflux stored it). There is also `changed_at`. — [Miniflux API reference](https://miniflux.app/docs/api.html)
- A Miniflux commit says the published date is not updated on refresh "because some feeds do not contain any date, in this case it default[s] to time.Now()". So date-less items are stamped with the time they were discovered. — (search summary of a commit mirror, not fetched) [git.causa-arcana.com mirror](https://git.causa-arcana.com/forks/miniflux/src/commit/b0442e027771c2cf33b92557a7e73fa4f85849cf)
- The history page sorts by `changed_at`. When many entries share it (bulk mark-read), it falls back to `published_at`. — (search summary, not fetched) [commit mirror](https://git.causa-arcana.com/forks/miniflux/commits/commit/168a870c025bfef6efdeb46e166e79a16093c157/model/entry.go)
- User sort options for "Oldest" and "Newest" in third-party customisations sort by published date. — [Abhinav Sarkar, Customizing Miniflux (2025)](https://notes.abhinavsarkar.net/2025/customizing-miniflux)

**NewsBlur**
- NewsBlur respects the publisher's story date ("they are publishing a story in the future and NewsBlur is respecting that"). It also used the latest story's date as the feed's "last read date". The developer said that rule exists "to get around issues like marking a feed as read but it hasn't been fetched in an hour". — [NewsBlur forum, samuelclay, 2012-05-14](https://forum.newsblur.com/t/posts-from-the-future/600)
- For a JSON feed with no published date, NewsBlur used the fetch time as the item time. That labelled a two-week-old article as published today and broke the sort of "All Site Stories". — (search summary, not fetched) [NewsBlur forum: NewsBlur gets article dates wrong](https://forum.newsblur.com/t/newsblur-gets-article-dates-wrong/11508)

### Inferences
- The industry default for a "latest" feed is received order, with the publisher's date shown as a label. FreshRSS and Inoreader say this explicitly, and Feedly says it about its displayed dates. NewsBlur is the main exception: it sorts by the story date and has had recurring future-date and fetch-time problems as a result.
- Received order makes "new items only appear at the top" true by construction. Publication-date order cannot promise that whenever discovery lags publication. In our app that lag is minutes to hours (fetcher plus AI).
- Miniflux shows the common split: one database stores both `published_at` and `created_at`, and offers sorting by `id` (insertion order) or `published_at`.

### Gaps
- The Old Reader: I found no documentation on its sort key. It exposes a Google-Reader-style API, so it likely uses crawl time, but that is not confirmed.
- Feedly's official definitions of `crawled`, `published`, `recrawled` and `ranked`, and the exact sort key of `/streams/contents`: the official pages 404, and web.archive.org was not reachable from my tools.
- I could not read Miniflux's default UI sort setting and its option names from primary docs.

## 2. How do readers handle items with old (backdated) or future dates?

### Takeaway
No reader has a clean general solution. The documented patterns are:
- clamp future dates to "now" beyond a tolerance (NewsBlur)
- stamp date-less items with the fetch time (Miniflux, NewsBlur)
- sort by received time so odd dates cannot reorder the list (FreshRSS)

Re-dated old posts show up as "new" in received-order readers. A received-order reader also shows a newly discovered old item at the top unless the publisher's date is honoured.

### Cited Findings
- Future dates are a named reason FreshRSS keeps received-date sort as the default. With date sort, "articles with a publication date far in the future" sit at the top, and items with past dates can arrive later and land deep in the list. — [FreshRSS PR #7149](https://github.com/FreshRSS/FreshRSS/pull/7149)
- NewsBlur's developer, 2017-08-03: "There is really no way around it other than to have me institute a policy of future-dates-become-current-dates." He describes converting far-future dates to the current time and letting dates "less than 24 hours into the future" stand ("I let the publisher use the date they give"). The dashboard river "only shows stories that are less than an hour into the future". He was "thinking about changing this". The page summary also mentions a one-hour threshold for conversion, which conflicts with the 24-hour statement; treat the exact thresholds as uncertain. — [NewsBlur forum, 2017](https://forum.newsblur.com/t/override-or-delay-future-dating-of-publisher-content-channeled-through-newsblur/6605)
- NewsBlur, 2012: a Washington Post feed item was dated about 7 months in the future. The developer deleted it by hand and floated "Maybe I should cap it at a day or so into the future". Future dates also pushed the feed's "last read date" forward, which hid real new stories. — [NewsBlur forum, 2012](https://forum.newsblur.com/t/posts-from-the-future/600)
- Feedly: if a publisher gives an old article a new timestamp, "we show it as new despite the article being years old". The page notes "It is a common practice to refresh old content to make it look like new." — [Feedly help](https://docs.feedly.com/article/323-my-article-is-showing-the-wrong-date)
- Real case, April 2024: an R-devel maintainer reported Feedly greeting him with "569 new posts" because the R NEWS feed's timestamps had been reset, so every old post looked fresh. — (search summary, not fetched) [R-devel mailing list, 2024-04](https://stat.ethz.ch/pipermail/r-devel/2024-April/083310.html)
- Miniflux: when a feed item has no date, the parser falls back to `time.Now()`. Miniflux deliberately does not overwrite `published_at` on later refreshes, so the item does not keep jumping. — (search summary of commit, not fetched) [commit mirror](https://git.causa-arcana.com/forks/miniflux/src/commit/b0442e027771c2cf33b92557a7e73fa4f85849cf)
- FreshRSS has a user option `mark_updated_article_unread` (default `false`) for articles whose content changed after they were received. A TODO in the code considers "-1 => ignore, 0 => update, 1 => update and mark as unread". — [FreshRSS config-user.default.php](https://raw.githubusercontent.com/FreshRSS/FreshRSS/edge/config-user.default.php)
- Inoreader keeps an `updated` field only for articles changed after fetch, separate from `published` and the crawl timestamp. — [Inoreader API](https://www.inoreader.com/developers/stream-contents)
- Apple News added a `datePublished` metadata property in 2016 so publishers can add older stories to a channel without them appearing as new or at the top of the channel. — (secondary coverage, search summary, not fetched) [AppleInsider forum/article](https://forums.appleinsider.com/discussion/193118); [AppleMagazine](https://applemagazine.com/apple-news-format-gets-bundle-of-new-features-for-publishers/)

### Inferences
- A practical policy pieced together from these products:
  1. Store both the publisher date and the received time.
  2. Clamp publisher dates in the future to the received time, with a small tolerance (NewsBlur used about a day, or about an hour in its main river).
  3. For a date-only source, put the time at the received time when it is the same day. Otherwise use start or end of day, and display only the date.
  4. Do not rewrite the stored date on refresh (Miniflux).
- For items discovered long after publication (a backfill, or a source caught up after downtime), received-order readers show them at the top as new. Apple's `datePublished` shows the opposite choice: treat them as old and keep them out of "new". The products differ, so pick a threshold, for example "published more than N days before discovery means not new".

### Gaps
- I found no reader that documents a numeric rule for backdated items, such as "items published more than X days ago are not marked unread". The closest is Feedly auto-marking articles older than 30 days as read (see section 5), but it is not stated whether that uses received or published age.
- I could not read Apple's own reference text for `datePublished` (the URL tried returned 404). The ordering claim rests on 2016 secondary coverage.

## 3. Reddit "new" and Hacker News "newest": sort key and paging when items are added or removed

### Takeaway
Both link sites sort "new" by submission time and page with cursors anchored to an item ID, not page numbers. Reddit says this is because content changes too often for page numbers. HN's web "More" link carries `next=<item id>`. Cursor paging means items submitted after you loaded the first page never shift what the next page returns.

### Cited Findings
**Reddit**
- "Listings do not use page numbers because their content changes so frequently. Instead, they allow you to view slices of the underlying data." Listings share the parameters `after`/`before`, `limit`, `count` and `show`. — Reddit API docs, via search summary (reddit.com blocks my fetch tool) [Reddit API docs mirror](https://web-archive.nli.org.il/National_Library/mp_/https://www.reddit.com/dev/api); [redditclient reference](https://redditclient.readthedocs.io/en/latest/reference/)
- `after`/`before` are "the fullname of an item in the listing to use as the anchor point of the slice", and "only one should be specified". `count` is "the number of items already fetched". You page by passing the returned `after` value until it comes back null. — same sources (search summary)
- "'before' and 'after' mean before and after in the listing, not necessarily in time." — [redditclient reference](https://redditclient.readthedocs.io/en/latest/reference/) (search summary)
- Third-party, unofficial:
  - `limit` caps at 100
  - passing a bare ID instead of a fullname silently returns page one
  - forward paging runs out at about 1,000 items per listing (949 measured for r/python "new")

  — [redditapis.com tutorial, 2026](https://www.redditapis.com/blogs/reddit-api-pagination-2026); [Glama deep-dive](https://glama.ai/mcp/servers/@padak/apify-actor-reddit-mcp/blob/72ada09efe1e7e2075bcf66b26878ec302784793/docs/reddit-api-deep-dive.md)

**Hacker News**
- The official HN API exposes `/v0/newstories` ("Up to 500 top and new stories") and `/v0/maxitem` ("The current largest item id"). Clients can walk backward from `maxitem`. `/v0/updates` lists recently changed items and profiles. — [HackerNews/API on GitHub](https://github.com/HackerNews/API)
- The API documents no paging parameters. Each item's `time` is "Creation date of the item, in Unix Time". Removed items stay in place with `dead: true` or `deleted: true`. — [HackerNews/API](https://github.com/HackerNews/API)
- The HN web "newest" page (observed 2026-10-15) lists items in strictly descending ID order (50100994, 50100993, 50100987…) with relative ages ("2 minutes ago"). Its "More" link is `newest?next=50100584&n=31`, a cursor on the item ID plus a rank offset for numbering. — [news.ycombinator.com/newest](https://news.ycombinator.com/newest)

**Mastodon (comparable timeline API, for paging semantics)**
- Mastodon's timeline paging parameters:
  - `max_id`: "All results returned will be lesser than this ID"
  - `since_id`: "All results returned will be greater than this ID"
  - `min_id`: "Returns results immediately greater than this ID. In effect, sets a cursor at this ID and paginates forward"

  Next and previous URLs are sent in a `Link` header. "Clients generally do not need to sort IDs; the server is responsible for sorting IDs before generating the API response". IDs should be treated as opaque strings. — [Mastodon API guidelines](https://docs.joinmastodon.org/api/guidelines/)

### Inferences
- On HN, item IDs are assigned at submission, so ID order and creation-time order coincide. "Newest" is effectively insertion order, the same monotonic-key idea as FreshRSS's `id` sort.
- Removals do not break cursor paging. The cursor is an ID, so a deleted item just disappears from a slice and no other item shifts across a page boundary. That is the property offset paging lacks.
- I did not confirm from primary docs that Reddit's "new" sorts by `created_utc`. It is the widely assumed key, but the docs I could reach describe only the listing mechanics.

### Gaps
- Reddit's sort key for `/new` and how its cursors behave when the anchor item is removed: reddit.com/dev/api could not be fetched, and the docs do not cover the removed-anchor case.
- How HN's `next=` behaves if the anchor item is killed. Not documented.

## 4. Google News and Apple News: how freshness is decided and how publishers are told to give dates

### Takeaway
Google treats dates as an estimate built from several signals, the visible date and `datePublished`/`dateModified` among them, and tells publishers to give accurate dates, a time zone where a time is given, and no future dates. News sitemaps must use the original first-publication time, not the time the URL was added. Apple News uses `datePublished` metadata so back-catalogue stories do not surface as new. Neither company documents its exact ordering algorithm for "latest" or "top".

### Cited Findings
- Google: "A *byline date* is the date that Google estimates that the web page was updated or published." Google uses multiple factors because each one alone can be unreliable, and does not guarantee showing a byline date. — [Google Search Central: Influencing your byline dates (last updated 2025-12-10)](https://developers.google.com/search/docs/appearance/publication-dates)
- Google's guidance to publishers:
  - show a clearly labelled visible date ("Published" or "Last updated")
  - add `datePublished` and/or `dateModified` to `Article`, `BlogPosting` or another `CreativeWork` type
  - "The date is required; the time is not", but a time with the correct time zone (accounting for DST) adds precision
  - do not use future dates, or the date of an event described on the page
  - keep the visible and structured dates consistent, and remove other dates if the wrong one gets picked

  — [Google Search Central: publication dates](https://developers.google.com/search/docs/appearance/publication-dates)
- Google News sitemaps: `<news:publication_date>` must be "the original date and time when the article was first published on your site". "Don't specify the time when you added the article to your sitemap". Date-only W3C format is accepted. "Only include recent URLs for articles that were created in the last two days". Up to 1,000 `news:news` tags per sitemap. — [Google Search Central: News sitemap (last updated 2025-12-10)](https://developers.google.com/search/docs/crawling-indexing/sitemaps/news-sitemap)
- The old Google News Publisher Center article on dates (support.google.com/news/publisher-center/answer/9606710) now redirects to the News sitemap page. — fetched 2026-10-15
- Apple News Format `Metadata` holds author, creation date, publication date, keywords and excerpt. Apple's sample includes `datePublished`, `dateCreated` and `dateModified` as ISO 8601. — (search summary of Apple docs, not fetched) [Apple News Format: Metadata](https://developer.apple.com/documentation/applenewsformat/metadata.md)
- Apple's 2016 update added `datePublished` so publishers could add older stories without them showing up as new. — (secondary coverage, search summary, not fetched) [AppleInsider](https://forums.appleinsider.com/discussion/193118); [AppleMagazine](https://applemagazine.com/apple-news-format-gets-bundle-of-new-features-for-publishers/)

### Inferences
- Google and Apple both make the publisher date the authority for "how old is this" and check it against what they observe. Google bounds sitemap freshness to two days and rejects future dates. That fits an app that sorts by discovery but uses the source's date to decide whether a late item counts as "new".
- Google explicitly accepts date-only values, so "date only, no time" is a normal case and not an error. Showing only the date for such items matches what publishers are told to provide.

### Gaps
- No public Google or Apple documentation on the ordering formula for "Latest", "Top stories" or "Full coverage". These are ranked, and the blend of freshness signals is not published.
- Apple News Publisher docs on how `dateModified` or article updates affect placement: not found.

## 5. Unread / "new since last visit" tracking, unread counts, and keeping lists from jumping

### Takeaway
The products separate "where the user's read state ends" from the display date, and they cap bulk "mark as read" at a high-water mark of what the user actually saw: FreshRSS `idMax`, NewsBlur's "last read date", Mastodon markers. That high-water mark must use a key that only grows, the received ID or time. If it uses the publisher's date, late or future-dated items get wrongly hidden or wrongly marked read. Unread counts are bounded in time (Feedly: 30 days) to keep them cheap.

### Cited Findings
- FreshRSS: articles can arrive in the background after what is on screen and before the user taps "mark all as read". With non-monotonic sorts, "users risk marking as read a batch of articles containing some fresh articles without seeing them". "A parameter idMax tracks the maximum ID related to a batch of actions such as mark all as read", which excludes items received after those displayed. — [FreshRSS PR #7149](https://github.com/FreshRSS/FreshRSS/pull/7149); [commit-notes mirror](https://git.rdnlsmith.com/fresh-rss-custom/atom/app/Models/EntryDAO.php?h=1.26.1)
- FreshRSS default read-marking triggers: `'mark_when' => ['article' => true, 'site' => true, 'scroll' => false, …]` and `'onread_jump_next' => true`. — [FreshRSS config-user.default.php](https://raw.githubusercontent.com/FreshRSS/FreshRSS/edge/config-user.default.php)
- NewsBlur stored a per-feed "last read date" equal to the latest story's date. A story dated in the future moved that mark forward and hid genuinely new stories until real time caught up. This is the failure that comes from tracking read state by publisher date. — [NewsBlur forum, 2012](https://forum.newsblur.com/t/posts-from-the-future/600)
- Feedly auto-marks articles older than 30 days as read: "we need a reasonable limit to be able to compute unread counts in sub-seconds". "All the articles stay in Feedly indefinitely, they are just being marked as read." The page does not say whether age is measured from crawl or publication. — [Feedly help: Do you mark articles older than 30 days as read? (page updated 2024-08-27)](https://docs.feedly.com/article/372-do-you-mark-articles-older-than-30-days-as-read)
- Feedly's incremental polling pattern:
  1. Page with `continuation` until no token comes back.
  2. Save the `updated` value ("the publish time of the newest entry in this response") from the cycle's first response.
  3. Pass it as the next cycle's lower bound.

  — [Feedly: Understanding Continuation](https://developers.feedly.com/docs/understanding-continuation)
- Inoreader lets a client fetch "only new since X" with `ot` (microsecond precision, matching `timestampUsec`, the crawl time) and exclude read items with `xt=user/-/state/com.google/read`. — [Inoreader API](https://www.inoreader.com/developers/stream-contents)
- Miniflux supports `after_entry_id` and `before_entry_id` cursors alongside time filters, so a client can ask for "entries newer than the last one I saw" by ID. — [Miniflux API](https://miniflux.app/docs/api.html)
- Mastodon's Marker entity stores a per-timeline last-read position with a version counter to prevent write conflicts. Aaron Parecki's Microsub server Aperture says it was "mostly inspired by the Feedly Markers API". — (search summary, not fetched) [Mastodon Marker entity](https://docs.joinmastodon.org/entities/Marker); [Aaron Parecki, Aperture (2018)](https://aaronparecki.com/2018/02/12/9/aperture)
- The FreshRSS Today / Yesterday / Before yesterday headers are shown only in received-date order. Grouping by day is tied to the same monotonic key. — [FreshRSS PR #7149](https://github.com/FreshRSS/FreshRSS/pull/7149)

### Inferences
Translated to our app (official decisions; fetcher plus AI add minutes to hours of lag; some sources give only a date):
- **Sort key.** Order "latest" by a monotonic server key assigned when an article becomes visible, which for us means after AI processing. FreshRSS `id`, Inoreader `timestampUsec`, Feedly's crawl date and HN item IDs all work this way. Late items then appear on top, never in the middle of what the user already read. Show the source's published date, date-only where that is all there is, as a label, as Inoreader ("display purposes") and Feedly do.
- **Paging.** Use a cursor on that key: `before=<id>` for older pages and `after=<id>` or `since` for new items, as with Reddit `after`, HN `next=`, Mastodon `max_id`/`min_id` and Miniflux `after_entry_id`. Do not use offsets. Items arriving during a scroll then do not duplicate or skip rows.
- **"New since last visit" and "mark all read".** Store a high-water mark of the largest key the user saw (FreshRSS `idMax`, Mastodon marker). Do not store a publisher date (NewsBlur's failure). Bound any bulk read action by it.
- **Late but genuinely old items.** Decide a threshold (Apple's `datePublished` approach) so that, say, an item published more than N days before discovery is placed by its published date or not counted as unread. Otherwise a received-order list will present a backfill as fresh news.
- **Dates.** Clamp future-dated items to the discovery time, with a small tolerance (NewsBlur). Never rewrite a stored date on refresh (Miniflux).

### Gaps
- Feedly's Markers API (`markAsRead`, and what I recall as `asOf`/`lastReadEntryId` parameters) could not be verified. The official v3 pages 404 and the archive was unreachable. Unverified; do not cite.
- I found no product doc describing a "new items available" banner instead of auto-inserting at the top. That is a common UI pattern, but I found no primary source for it in these products.
- How Inoreader, The Old Reader and Feedly compute unread counts for items discovered late but dated long ago is not documented in what I found.
