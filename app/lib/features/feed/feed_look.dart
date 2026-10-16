import 'package:flutter/material.dart';

import '../../core/article.dart';
import 'feed_filters.dart';
import 'feed_look_a.dart';
import 'feed_look_b.dart';
import 'feed_look_c.dart';
import 'feed_look_now.dart';

/// PROTOTYPE (#66): the feed's looks, to compare design options in one build.
///
/// Everything the feed draws goes through a [FeedLook]; everything it does
/// (loading, errors, empty states, pull to refresh, loading more, the "N new"
/// pill, opening an article, analytics) stays in the feed screen. To change a
/// look, change only its own file: `feed_look_a.dart` for [ALook], and so on,
/// plus any `feed_look_a_*.dart` files of its own. Nothing else needs editing.
enum FeedDesign { now, a, b, c }

/// The look shown now. Settings switches it (the "Design" row); a build can
/// start with another one: `--dart-define=FEED_DESIGN=a`.
final feedDesign = ValueNotifier<FeedDesign>(
  designNamed(const String.fromEnvironment('FEED_DESIGN')),
);

/// `now`, `a`, `b` or `c`, in any case; anything else is [FeedDesign.now].
FeedDesign designNamed(String name) =>
    FeedDesign.values.asNameMap()[name.trim().toLowerCase()] ?? FeedDesign.now;

/// The look for [design]. Looks are created for each build of the feed, so
/// they keep no state: a look that needs some (a carousel's page) keeps it
/// in a StatefulWidget of its own.
FeedLook lookFor(FeedDesign design) => switch (design) {
  FeedDesign.now => NowLook(),
  FeedDesign.a => ALook(),
  FeedDesign.b => BLook(),
  FeedDesign.c => CLook(),
};

/// How the feed looks. The slots that hold lists return SLIVERS, so a long
/// feed builds only the rows on screen: use SliverList (or SliverMainAxisGroup
/// to put a title and a list together), never a Column of every article.
///
/// The screen lays the page out as, top to bottom: the pull-to-refresh
/// control, [masthead], a notice when the refresh failed, [topStories] (when
/// there are top stories), [latest] (when there are later articles) and
/// [feedEnd]. While new articles wait, the screen floats [newPill] just under
/// the masthead as it is on screen: under the filters at the top of the feed,
/// under a pinned bar once folded, near the top once the masthead has gone.
abstract class FeedLook {
  /// The colour behind the whole feed.
  Color background(BuildContext context);

  /// The theme the feed is drawn with: [base] is the app's. Returning another
  /// one changes the shared pieces at once (NewsText styles used by KindLabel,
  /// PublisherLine and the loading, error and empty texts; the divider colour).
  /// Returning [base] itself changes nothing.
  ThemeData theme(BuildContext context, ThemeData base) => base;

  /// The top of the feed: the app's name, today's date, the settings button
  /// and the filters, arranged as the look likes. One sliver (a pinned
  /// SliverPersistentHeader is fine).
  Widget masthead(BuildContext context, FeedMasthead masthead);

  /// "Top stories" as a whole, title included: up to 5 articles, most
  /// important first. A lead card, a list, a carousel or a numbered list.
  /// One sliver; only called when there is at least one article.
  Widget topStories(BuildContext context, FeedSection top);

  /// "Latest" as a whole, title included: one list in the order articles
  /// arrived (no day headings: an article dated yesterday can arrive today).
  /// One sliver, built lazily; only called when there is at least one article.
  Widget latest(BuildContext context, FeedSection latest);

  /// The bottom of the feed: a spinner while more is loading, a retry when
  /// that failed, or the end of the feed. One sliver.
  Widget feedEnd(BuildContext context, FeedEnd end);

  /// "3 new decisions": a plain widget, as small as it looks (taps beside it
  /// reach the feed). The screen places it under the masthead, never on the
  /// name or the filters, and calls [onTap] to show them.
  Widget newPill(
    BuildContext context, {
    required int count,
    required VoidCallback onTap,
  });
}

/// The pieces of the feed's top for [FeedLook.masthead].
class FeedMasthead {
  const FeedMasthead({
    required this.title,
    required this.date,
    required this.openSettings,
    required this.filters,
  });

  /// "Official News": the app's name, the same in every language.
  final String title;

  /// Today in the reader's language: "Friday, 16 October", "Пʼятниця, 16 жовтня".
  final String date;

  /// Opens Settings. [settingsButton] is today's button for it.
  final VoidCallback openSettings;

  /// The filters' state and how to change them; [filterBar] draws today's.
  final FeedFilters filters;

  /// Today's settings button: a round gear with a 44-pt target and its
  /// VoiceOver label. A look may draw its own and call [openSettings].
  Widget get settingsButton => NowSettingsButton(onPressed: openSettings);

  /// Today's filter bar: the Where and Topics pull-downs (#67, #68).
  Widget get filterBar => FeedFilterBar(
    place: filters.place,
    countries: filters.countries,
    topic: filters.topic,
    topicCounts: filters.topicCounts,
    onPlace: filters.onPlace,
    onTopic: filters.onTopic,
  );
}

/// The feed's filters (prototype, #67, #68): where the articles come from
/// (every country, a group or one country) and a topic.
class FeedFilters {
  const FeedFilters({
    required this.place,
    required this.countries,
    required this.topic,
    required this.topicCounts,
    required this.onPlace,
    required this.onTopic,
  });

  final FeedPlace place;

  /// The countries with articles in the loaded feed (ISO codes, 'EU' for the
  /// EU's institutions): the Where menu offers each alone.
  final Iterable<String> countries;

  /// The topic id shown, or null for all topics.
  final String? topic;

  /// Topics with articles under the Where choice, busiest first (names:
  /// [topicName]).
  final List<MapEntry<String, int>> topicCounts;
  final ValueChanged<FeedPlace> onPlace;
  final ValueChanged<String?> onTopic;
}

/// One section of the feed for a look to draw: its title, its articles and
/// what a row does. The screen does the rest.
class FeedSection {
  const FeedSection({
    required this.title,
    required this.articles,
    required this.readIds,
    required this.open,
    this.shown = _nothing,
    this.topic,
  });

  /// "Top stories", "Latest", in the reader's language.
  final String title;
  final List<Article> articles;

  /// The topic the feed is filtered by (an id, as [Article.topics] has it),
  /// or null for every topic. A card that names one topic names this one, so
  /// it agrees with the Topics chip: every article here has it.
  final String? topic;

  /// Articles already opened: they stay in the feed, dimmed.
  final Set<String> readIds;

  /// Opens `articles[index]`: `onTap: () => section.open(i)`. Analytics
  /// records the section and the index as the article's position, so pass
  /// the index in [articles], whatever the layout (a lead card is index 0).
  final ValueChanged<int> open;

  /// Call when the row for `articles[index]` is built, in the item builder:
  /// how deep the reader scrolled, for analytics. Cheap, and safe to call
  /// again; does nothing for Top stories.
  final ValueChanged<int> shown;

  static void _nothing(int _) {}

  int get length => articles.length;
  bool isRead(Article article) => readIds.contains(article.id);
}

/// What the bottom of the feed shows for [FeedLook.feedEnd].
class FeedEnd {
  const FeedEnd({required this.state, required this.retry});

  final FeedEndState state;

  /// Loads the next page again after it failed ([FeedEndState.failed]).
  final VoidCallback retry;
}

enum FeedEndState {
  /// More is loading, or will load when the reader gets near the end.
  loading,

  /// The next page failed to load (offline): offer [FeedEnd.retry].
  failed,

  /// Everything in the feed is shown.
  end,
}
