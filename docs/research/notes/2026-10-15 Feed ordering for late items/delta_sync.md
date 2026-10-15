# Delta sync with sequence numbers, history IDs and sync tokens

Scope: how established products sync a changing list to clients ("everything after X"), and whether a server-assigned monotonic sequence is a sound design for a small news feed (Flutter client; Cloudflare Workers + D1/SQLite; about 500 items in a 7-day window; 50–70 new items a day; items can be updated or hidden later). Sources were fetched 2026-10-15. Page dates are given where the page shows one.

## Google: Gmail historyId / users.history.list, Calendar syncToken, Drive changes.list

### Takeaway
All three Google APIs use the same shape. The first sync is a full list. The server then returns an opaque position (historyId, nextSyncToken, newStartPageToken). The client stores it and asks for "changes since" it. Deletions arrive in the change feed. When the position is too old, the server returns an error (Gmail 404, Calendar 410) and the documented fix is to wipe local state and run a full sync. Google explicitly calls the older timestamp-based method (`modifiedSince` on `updated`) "no longer recommended" because it misses updates more easily.

### Cited Findings
**Gmail (guide last updated 2026-09-15)**
- After a full sync, the app should "store the historyId of the most recent message". Partial sync calls `users.history.list` with a required `startHistoryId` and returns history records (message IDs and change types, such as added or labels modified) since that ID. — [Gmail sync guide](https://developers.google.com/workspace/gmail/api/guides/sync)
- Full sync: `messages.list` for IDs, then batched `messages.get`. Use `format=full`/`raw` the first time, then `format=minimal` for cached messages, "since only labelIds might change". — [Gmail sync guide](https://developers.google.com/workspace/gmail/api/guides/sync)
- Retention: "History records are typically available for at least one week and often longer". The window "might be significantly shorter", and records "might be unavailable in rare cases". — [Gmail sync guide](https://developers.google.com/workspace/gmail/api/guides/sync)
- Expiry: if the ID is out of range, "the Gmail API returns an HTTP 404 error response", and "your client must perform a full sync". — [Gmail sync guide](https://developers.google.com/workspace/gmail/api/guides/sync)
- Ordering: "History IDs increase chronologically but are not contiguous with random gaps in between valid IDs." "Supplying an invalid or out of date startHistoryId typically returns an HTTP 404 error code." The response `historyId` is "The ID of the mailbox's current history record." — [users.history.list reference](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.history/list)
- Push notifications are used only to trigger a partial sync. They tell the client to pull and do not replace the pull. — [Gmail sync guide](https://developers.google.com/workspace/gmail/api/guides/sync)

**Google Calendar (guide last updated 2026-09-11)**
- The first full sync stores `nextSyncToken`, which is "present only on the very last page". Incremental sync sends it back as `syncToken`. — [Calendar sync guide](https://developers.google.com/workspace/calendar/api/guides/sync)
- Deletions: during incremental sync "the result will always contain deleted entries" (tombstones are always delivered). — [Calendar sync guide](https://developers.google.com/workspace/calendar/api/guides/sync)
- Paging inside a delta: if many items changed, the response carries `nextPageToken` instead of a sync token. The client repeats the same query with the same `syncToken` plus `pageToken` until the last page returns a new sync token. — [Calendar sync guide](https://developers.google.com/workspace/calendar/api/guides/sync)
- Filter restrictions: "The set of query parameters that can be used on incremental syncs is restricted". "Each list request should use the same set of query parameters, including the initial request". Disallowed parameters return HTTP 400. The sample notes "Sync tokens aren't compatible with most filters". Its full sync limits history with `timeMin` (one year). — [Calendar sync guide](https://developers.google.com/workspace/calendar/api/guides/sync)
- Expiry: tokens can be invalidated by expiration or ACL changes, and the server returns 410. "This should trigger a full wipe of the client's store and a new full sync." The Java sample deletes the token, clears the local store and re-runs full sync. — [Calendar sync guide](https://developers.google.com/workspace/calendar/api/guides/sync)
- Timestamp method deprecated: the legacy `updated` + `modifiedSince` approach is "no longer recommended" because it is more error-prone for missed updates. — [Calendar sync guide](https://developers.google.com/workspace/calendar/api/guides/sync)

**Google Drive (guide last updated 2026-09-03)**
- `changes.getStartPageToken` gives a token for the current state. `changes.list` returns changes; "Entries in the changes collection are in chronological order (the oldest changes appear first)". — [Drive: Retrieve changes](https://developers.google.com/workspace/drive/api/guides/manage-changes)
- Two tokens: if `nextPageToken` is present, page on. If not, "the client application should store the newStartPageToken in the response for future use." `includeRemoved` controls whether removed items appear. — [Drive: Retrieve changes](https://developers.google.com/workspace/drive/api/guides/manage-changes)
- `changes.watch` notifications only signal that changes exist. The client still polls the change feed for the details. — [Drive: Retrieve changes](https://developers.google.com/workspace/drive/api/guides/manage-changes)

### Inferences
- The common contract is: (1) the server owns an ordered change position; (2) the client stores one opaque value; (3) a delta can span pages, and the new position is handed over only after the last page; (4) deletes are in-band records; (5) there is a documented "too old, start over" error that leads to a full resync. A news app's `?since=N` API mirrors this directly. The 404/410 analogue would be a "reset" response.
- Gmail's IDs are monotonic with gaps, so a client must treat the cursor as an ordering key, never as a count. The same holds for a D1 sequence with gaps.
- Calendar's "full sync limited by timeMin, then deltas" is the same shape as "initial sync of the 7-day window, then deltas".

### Gaps
- The Drive guide does not document token expiry. I did not check the `changes.list` reference for the `removed` field structure.
- No Google page I fetched states the server-side mechanism behind historyId (for example, whether it is assigned at commit).

## Slack: conversations.history, pagination evolution, client catch-up

### Takeaway
Slack's public guidance is about paging, not delta sync. Its engineering post (2017, updated 2020) explains why offset pagination breaks under frequent inserts and why Slack moved to opaque cursors built on a unique, sequential column. `conversations.history` uses each message's server-assigned, unique-per-channel `ts` as a sortable cursor (`oldest`/`latest`). I found no primary source on how Slack's own clients catch up after a disconnect.

### Cited Findings
- "Evolving API Pagination at Slack", Michael Hahn, 2017-08-15 (updated 2020-06-25). On offsets: "Using LIMIT <count> OFFSET <offset> doesn't scale well for large datasets", and "If items are being written to the dataset at a high frequency, the page window becomes unreliable". Example: after 10 new messages arrive, page 2 repeats page 1. — [Slack Engineering](https://slack.engineering/evolving-api-pagination-at-slack/)
- Cursor pros, as stated: an indexed WHERE clause scales well and the window stays stable during writes. Cons: the cursor needs a unique, sequential column; there is no total count; and clients cannot jump to a page. — [Slack Engineering](https://slack.engineering/evolving-api-pagination-at-slack/)
- Opaque cursors were chosen so the server can "implement different underlying pagination schemes per endpoint". For example, an encoded offset for legacy `files.list`, or several shard IDs for Enterprise Grid. — [Slack Engineering](https://slack.engineering/evolving-api-pagination-at-slack/)
- `conversations.history`: "All messages have both a type and a sortable ts". The ts "uniquely identif[ies] it within a conversation". `oldest` means "Only messages after this Unix timestamp will be included", and the boundary message is excluded unless `inclusive=true`. Paging works by `ts` (set `latest` to the last message's ts) or by `response_metadata.next_cursor`. `limit` defaults to 100 (max 999; "no more than 200" recommended). — [Slack API: conversations.history](https://docs.slack.dev/reference/methods/conversations.history)
- Since 2025-05-29, new installs of non-Marketplace commercial apps are limited to 1 request/minute and 15 objects per call on this method. — [Slack API: conversations.history](https://docs.slack.dev/reference/methods/conversations.history)
- Slack's edge cache "Flannel" served slimmed-down startup data so clients could boot faster. This is from a third-party summary, not primary. — [StackShare 2017 summary (secondary)](https://stackshare.io/posts/102366439899855989); QCon 2018 slides list reconnect cost as a problem — [QCon SF 2018 slides](https://qconsf.com/sf2018/system/files/presentation-slides/scaling_slack_-_qcon_2018.pdf)

### Inferences
- Slack's `ts` works as a "since" cursor only because the server assigns it and it is unique per channel. A client-side or wall-clock timestamp would not have that guarantee.
- "Messages after oldest ts" returns only new messages. It does not return edits or deletes of older messages. Slack delivers those over a separate event stream. A single sequence bumped on every change (insert, update, hide) folds both into one query, which is simpler for a small app.

### Gaps
- No primary Slack source found on how desktop/mobile clients reconcile missed messages, edits and deletes after reconnect. The Flannel and QCon material covers boot data, not delta semantics.
- I did not verify in this session the Events API `message_changed` / `message_deleted` subtypes that carry edits and deletes.

## CouchDB/PouchDB _changes, CloudKit change tokens, Firestore listeners, Dropbox cursors (plus Electric, Replicache, Stripe)

### Takeaway
Each of these systems exposes a per-dataset change log with a server-issued position: CouchDB `seq`, CloudKit `CKServerChangeToken`, Dropbox `cursor`, Electric `offset`+`handle`, Replicache `cookie`. Deletes are delivered as records (`deleted:true`, a deleted-record callback, a `del` op, a deletion entry). Each also has an explicit "start over" signal: Dropbox 409 `reset`, CloudKit `changeTokenExpired`, Electric `must-refetch`. Two properties recur: only the latest state per item is guaranteed (intermediate updates collapse), and consumers should be idempotent because changes may repeat.

### Cited Findings
**CouchDB `_changes`**
- Returns changes "in time order of application". "Only the most recent change for a given document is guaranteed to be provided", so intermediate states can be skipped. — [CouchDB _changes](https://docs.couchdb.org/en/stable/api/database/changes.html)
- `since` starts "from the change immediately after the given update sequence". Accepts a seq or `now`; default 0. Sequences look like `"5-g1AAAAI..."` and, per the 2.0.0 changelog note, "can be any valid json object". `last_seq` is "the update sequence of the last update returned". — [CouchDB _changes](https://docs.couchdb.org/en/stable/api/database/changes.html)
- Each row has `deleted: true` for deleted documents. Feed modes: `normal`, `longpoll`, `continuous`, `eventsource`. `limit` caps rows. — [CouchDB _changes](https://docs.couchdb.org/en/stable/api/database/changes.html)
- Clustered caveat: "The results returned by _changes are partially ordered", and "the order is not guaranteed to be preserved for multiple calls". If replicas for a `since` value are unavailable, "you might see changes again that you have previously seen", so consumers must be idempotent. — [CouchDB _changes](https://docs.couchdb.org/en/stable/api/database/changes.html)
- Tombstones: DELETE "Marks the specified document as deleted by adding a field _deleted with the value true". Such documents "stay in the database", leaving "a tombstone with very basic information". "The tombstone is required so that the delete action can be replicated across databases." — [CouchDB document API](https://docs.couchdb.org/en/stable/api/document/common.html)

**Apple CloudKit**
- `CKFetchRecordZoneChangesOperation`: the configuration holds "a server change token, which is an opaque pointer to a specific change in the zone's history. CloudKit returns only the changes that occur after that point." Use `nil` for the first fetch or "to refetch all changes". — [Apple docs](https://developer.apple.com/documentation/cloudkit/ckfetchrecordzonechangesoperation)
- "Each batch yields a new change token… The change tokens conform to NSSecureCoding and are safe to cache on-disk… Don't infer behavior or order from the tokens' contents." Deleted records arrive via `recordWithIDWasDeletedBlock` ("when a record no longer exists"). The completion block has a `moreComing` flag. — [Apple docs](https://developer.apple.com/documentation/cloudkit/ckfetchrecordzonechangesoperation)
- Guidance: fetch all changes on first launch, cache on device, then subscribe (`CKRecordZoneSubscription`) and fetch on push. "it's not necessary to perform fetches each time your app launches, or to schedule fetches at regular intervals." — [Apple docs](https://developer.apple.com/documentation/cloudkit/ckfetchrecordzonechangesoperation)
- `CKError.Code.changeTokenExpired`: "An error that occurs when the change token expires." The page has no discussion section. — [Apple docs](https://developer.apple.com/documentation/cloudkit/ckerror/code/changetokenexpired)

**Firestore**
- Offline persistence "caches a copy of the Cloud Firestore data that your app is actively using". It is on by default on Android/Apple and off on web. `fromCache: true` means data "might be stale or incomplete". Default cache threshold is 100 MB. — [Firestore offline](https://firebase.google.com/docs/firestore/manage-data/enable-offline)
- Billing shows the cost of a lost delta position. A read is charged "each time a document in the result set is added or updated". If a listener is disconnected for more than 30 minutes (with persistence on), "you will be charged for documents and index entries read as if you had issued a brand-new query". Without persistence, any reconnect is charged as a new query. — [Firestore pricing](https://firebase.google.com/docs/firestore/pricing)

**Dropbox**
- `list_folder` returns `cursor` + `has_more`. A cursor marks the folder state at a point in time. `list_folder/continue` returns the next page or changes since. `get_latest_cursor` skips enumeration when only future changes matter. `list_folder/longpoll` "will simply block until a change is detected (or its timeout occurs)". Results say whether each entry is a file change, a folder change or a deletion. — [Dropbox detecting changes](https://docs.dropboxapi.com/dropbox-api/docs/detecting-changes)
- Expiry: cursors can expire if unused for an extended time. An expired cursor gets a 409 `reset` error, and the fix is to call `list_folder` again. Always store the latest cursor, even when a response has no entries. Rapid polling is discouraged in favour of longpoll or webhooks. — [Dropbox detecting changes](https://docs.dropboxapi.com/dropbox-api/docs/detecting-changes)

**Electric (Postgres sync engine, HTTP shape API)**
- The shape log's `offset` "identifies a position in the log". `offset=-1` requests "the whole log, from the start". Each response carries an `electric-offset` header for the next request, and the client is caught up at an `up-to-date` control message. `live=true` long-polls. A `must-refetch` control message means the client must discard local data and resync. — [Electric HTTP API](https://electric.ax/docs/api/http)
- Delta responses carry `cache-control` and `etag`, so CDNs (including Cloudflare) can cache initial-sync responses and coalesce live long-polls. — [Electric HTTP API](https://electric.ax/docs/api/http)

**Replicache "Global Version" strategy**
- "A single global version is stored in the database and incremented on each push". Each entity has `lastModifiedVersion` and a `deleted` flag. Pull returns rows with `lastModifiedVersion > cookie` as `put`/`del` ops. Deletes are soft, and "Soft Deletes are annoying to maintain". — [Replicache: Global Version](https://doc.replicache.dev/strategies/global-version)
- Cost: "all pushes server-wide are serialized". At 20 ms per push, that is about 50 pushes/s maximum. Access-rule changes do not bump entity versions unless you bump them explicitly. — [Replicache: Global Version](https://doc.replicache.dev/strategies/global-version)

**Stripe events (retention as an expiry analogue)**
- "List events, going back up to 30 days." Paging uses object-ID cursors `starting_after` / `ending_before`, with `limit` 1–100. — [Stripe API: List events](https://docs.stripe.com/api/events/list)

### Inferences
- The industry-standard set of pieces is: a server-issued position, delete records, a "more pages" flag, an explicit reset signal, and idempotent apply. A news-feed `?since=N` design that returns `{items, deleted_ids or hidden flags, next_since, has_more}` plus a `reset` response is the same pattern at small scale.
- CouchDB, CloudKit and Replicache all collapse multiple updates to one item into a single latest row. A per-row `seq` that is overwritten on every change gets this for free: an item edited three times appears once, with its latest content.
- Electric shows that delta responses can still be CDN-cached when many clients share the same offset. That partly answers the "per-client cursor kills caching" concern. It requires quantised or shared cursors, which a small app might not need.

### Gaps
- PouchDB pages were not fetched. PouchDB implements the CouchDB replication protocol (general knowledge, not verified here).
- Firestore's internal resume-token mechanism and `docChanges` `removed` semantics were not in the fetched text.
- Apple's fetched pages give no recovery procedure for `changeTokenExpired`. The common practice (set the token to nil, clear the zone cache, refetch) is from general knowledge, not a fetched Apple source.
- Dropbox's cursor expiry period is not stated ("extended time").

## Local-first / offline-first patterns: small local store synced by sequence; pitfalls; trade-offs vs re-fetching; when it is overkill

### Takeaway
"Full fetch once, then deltas since a stored position, with tombstones and a reset path" is the documented norm (Google, Apple, Dropbox, CouchDB, Electric, Replicache). Its recurring costs are: keeping tombstones long enough, a reset/resync path that must be tested, a cursor that cannot be stored client-side without the data it describes, and filter or schema changes that invalidate cursors. For very small or rarely changing data, sync-engine vendors themselves say "send everything every time" is acceptable.

### Cited Findings
- Replicache's simplest strategy, "Reset", "sends the entire client view on every pull response, so no patch calculation is necessary at all". "Sending the entire client view on each pull this way is very inefficient, so this approach is not usually recommended". Yet it "works if your data changes infrequently or is very small", and some customers use it in production. — [Replicache: Reset strategy](https://doc.replicache.dev/strategies/reset)
- Keyset ("seek") pagination is the alternative for "re-fetch a sorted page". OFFSET drifts when rows are inserted between fetches (duplicates). Keyset avoids drift and is faster, but "you cannot directly navigate to arbitrary pages". (Markus Winand, 2014-08-06, updated 2023-09-08.) — [Use The Index, Luke: No Offset](https://use-the-index-luke.com/no-offset)
- Slack: offset windows become "unreliable" under frequent writes; cursors need "a unique, sequential column". — [Slack Engineering](https://slack.engineering/evolving-api-pagination-at-slack/)
- Tombstones are needed so deletions propagate. CouchDB keeps them permanently for replication. — [CouchDB document API](https://docs.couchdb.org/en/stable/api/document/common.html)
- Cursor invalidation by changed query/filter: Calendar requires the same query parameters on every incremental request and returns 400 otherwise. — [Calendar sync guide](https://developers.google.com/workspace/calendar/api/guides/sync)
- Reset path: Calendar says wipe the store and full sync on 410. Gmail says full sync on 404. Electric says discard and resync on `must-refetch`. — [Calendar](https://developers.google.com/workspace/calendar/api/guides/sync); [Gmail](https://developers.google.com/workspace/gmail/api/guides/sync); [Electric](https://electric.ax/docs/api/http)
- Read-authorization or visibility changes need their own version bump, because a row whose content did not change keeps its old version. — [Replicache: Global Version](https://doc.replicache.dev/strategies/global-version)
- Replicache warns that a client storing a cursor ahead of its data will never get the missing rows: "A browser refresh doesn't fix it because Replicache reads its cached data". This is the general risk of persisting a cursor separately from the data. — [Replicache: Global Version](https://doc.replicache.dev/strategies/global-version)
- Secondary (non-primary, general guidance): tombstones should be garbage-collected only after a TTL longer than the longest offline period. Missing tombstones show up as deleted items reappearing. Local schema changes need additive migrations or versioned shapes. Pulling everything to every device is called out as a mistake at scale. — [RapidNative blog (secondary)](https://www.rapidnative.com/blogs/sync-data-across-devices); [techinterview.org (secondary)](https://www.techinterview.org/post/3233474986/design-offline-first-mobile-app/)

### Inferences (applied to the news app; estimates labelled)
- The design under consideration is standard: `seq` bumped when an item becomes visible, changes, or is hidden; client asks `since=N`. It is the Replicache "global version" / Gmail historyId pattern with one table.
- Points that follow from the sources:
  1. Hiding is an update. Keep the row, set `hidden=1`, and bump `seq`, so the client receives it as a delete (the Calendar "always contain deleted entries" rule).
  2. Items aging out of the 7-day window need no tombstone. The client can prune locally by date.
  3. If a cleanup job hard-deletes rows (including hidden tombstones), the server must keep a watermark (for example `min_valid_seq`). Any `since` below it gets a `reset` (like Gmail 404 / Calendar 410 / Dropbox 409 reset) so the client refetches the window.
  4. Persist `next_since` in the same local transaction as the applied rows (the CloudKit and Replicache lesson).
  5. Applying rows must be idempotent (upsert by id), because a page may be re-requested (CouchDB lesson).
  6. Bump `seq` on anything that changes what the client shows. That includes the ordering field and the visibility flag, not just content (Replicache read-auth lesson).
  7. If a filter or schema change alters what "the list" means, the server should force `reset` (Calendar same-params rule).
  8. A client schema migration can simply drop the local store and the cursor, then do a full sync. At about 500 items this is cheap.
- Trade-off vs simply re-fetching the sorted 7-day page:
  - Re-fetching is simpler. It has no tombstones, no reset path and no cursor bugs, and the same response is CDN-cacheable for all users.
  - At about 500 items it is small (rough estimate only: about 0.5–1 MB uncompressed if each item with summary is 1–2 KB; not measured).
  - Its weaknesses are bandwidth on every refresh, and no "what changed" signal for UI such as "3 new items" or a smooth insert of late-arriving items. Paging a re-fetch by offset also drifts (Slack, Winand).
  - Delta sync makes routine refreshes tiny (tens of rows a day) and gives an exact "new or changed since last view" set. The cost is the extra state machine.
- When it is overkill: per Replicache's own wording, a full fetch is acceptable when data "changes infrequently or is very small". About 500 items is small. A middle ground is full re-fetch with an ETag/`If-None-Match` (304 when unchanged), which removes most of the bandwidth cost without cursor state. I did not research this in depth here; see Gaps. Delta sync earns its keep mainly when (a) the client keeps a persistent offline store anyway, (b) the UI needs exact change sets (late items inserted mid-list, "updated" badges), or (c) refreshes are frequent enough that full payloads cost real bandwidth or Worker/D1 reads.

### Gaps
- No primary source found on mobile local-store pitfalls specific to Flutter (for example sqflite/drift migration patterns). The secondary sources above are generic and not authoritative.
- Firestore's "30 minutes" rule shows a vendor-imposed resume window, but I found no published retention figure for most other systems (Drive, Dropbox).
- HTTP ETag/304 for full re-fetch, as a cheaper alternative, was not researched in this pass.
- No measured payload size for the app's items. The figures above are estimates.

## Monotonic integer sequence vs timestamp for "changes since"; commit-order hazards; SQLite/D1 behaviour

### Takeaway
Timestamps are the documented wrong choice for "changes since". Google deprecated `modifiedSince` as error-prone, and Replicache says last-modified timestamps "can't be done correctly". Even integer IDs from a sequence are unsafe in concurrent multi-writer databases (Postgres), because a lower ID can commit after a higher one and a max-ID cursor then skips it. The fix everywhere is to serialize sequence assignment with commit. SQLite allows only one writer at a time, and D1 is single-threaded and runs `batch()` as a sequential transaction. So on D1 a `seq` assigned inside the writing statement or batch commits in assignment order, and the out-of-order hazard does not arise. The remaining risks are: computing `seq` outside the transaction, reusing rowids, and reading the cursor in a different snapshot than the rows.

### Cited Findings
- Timestamp failure mode: a write that started at t1 can commit after a pull at t2 has read the data. "That pull's client then has a timestamp past the missing changes, and the server never resends them." Last-modified timestamps "can't be done correctly, and we strongly advise against trying". The global version works by "forcing the database to process pushes serially". — [Replicache: Global Version](https://doc.replicache.dev/strategies/global-version)
- Google Calendar's timestamp method (`updated` + `modifiedSince`) is "no longer recommended", being more error-prone for missed updates. — [Calendar sync guide](https://developers.google.com/workspace/calendar/api/guides/sync)
- Postgres sequences "do not actually guarantee that values are assigned in increasing order" of visibility. Two transactions get IDs 4 and 5, 5 commits first, a poller's cursor becomes 5, then 4 commits and "that row would never be returned to the client". cloudscale's fix was a deferred constraint trigger that, at commit, takes an exclusive lock on a lock-only table and calls `nextval()`. IDs are then handed out in commit order at the cost of serialized commits (cloudscale engineering blog, 2025-10-09). — [cloudscale](https://www.cloudscale.ch/en/engineering-blog/2025/10/09/generating-truly-sequential-ids-in-postgresql)
- Same class of problem in event stores and replication. Axon tracks gaps in its event sequence and re-checks them, at a performance cost. Older replication tools gave up on total order and moved between consistent snapshots. These are from search snippets, not fetched in full. — [Axon: Auto-Increment and Sequences](https://docs.axoniq.io/relational-database-guide/4.10/auto-increment); [OSM dev list, 2009](https://lists.openstreetmap.org/pipermail/dev/2009-May/015284.html); [event-driven.io: ordering in Postgres outbox](https://event-driven.io/en/ordering_in_postgres_outbox/)
- Gmail's history IDs "increase chronologically but are not contiguous with random gaps", so gaps are normal and harmless for a `>` cursor. — [Gmail history.list](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.history/list)
- SQLite WAL: "there can only be one writer at a time". "Readers do not block writers and a writer does not block readers". Each reader's end mark "is unchanged for the duration of the transaction, thus ensuring that a single read transaction only sees the database content as it existed at a single point in time." — [SQLite WAL](https://www.sqlite.org/wal.html)
- SQLite rowid without AUTOINCREMENT is max+1. "ROWIDs from previously deleted rows might be reused… and newly created ROWIDs might not be in strictly ascending order". With AUTOINCREMENT, IDs are "guaranteed to be monotonically increasing" and never reused, but can have gaps. "Only ROWID values from previous transactions that were committed are considered". AUTOINCREMENT "imposes extra CPU, memory, disk space, and disk I/O overhead". — [SQLite AUTOINCREMENT](https://www.sqlite.org/autoinc.html)
- D1: "Each individual D1 database is inherently single-threaded, and processes queries one at a time". Throughput is tied to query duration (1 ms per query means at most about 1,000 queries/s). Max size is 10 GB paid / 500 MB free. — [D1 limits](https://developers.cloudflare.com/d1/platform/limits/)
- D1 `batch()`: "each statement in the list will execute and commit, sequentially, non-concurrently". "Batched statements are SQL transactions". A failure "aborts or rolls back the entire sequence". — [D1 Database API](https://developers.cloudflare.com/d1/worker-api/d1-database/)
- D1 read replicas (Sessions API) give sequential consistency within a session. The default first query can go to "any database instance" and may be stale. Use `first-primary` or bookmarks for up-to-date data. — [D1 Database API](https://developers.cloudflare.com/d1/worker-api/d1-database/)

### Inferences
- On D1 (one writer, serial execution), assigning `seq` inside the same SQL statement or `batch()` as the change makes assignment order equal commit order. Two ways to do this: `UPDATE articles SET seq = (SELECT COALESCE(MAX(seq),0)+1 FROM articles) …`, or a one-row counter table bumped in the same batch. This avoids the Postgres hazard without cloudscale's lock-at-commit trick.
- The unsafe variant is reading `MAX(seq)` in one Worker request and writing `seq` in a later, separate statement. Two concurrent Worker invocations (fetcher plus summarizer) could then compute the same value.
- Do not use the plain `rowid`/id as the change cursor. It is fixed at insert, so updates and hides would not move it. Without AUTOINCREMENT it can be reused after deleting the max row. A dedicated, indexed `seq` column that is rewritten on every visible change is the right shape. Gaps are fine.
- Return the cursor from the same snapshot as the rows: `next_since = MAX(seq)` of the returned rows, or read in the same batch. A separately read "current global seq" could run ahead of the rows if a write landed in between. That is exactly the skip Replicache describes. Gmail's "current history record" works because Google controls that snapshot.
- If D1 read replicas are enabled later, a replica may lag. This causes no skipped rows if the cursor comes from the rows actually returned: the client just sees them on the next poll. A cursor obtained from the primary and then used against a lagging replica returns nothing new until the replica catches up, which delays but does not lose rows.
- Throughput is a non-issue here. Replicache's ~50 serialized pushes/s ceiling is irrelevant at a fetcher cadence of 2 sources/minute and about 70 new items/day.
- Using `published_at` (source-supplied time) as the cursor is unsafe for late-arriving items: an item published at 09:00 but fetched at 11:00 sorts below a client's 10:00 cursor and is never delivered. Display order (by `published_at`) and sync order (by `seq`) should be separate fields. The client syncs by `seq` and sorts locally by `published_at`.

### Gaps
- No Cloudflare doc explicitly states that writes to D1 commit in the order they execute. This is inferred from "single-threaded… one at a time" and the sequential-commit wording for `batch()`.
- I did not verify whether D1 SQL supports `RETURNING` on `UPDATE` for returning the assigned `seq` in one statement (SQLite ≥3.35 supports it; D1 support not checked here).
- The OSM, Axon and event-driven.io sources were seen only as search snippets, not read in full.
