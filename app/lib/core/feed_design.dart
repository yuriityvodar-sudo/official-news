/// The feed's looks (#66): today's and the design options Yurii compared;
/// Settings → Design switches them. What each one draws is its `FeedLook`
/// (`features/feed/feed_look.dart`); this file is only the names, so the
/// phone's store can keep the choice without the feed's widgets.
enum FeedDesign { now, a, b, c }

/// `now`, `a`, `b` or `c`, in any case; anything else is [FeedDesign.now].
FeedDesign designNamed(String name) =>
    FeedDesign.values.asNameMap()[name.trim().toLowerCase()] ?? FeedDesign.now;
