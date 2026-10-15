# How social timelines order reverse-chronological feeds and handle late items (Twitter/X, Mastodon, Bluesky)

Research date: 2026-10-15. Code facts marked "main branch" were read directly from GitHub (`gh api .../contents/...`) on that date. Sources older than 2020 are flagged **[pre-2020]**.

## Twitter/X: how do since_id/max_id and Snowflake IDs make timeline paging consistent?

### Takeaway
X sorts and pages timelines by a server-assigned 64-bit Snowflake ID, which encodes a timestamp and is "roughly time-ordered". Clients poll for newer items with `since_id` and page older items with `max_id` (v1.1) or `until_id` / `pagination_token` (v2). Authors never supply the sort key: the server mints it when the post is created.

### Cited Findings
- X IDs are "64-bit unsigned integers generated using a system called 'Snowflake'". Each one encodes a timestamp, a worker number and a sequence number. — [X Docs: X IDs](https://docs.x.com/resources/fundamentals/x-ids) (undated, current docs)
- The same page says IDs are "roughly time-ordered: higher IDs generally represent newer objects", and that comparing them gives chronological order. In JavaScript you compare them as strings (this works lexicographically only for IDs of equal length) or as `BigInt`, because the numbers are too large for a JS double. — [X Docs: X IDs](https://docs.x.com/resources/fundamentals/x-ids)
- v2 timelines return up to 100 posts per request. To page, you read `next_token` from `meta`, send it back as `pagination_token`, and repeat until no `next_token` comes back. `since_id` means "Return Posts after this ID" and `until_id` means "Return Posts before this ID". — [X Docs: Timelines integration guide](https://docs.x.com/x-api/posts/timelines/integrate)
- In v1.1, `since_id` is exclusive and `max_id` is inclusive. v2 replaced `max_id` with `until_id`, which is exclusive. Both versions can "traverse through timelines using Post ID 'timestamps'" because of how the IDs are built. This comes from a search-result snippet of the migration guide; the page itself was not opened. — [X Developer: Standard v1.1 to v2 timelines migration](https://developer.x.com/en/docs/x-api/tweets/timelines/migrate/standard-to-twitter-api-v2)
- There are caps: the user Posts timeline reaches back only about 3,200 posts and the mentions timeline about 800. Requests past those limits return "a successful response with no data". — [X Docs: Timelines integration guide](https://docs.x.com/x-api/posts/timelines/integrate); the cap numbers come from the migration-guide search snippet above.

### Inferences
- An X ID's timestamp is the server clock at the moment the post was written, so creation time and ingestion time are the same thing. An author cannot backdate an X post, which removes the late-item problem by construction.
- Because v1.1 `max_id` is inclusive, the well-known client habit of sending `max_id = oldest_seen_id - 1` exists to avoid a duplicate at the page seam. No source fetched this session documents that habit. v2's exclusive `until_id` makes it unnecessary.
- ID-based paging stays stable for the same reason any keyset cursor does. Posts arriving at the top don't shift older pages, which is the failure that offset or page-number paging has.

### Gaps
- The classic v1.1 guide "Working with timelines" (developer.twitter.com) explained why IDs beat page numbers, with a diagram of new tweets arriving between requests. It could not be retrieved: developer.x.com returned HTTP 402, the old URL redirects to the docs.x.com home page, and web.archive.org is blocked for this tool. Its wording is therefore not quoted here.
- The 2010 Twitter engineering post "Announcing Snowflake" (blog.x.com) returned HTTP 403. It is widely cited as stating the requirement that IDs be "roughly sortable" (k-sorted), but this was not verified this session and would be **[pre-2020]** anyway.
- No primary source was found for how X's own app places its "See new posts" pill, or for how Twitter's internal timeline cache (fan-out into Redis lists of IDs, per the 2013 "Timelines at scale" talk) handles late items. Not verified.

## Mastodon: how is the home timeline built and ordered, what do min_id/max_id/since_id mean, and where do late federated posts and boosts land?

### Takeaway
Mastodon's home timeline is a Redis sorted set per user, scored by status ID. Status IDs are Snowflake-style and time-based. Since 2018, posts delivered live over federation get an ID based on *when the server processed them*, not on their claimed `published` time. Mastodon adopted this precisely because backdated IDs broke the API promise that new items always have a greater ID than the last one seen. Posts fetched later (not delivered live) keep a backdated ID and are only pushed into home feeds if they are less than 6 hours old. A boost is its own status with its own fresh ID, so it appears at the top.

### Cited Findings
- **Feed structure.** `FeedManager#add_to_feed` inserts with `redis.zadd(timeline_key, status.id, status.id)`, so the sort score *is* the status ID. The feed is trimmed with `zremrangebyrank(timeline_key, 0, -(MAX_ITEMS + 1))`, where `MAX_ITEMS = 800`. — [mastodon/mastodon main: app/lib/feed_manager.rb](https://github.com/mastodon/mastodon/blob/main/app/lib/feed_manager.rb)
- **Boost dedup.** A reblog is skipped if the original status already sits within the top `REBLOG_FALLOFF = 80` items of the feed: `return false if !rank.nil? && rank < FeedManager::REBLOG_FALLOFF`. Later reblogs of the same original are tracked in a per-original set, so only one copy shows. — [feed_manager.rb](https://github.com/mastodon/mastodon/blob/main/app/lib/feed_manager.rb)
- **Feed rebuild.** `populate_home` refills an empty feed with `MAX_ITEMS / 2` items. When the feed is full, it skips any account that "has not posted more recently than the last item on the feed". — [feed_manager.rb](https://github.com/mastodon/mastodon/blob/main/app/lib/feed_manager.rb)
- **ID generation rule.** `Mastodon::Snowflake::Callbacks.around_create` leaves the database default in place, which is a time-based ID at insert time (`timestamp_id(...)`), when any of these holds: `created_at.nil? || created_at >= now || created_at == updated_at || record.override_timestamps`. Otherwise it sets `record.id = Mastodon::Snowflake.id_at(record.created_at)`, a backdated ID. On a collision it retries with `id += rand(100)`. — [mastodon/mastodon main: lib/mastodon/snowflake.rb](https://github.com/mastodon/mastodon/blob/main/lib/mastodon/snowflake.rb)
  - Consequence: a remote post claiming a *future* `created_at` never gets a future ID. It gets a now-based ID, so it cannot pin itself to the top.
- **The flag's documented meaning.** "If `override_timestamps` is set at creation time, Snowflake ID creation will be based on current time instead of `created_at`". — [mastodon/mastodon main: app/models/status.rb](https://github.com/mastodon/mastodon/blob/main/app/models/status.rb)
- **Who sets the flag.** The inbox worker, which handles real-time federation deliveries, calls `ProcessActivityService.new.call(body, actor, override_timestamps: true, ..., delivery: true)`. — [main: app/workers/activitypub/processing_worker.rb](https://github.com/mastodon/mastodon/blob/main/app/workers/activitypub/processing_worker.rb)
  - Both `Create`, for posts, and `Announce`, for boosts, store the remote `published` as `created_at` and pass `override_timestamps` through. — [main: activity/create.rb](https://github.com/mastodon/mastodon/blob/main/app/lib/activitypub/activity/create.rb), [main: activity/announce.rb](https://github.com/mastodon/mastodon/blob/main/app/lib/activitypub/activity/announce.rb)
- **Late-arrival guard.** A status is distributed into home and list feeds only when `@options[:override_timestamps] || @status.within_realtime_window?`. That window is `created_at >= REAL_TIME_WINDOW.ago`, with `REAL_TIME_WINDOW = 6.hours`. Old posts fetched by other paths (search, backfill, collections) are stored with a backdated ID but are *not* pushed into followers' home feeds. — [create.rb](https://github.com/mastodon/mastodon/blob/main/app/lib/activitypub/activity/create.rb), [status.rb](https://github.com/mastodon/mastodon/blob/main/app/models/status.rb)
- **Why the rule exists.** PR #7336, "Fixes/do not override timestamps" (ClearlyClaire, merged 2018-05-03), says: "inserting items with older snowflakes IDs will break the assumption of consumers of the paging APIs that new items will always have a greater identifier than the last seen one". It introduced `override_timestamps` so that IDs for posts processed in real time are "based on the time the status is processed". **[pre-2020, but the mechanism is still in main as of 2026-10-15]** — [GitHub PR #7336](https://github.com/mastodon/mastodon/pull/7336); [commit mirror](https://git.asonix.dog/asonix/mastodon/commit/a24605961a1572f7e1800cc177b5b7defe45969c)
- **Earlier history.** PR #5260 (2017) first made backdated statuses get backdated Snowflake IDs, skipping "statuses that claim to be from the future". The commit noted that Snowflake IDs serve both to make identifiers harder to guess and to keep them in chronological order. This was seen only as a commit-log search snippet. **[pre-2020]** — [commit log mirror](https://git.asonix.dog/asonix/mastodon/commits/commit/f0f8b242c4ccd3603a60ba5decf7dc225000a017/app/services?page=3)
- **Pagination semantics.**
  - `max_id`: "All results returned will be lesser than this ID."
  - `since_id`: "All results returned will be greater than this ID."
  - `min_id`: "Returns results immediately greater than this ID", i.e. it pages forward (added in v2.6.0).
  - The docs' examples: `since_id=1` returns the *latest* statuses, while `min_id=1` returns the *oldest*.
  - Clients should follow `rel="next"` / `rel="prev"` in the `Link` header, because some endpoints paginate on IDs that are not exposed in responses.
  - IDs must be treated as opaque strings and never cast to integers. Vanilla IDs sort chronologically by length, then lexically.
  — [Mastodon docs: API guidelines, Pagination & IDs](https://docs.joinmastodon.org/api/guidelines/) (undated page)

### Inferences
- `since_id` and `min_id` differ in a way that matters for "load new posts". With more than `limit` new items, `since_id` returns the newest page and leaves a hole between it and what the client already holds. That is why Mastodon's web UI renders "load more" gap markers. `min_id` walks forward from the client's newest item without holes.
- Mastodon's protection against late items amounts to two things: (1) sort by an ID minted at *processing* time for anything that enters feeds live, and (2) refuse to fan out anything older than 6 hours that did not arrive live. A post's displayed `created_at` can therefore differ from its feed position, and Mastodon accepts that.
- A boost lands at the top because the boost row has its own new ID. Re-surfacing is modelled as a new feed item, not as moving the old one.

### Gaps
- No Mastodon documentation page explains the home-feed Redis structure or the 6-hour window. These come from source code only.
- Exact behaviour of third-party Mastodon clients (Ivory, Tusky and others) was not researched.

## Bluesky / AT Protocol: createdAt vs indexedAt, and is there a documented sortAt rule?

### Takeaway
Yes. Bluesky's AppView computes `sortAt = least(createdAt, indexedAt)`, the *earlier* of the author-supplied time and the time the AppView first saw the record. It sorts and pages every chronological feed by the keyset `(sortAt, cid)`. This stops future-dated posts from pinning themselves to the top, and backdated or imported posts sink to their claimed date. But it means a post indexed late, whose `createdAt` precedes items already shown, lands *mid-list*. Bluesky's own 2026 PR acknowledges that clients polling for "newer than X" will never see such items.

### Cited Findings
- **The two timestamps.**
  - `createdAt` is client-supplied and "generally assumed to be the original posting time". Clients may insert any value, which enables imports and migrations. It also allows abuse: "if you chose a far-future timestamp, that record will always sort at the top".
  - `indexedAt` is when an API server first sees a record. Using it alone clusters bulk imports at the import time.
  — [Bluesky docs: Timestamps (advanced guide)](https://docs.bsky.app/docs/advanced-guides/timestamps); [source markdown](https://github.com/bluesky-social/bsky-docs/blob/main/docs/advanced-guides/timestamps.md). The guide was drafted on 2024-01-29 and last updated 2024-04-25, per its git history.
- **The documented rule.** `sortAt` is the "earlier" of `createdAt` and `indexedAt`. Put simply: use `createdAt` unless it is in the future, in which case use `indexedAt`.
  - A stricter, nullable variant drops `createdAt` values earlier than the UNIX epoch, setting null or the epoch.
  - The guide recommends rejecting far-past and far-future timestamps, with a clock-skew window of about 2 minutes (`CLOCK_SKEW_WINDOW`, not part of the spec).
  - The Bluesky App View uses this logic for "author feeds, reply threads, and other chronologically-sorted feeds".
  — [Bluesky docs: Timestamps](https://github.com/bluesky-social/bsky-docs/blob/main/docs/advanced-guides/timestamps.md)
- **In code.** The AppView reference data-plane defines `sortAt` as a generated column: `.generatedAlwaysAs(sql\`least("createdAt", "indexedAt")\`)` on `post` and `repost`. The same applies to feed generators, lists, blocks, labelers, starter packs and quotes, with indexes on `(sortAt, cid)`. — [atproto main: migrations/20230309T045948368Z-init.ts](https://github.com/bluesky-social/atproto/blob/main/packages/bsky/src/data-plane/server/db/migrations/20230309T045948368Z-init.ts) (2023-03-09, still present; later migrations up to 2026-08-27 repeat the pattern)
- **The home timeline.** The `feed_item` table, one row per post or repost, carries `sortAt`. `getTimeline` paginates with `new TimeCidKeyset(ref('feed_item.sortAt'), ref('feed_item.cid'))` and merges followed-account items with self-items, sorted by `sortAt` descending with `cid` as tiebreak. — [atproto main: data-plane/server/routes/feeds.ts](https://github.com/bluesky-social/atproto/blob/main/packages/bsky/src/data-plane/server/routes/feeds.ts)
- **Cursors.** A cursor is an opaque packed string `<sortAt ms>__<cid>`, e.g. `'1641038400000__bafyx'`. It applies a row-value comparison `(sortAt, cid) < (cursor.sortAt, cursor.cid)` for descending order and fetches `limit + 1` rows to detect more pages. — [atproto main: data-plane/server/db/pagination.ts](https://github.com/bluesky-social/atproto/blob/main/packages/bsky/src/data-plane/server/db/pagination.ts)
- **The 2026 `since` parameter.** atproto PR #5493, "Add since and startCursor to getTimeline and getListFeed", was opened 2026-09-08 and merged 2026-09-29.
  - It adds an exclusive lower bound `since`, so the server returns items with `since < position < cursor`.
  - It adds a `startCursor` output that the client persists and sends back as `since` "to fetch only what is strictly newer". This supports "Following v2 position restoration" and "new content indicators".
  - When a bounded range is exhausted, the server echoes `since` back as the cursor rather than returning an empty one, because an empty cursor means "end of feed".
  — [GitHub: bluesky-social/atproto PR #5493](https://github.com/bluesky-social/atproto/pull/5493)
- **Bluesky's own caveat**, verbatim from PR #5493: "the bound is on sort position, not arrival time, so items that land later with a position below the boundary are not seen by a bounded read and clients should still do an occasional unbounded refresh". The PR also notes that production bounds on the timestamp alone, while the reference data-plane uses the full `(sortAt, cid)` keyset. — [PR #5493](https://github.com/bluesky-social/atproto/pull/5493)
- The PR references a parallel change in a separate production data-plane repo (`bluesky-social/tango#1540`, "atlantis"). The atproto repo's data-plane is a reference implementation, so production code may differ in detail, though the docs state that production uses the same `sortAt` logic. — [PR #5493](https://github.com/bluesky-social/atproto/pull/5493)

### Inferences
- `least(createdAt, indexedAt)` is an anti-abuse rule. It defends the *top* of the feed against future-dated spam and keeps imports from flooding the present. It does *not* defend the middle of the feed against late arrivals; it causes them. Any item whose indexing lags its `createdAt` is slotted behind items the reader may already have scrolled past.
- For a feed where every item arrives minutes to hours after its official publication time, `least()` almost always resolves to the publication time. Bluesky's rule would therefore put essentially *every* late item mid-list, which is the opposite of what the news app wants.

### Gaps
- No Bluesky document gives typical `indexedAt - createdAt` lag, or how often posts land mid-list in practice.
- The Linear design doc for "Following v2 position restoration and new content indicators" linked from PR #5493 is private and was not read.
- No source was found on whether Bluesky's app visually labels heavily backdated (imported) posts. A search for an "archived" indicator found nothing authoritative.

## How do these apps show "new posts" without moving the list the user is reading?

### Takeaway
Both open-source clients use the same pattern: poll or stream in the background, don't insert new items above the reader, and show a button ("Load new posts" / "N new items"). Tapping it scrolls to the top and refreshes. Bluesky's check only peeks at the single newest item, so a late item that sorts below the current top never lights the indicator.

### Cited Findings
- **Bluesky's poll.** The home `FeedPage` declares `POLL_FREQ = 60e3 // 60sec`. Polling is disabled when `hasNew` is already true or the page is not focused. `LoadLatestBtn` renders when `(isScrolledDown || hasNew)`, and `onPressLoadLatest` calls `scrollToTop()` and resets `hasNew`. — [bluesky-social/social-app main: src/view/com/feeds/FeedPage.tsx](https://github.com/bluesky-social/social-app/blob/main/src/view/com/feeds/FeedPage.tsx)
- **Bluesky's check.** `checkForNew` calls `pollLatest(data.pages[0])` and on success calls `onHasNew(true)`, or `refetch()` if the feed is empty. The "Discover" feed always reports new content. A first check runs once the feed is older than `CHECK_LATEST_AFTER = STALE.SECONDS.THIRTY`. — [social-app main: src/view/com/posts/PostFeed.tsx](https://github.com/bluesky-social/social-app/blob/main/src/view/com/posts/PostFeed.tsx)
- **What the check actually fetches.** `pollLatest` calls `page.api.peekLatest()`. For the Following feed that is `getTimeline({limit: 1})`. It then runs the feed tuner in `dryRun` mode on that one post and returns true if a slice survives. — [social-app main: src/state/queries/post-feed.ts](https://github.com/bluesky-social/social-app/blob/main/src/state/queries/post-feed.ts); [src/lib/api/feed/following.ts](https://github.com/bluesky-social/social-app/blob/main/src/lib/api/feed/following.ts)
- **Bluesky's server side.** PR #5493 (merged 2026-09-29) adds `since` / `startCursor` so the client can "fetch upward from the newest item it holds and prepend" for position restoration and new-content indicators. — [atproto PR #5493](https://github.com/bluesky-social/atproto/pull/5493)
- **Mastodon's web UI** keeps streamed statuses in a *pending* queue while the user is scrolled down and shows a "load pending" ("X new items") button. All of the following come from commit-log search snippets, not code read directly. **[pre-2020]**
  - A September 2019 commit, "Fix slow mode issues", stopped the button from altering scroll position and treated pending items as unread.
  - A change that added new items to pending when scrolled down was reverted days later (#11867, fixing #11912).
  - Other fixes addressed "load more" wrongly adding *older* toots to the pending queue.
  — [Mastodon reducers commit log (mirror)](https://gitea.kosmos.org/kosmos/mastodon/commits/commit/162dc845a04741f15d0d8ca70e17f1ee9ed38841/app/javascript/mastodon/reducers); [components commit (mirror)](https://git.chinwag.org/chinwag/chinwagsocial/src/commit/0e8c0287d01d270238aeb7f25c6337b2bcb8afba/app/javascript/mastodon/components)
- **User-side failure.** A user of the Fedilab app reported that fetching new posts while scrolled up made the timeline jump and lose their place, and asked for background loading without a jump. This is a third-party client, not official behaviour. — [Fedilab thread on toot.fedilab.app](https://toot.fedilab.app/@apps/109785667347233682) (2023, judging by the status ID; undated on the page)

### Inferences
- The `hasNew` check compares only the newest item. It answers "is there something above my top?" and cannot answer "did something appear between items I already have?" With `least()` sorting, late items are invisible to the indicator until the user does a full refresh.
- Bluesky's feed tuner deduplicates against posts already seen, so the dry run most likely returns true only when the newest post is not yet displayed. This is inferred from the dry-run usage; `FeedTuner` itself was not read.
- The shared UX contract: never splice new rows above the reader's viewport automatically. Count or flag them, and merge only on an explicit tap or when the user is already at the top.

### Gaps
- Mastodon's current web UI code (`load_pending` component, timeline reducer) was not read directly. The 2019 behaviour may have changed.
- No primary source found for X's "See new posts" pill logic.

## What failure modes are documented when ordering purely by author-provided time?

### Takeaway
All three documented failures come from the same root cause: the sort key is not monotonic in the order items become visible. Future-dated items squat at the top, backdated items break "new items have greater IDs" for every paging client, and late items fall below a "newer than" boundary the client has already passed.

### Cited Findings
- **Future dates pin to the top.** "If you chose a far-future timestamp, that record will always sort at the top" of chronological lists. — [Bluesky docs: Timestamps](https://github.com/bluesky-social/bsky-docs/blob/main/docs/advanced-guides/timestamps.md) (2024). Mastodon guards against the same thing by never minting a Snowflake from a `created_at >= now`. — [snowflake.rb](https://github.com/mastodon/mastodon/blob/main/lib/mastodon/snowflake.rb)
- **Backdated IDs break incremental paging.** Inserting items with older IDs "will break the assumption of consumers of the paging APIs that new items will always have a greater identifier than the last seen one" (2018). **[pre-2020; fix still live]** — [Mastodon PR #7336](https://github.com/mastodon/mastodon/pull/7336)
- **Late items are missed by bounded "newer than" reads.** "Items that land later with a position below the boundary are not seen by a bounded read and clients should still do an occasional unbounded refresh" (2026). — [atproto PR #5493](https://github.com/bluesky-social/atproto/pull/5493)
- **The opposite extreme also fails.** Using only server-ingest time (`indexedAt`) clusters bulk imports and migrations at the import moment. — [Bluesky docs: Timestamps](https://github.com/bluesky-social/bsky-docs/blob/main/docs/advanced-guides/timestamps.md)
- **Stale items flooding feeds.** Mastodon fans a non-live status out to home feeds only if it is under 6 hours old, so old posts discovered later don't appear in followers' feeds. — [status.rb](https://github.com/mastodon/mastodon/blob/main/app/models/status.rb), [create.rb](https://github.com/mastodon/mastodon/blob/main/app/lib/activitypub/activity/create.rb)
- **Secondary data effects.** A code comment in Mastodon's `create.rb` notes that processing an old status "may register tags as being used now as opposed to when the status was really published". Trends and counters are keyed on processing time. — [create.rb](https://github.com/mastodon/mastodon/blob/main/app/lib/activitypub/activity/create.rb)

### Inferences
- Platforms that cared about paging correctness (Mastodon live delivery, X) ended up sorting by a key the *server* assigns when the item becomes visible. The author's time is kept as a displayed field. Bluesky chose author time, clamped, and documents the resulting blind spot.

### Gaps
- No public incident write-up (postmortem) was found on these failures beyond the PR texts above.

## Implications for the news app: which timestamp to sort by, and how to page so new items never land mid-list

### Takeaway
Everything in this section is inferred from the findings above; no new sources. Follow the Mastodon/X model, not Bluesky's `least()` rule. Sort and page by a server-assigned key minted at the moment an item becomes visible in the API, i.e. after the fetcher and AI step finish (`visible_at` plus a tiebreak ID, or one monotonic sequence). Show the official publication date as a label only. Use keyset cursors for older pages, a `since`-style bound for newer items, and a "N new" pill rather than inserting rows above the reader.

### Cited Findings
- Mastodon's precedent: a live item's ID is "based on the time the status is processed". — [Mastodon PR #7336](https://github.com/mastodon/mastodon/pull/7336), [status.rb](https://github.com/mastodon/mastodon/blob/main/app/models/status.rb)
- Bluesky's precedent and its documented blind spot under `least(createdAt, indexedAt)`. — [atproto init migration](https://github.com/bluesky-social/atproto/blob/main/packages/bsky/src/data-plane/server/db/migrations/20230309T045948368Z-init.ts), [atproto PR #5493](https://github.com/bluesky-social/atproto/pull/5493)
- Keyset cursor shape `(sortKey, tiebreak)` with exclusive bounds in both directions, and a `limit + 1` fetch to detect another page. — [atproto pagination.ts](https://github.com/bluesky-social/atproto/blob/main/packages/bsky/src/data-plane/server/db/pagination.ts), [PR #5493](https://github.com/bluesky-social/atproto/pull/5493)
- Gap-free forward paging uses `min_id` ("results immediately greater than this ID") rather than `since_id`. — [Mastodon API guidelines](https://docs.joinmastodon.org/api/guidelines/)

### Inferences
- **Sort key.** The news app's items arrive minutes to hours after official publication. Under `least(published_at, visible_at)` they would nearly always sort by `published_at` and land below items already on screen. A key minted at visibility time makes the feed append-only at the top: no item can appear below one the client already has.
- **Assigning the key.** Set it in the same write that flips an item to visible, i.e. after the AI summary is stored, not at fetch time. Otherwise the AI delay recreates the mid-list problem.
  - If two writers could assign keys concurrently, a key could commit out of order and be skipped by a `since` poll, the same class of bug as PR #5493's caveat.
  - A single serialized writer, or a sequence assigned inside the write transaction, avoids this. This is unverified for the app's database.
- **Paging contract, mirroring Mastodon and Bluesky.**
  - Older pages: `before=<cursor>` (exclusive), ordered `visible_at DESC, id DESC`.
  - Newer items: `after=<newest cursor held>` (exclusive), returned oldest-first or capped, so the client can prepend without holes, like Mastodon's `min_id`.
  - Return opaque string cursors. Never use offset or page-number paging.
- **New-items indicator.** Poll `after=<newest held>` (Bluesky polls every 60 s; any interval works). Show "N new" without touching the list, and prepend on tap or when the user is at the top. Because the key is monotonic in visibility, the count is exact and no late item is missed, unlike Bluesky's `limit: 1` peek.
- **Displayed date vs position.** Two items can show publication dates that appear out of order, e.g. a decision published at 09:00 surfacing above one published at 11:00 because its AI step finished later. Mastodon accepts the same discrepancy.
  - If that matters to readers, label it "added HH:MM" or group by day of visibility.
  - Re-sorting by publication date would reintroduce mid-list insertion.
- **Edits.** If a summary is regenerated, keep the item's original `visible_at` so it doesn't jump. Only deliberate re-surfacing (Mastodon's boost model) should mint a new key. Mastodon boosts get a fresh ID and appear at the top, with dedup if the original is still near the top.
- **Window size.** With about 50–70 items a day over a 7-day window (roughly 350–490 items), an occasional full refresh is cheap. Bluesky's own guidance to "do an occasional unbounded refresh" costs little here.

### Gaps
- Whether the app's backend (Cloudflare D1 per the project docs) serializes writes in a way that guarantees `visible_at` and sequence commit order was not researched here. Verify before relying on a pure `after=` poll.
