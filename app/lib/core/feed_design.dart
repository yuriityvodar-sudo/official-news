/// The feed's looks (#66): today's, the design options Yurii compared, and
/// two after Apple News that Roman picked (26 Oct) in our own colours:
/// [garnet], a red deeper than Apple's, and [seal], an official seal's green.
/// Settings → Design switches them. What each one draws is its `FeedLook`
/// (`features/feed/feed_look.dart`); this file is only the names, so the
/// phone's store can keep the choice without the feed's widgets.
enum FeedDesign { now, a, b, c, garnet, seal }

/// The look a new reader sees until one is chosen in Settings → Design:
/// Garnet (Yurii, 28 Oct, #176 and #195). Every other look stays there.
const defaultDesign = FeedDesign.garnet;

/// A look's name (`now`, `a`, `garnet`…), in any case; anything else is
/// [defaultDesign].
FeedDesign designNamed(String name) =>
    FeedDesign.values.asNameMap()[name.trim().toLowerCase()] ?? defaultDesign;
