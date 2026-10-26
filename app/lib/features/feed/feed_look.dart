import 'package:flutter/material.dart';

import '../../core/article.dart';
import '../../core/card_zoom.dart';
import '../../core/feed_design.dart';
import '../../core/filters.dart';
import '../../core/motion.dart';
import '../../core/read_mark.dart';
import '../../core/theme.dart';
import 'feed_look_a.dart';
import 'feed_look_b.dart';
import 'feed_look_c.dart';
import 'feed_look_now.dart';
import 'feed_look_paper.dart';
import 'feed_look_wire.dart';
import 'feed_topic_tabs.dart';
import 'feed_topic_tags.dart';

export '../../core/feed_design.dart';
export 'feed_topic_tabs.dart';

/// The look shown now ([FeedDesign], #66). Settings switches it (the
/// "Design" row); a build can start with another one:
/// `--dart-define=FEED_DESIGN=a`.
///
/// Everything the feed draws goes through a [FeedLook]; everything it does
/// (loading, errors, empty states, pull to refresh, loading more, the "N new"
/// pill, opening an article, analytics) stays in the feed screen. To change a
/// look, change only its own file: `feed_look_a.dart` for [ALook], and so on,
/// plus any `feed_look_a_*.dart` files of its own. Nothing else needs editing.
final feedDesign = ValueNotifier<FeedDesign>(
  designNamed(const String.fromEnvironment('FEED_DESIGN')),
);

/// How read articles look, in every design. Yurii's pick (20 Oct): no
/// marking at all. A build can start with another: `--dart-define=READ_STYLE=blue`.
final readStyle = ValueNotifier<ReadStyle>(
  readStyleNamed(const String.fromEnvironment('READ_STYLE')),
);

/// `none`, `dim`, `blue` or `red`, in any case; anything else is [ReadStyle.none].
ReadStyle readStyleNamed(String name) =>
    ReadStyle.values.asNameMap()[name.trim().toLowerCase()] ?? ReadStyle.none;

/// How many of its topics a card shows at most, in every design: 3 (Yurii's
/// pick, 20 Oct). A build can start with another: `--dart-define=TOPIC_TAGS=1`.
final topicTagCount = ValueNotifier<int>(
  topicTagCountNamed(const String.fromEnvironment('TOPIC_TAGS')),
);

/// `1`, `2` or `3`; anything else is [maxCardTopics].
int topicTagCountNamed(String name) => switch (int.tryParse(name.trim())) {
  final n? when n >= 1 && n <= maxCardTopics => n,
  _ => maxCardTopics,
};

/// The look for [design]. Looks are created for each build of the feed, so
/// they keep no state: a look that needs some keeps it in a StatefulWidget
/// of its own.
FeedLook lookFor(FeedDesign design) => switch (design) {
  FeedDesign.now => NowLook(),
  FeedDesign.a => ALook(),
  FeedDesign.b => BLook(),
  FeedDesign.c => CLook(),
  FeedDesign.paper => PaperLook(),
  FeedDesign.wire => WireLook(),
};

/// How the feed looks. The slot that holds the list returns a SLIVER, so a
/// long feed builds only the rows on screen: use SliverList (or
/// SliverMainAxisGroup to put something before it), never a Column of every
/// article.
///
/// The screen lays the page out as, top to bottom: the pull-to-refresh
/// control, [masthead], a notice when the refresh failed, [articles] (when
/// there are any) and [feedEnd]. While new articles wait, the screen floats
/// [newPill] just under the masthead as it is on screen: under the filters
/// at the top of the feed, under a pinned bar once folded, near the top once
/// the masthead has gone.
abstract class FeedLook {
  /// The colour behind the whole feed.
  Color background(BuildContext context);

  /// The colour under the status bar, for a look whose masthead is a band of
  /// its own colour; null (the default) for [background]. The status bar's
  /// own words turn light or dark to stay readable on it.
  Color? topInset(BuildContext context) => null;

  /// The theme the feed is drawn with: [base] is the app's. Returning another
  /// one changes the shared pieces at once (NewsText styles used by
  /// PublisherLine and the loading, error and empty texts; the divider colour).
  /// Returning [base] itself changes nothing.
  ThemeData theme(BuildContext context, ThemeData base) => base;

  /// The top of the feed: the app's name, today's date, the settings button
  /// and the filters, arranged as the look likes. One sliver (a pinned
  /// SliverPersistentHeader is fine).
  Widget masthead(BuildContext context, FeedMasthead masthead);

  /// The feed's one list (Yurii, 16 Oct): every article, each once, in the
  /// order it arrived in the feed, newest first. No section titles ("Top
  /// stories", "Latest") and no block of its own for the first articles (a
  /// lead card, a carousel, numbers): every row in the same style. No day
  /// headings either: an article dated yesterday can arrive today, and each
  /// row shows its own time. One sliver, built lazily; only called when
  /// there is at least one article.
  Widget articles(BuildContext context, FeedList list);

  /// The bottom of the feed: a spinner while more is loading, a retry when
  /// that failed, or the end of the feed. One sliver.
  Widget feedEnd(BuildContext context, FeedEnd end);

  /// The app's name, small, at the top of the screen once [masthead] has
  /// scrolled away (#141), as iOS folds a large title into its bar; null
  /// (the default) for a look whose masthead keeps a bar pinned itself.
  /// [smallTitle] is the usual one.
  Widget? foldedTitle(BuildContext context, String title) => null;

  /// [title] in the masthead's style, at a bar title's size.
  static Widget smallTitle(BuildContext context, String title) => Text(
    title,
    maxLines: 1,
    style: NewsText.from(context).masthead.copyWith(fontSize: 17, height: 1.2),
  );

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
    required this.filterBar,
    required this.whereChip,
    required this.topic,
    required this.topics,
    required this.onTopic,
  });

  /// "Official News": the app's name, the same in every language.
  final String title;

  /// Today in the reader's language: "Friday, 16 October", "Пʼятниця, 16 жовтня".
  final String date;

  /// Opens Settings. [settingsButton] is today's button for it.
  final VoidCallback openSettings;

  /// The filter bar: the Where and Topics pull-downs (#67, #68), built by
  /// the screen from the feed's state ([FeedFilterBar]). A look places it.
  final Widget filterBar;

  /// The Where pull-down alone, for a look that shows the topics as tabs
  /// instead of the Topics pull-down ([TopicTabs] with [topic], [topics] and
  /// [onTopic]).
  final Widget whereChip;

  /// The chosen topic's id, or null for all topics.
  final String? topic;

  /// The topics the feed offers, busiest first; null while none are known.
  final List<FeedTopic>? topics;

  /// Shows one topic, or every topic for null.
  final ValueChanged<String?> onTopic;

  /// Today's settings button: a round gear with a 44-pt target and its
  /// VoiceOver label. A look may draw its own and call [openSettings].
  Widget get settingsButton => NowSettingsButton(onPressed: openSettings);
}

/// The feed's list for a look to draw: its articles and what a row does.
/// The screen does the rest.
class FeedList {
  const FeedList({
    required this.articles,
    required this.readIds,
    required this.open,
    this.shown = _nothing,
    this.readStyle = ReadStyle.none,
    this.topic,
    this.maxTopics = maxCardTopics,
    this.arriving = false,
    this.entering = const {},
    this.actions = _nothing,
  });

  final List<Article> articles;

  /// The feed has just loaded (#141): its first rows arrive one after
  /// another ([tile]); rows built later, by scrolling, are there at once.
  final bool arriving;

  /// Decisions that have just come in at the top, by id (#141): their rows
  /// spring in one after another and push the others down ([tile]).
  final Set<String> entering;

  /// A long press on `articles[index]`: what can be done without opening it
  /// (share, the official page, copy the link; #141). [tile] wires it up.
  final ValueChanged<int> actions;

  /// How many rows arrive one after another: about a screen.
  static const arrivingRows = 8;

  /// The topic the feed is filtered by (an id, as [Article.topics] has it),
  /// or null for every topic. Every article here has it, and its card shows
  /// it first among its topic tags, so the card agrees with the Topics chip
  /// ([cardTopics]).
  final String? topic;

  /// How many topic tags a card shows at most (3; a build may set 1 or 2,
  /// [topicTagCount]). Give each card `cardTopics(article, first: topic,
  /// max: maxTopics)`, or [topicsOf].
  final int maxTopics;

  /// Articles already opened: they stay in the feed, dimmed or without the
  /// unread dot ([readStyle]).
  final Set<String> readIds;

  /// How read articles look ([ReadStyle]): give each row [markOf] its article.
  final ReadStyle readStyle;

  /// Opens `articles[index]`: `onTap: () => list.open(i)`. Analytics
  /// records the index as the article's position in the feed.
  final ValueChanged<int> open;

  /// Call when the row for `articles[index]` is built, in the item builder:
  /// how deep the reader scrolled, for analytics. Cheap, and safe to call
  /// again.
  final ValueChanged<int> shown;

  static void _nothing(int _) {}

  int get length => articles.length;

  /// The row of `articles[index]` as every look shows it (#141): it shrinks
  /// a little while held and springs back; just after the feed has loaded,
  /// the first rows arrive one after another, and a decision that has just
  /// come in springs in ([entering]). Its article grows out of it when
  /// opened ([ZoomSource]). Wrap each row in the item builder:
  /// `list.tile(i, MyRow(...))`.
  Widget tile(int index, Widget row) => ZoomSource(
    id: articles[index].id,
    child: Arrive(
      animate: arriving && index < arrivingRows,
      delay: Duration(milliseconds: 45 * index),
      child: GrowIn(
        animate: entering.contains(articles[index].id),
        delay: Duration(milliseconds: 70 * index),
        child: PressScale(onLongPress: () => actions(index), child: row),
      ),
    ),
  );

  /// The line after the row of `articles[index]`, in a list with lines
  /// between rows: it springs in with its row ([entering]), so the rows
  /// under it do not jump. `separatorBuilder: (_, i) => list.line(i, line)`.
  Widget line(int index, Widget line) => GrowIn(
    animate: entering.contains(articles[index].id),
    delay: Duration(milliseconds: 70 * index),
    child: line,
  );

  bool isRead(Article article) => readIds.contains(article.id);

  /// What the row of [article] shows of it being read: faded (Dim), or the
  /// unread dot in place of the official-source tick (Blue, Red).
  ReadMark markOf(Article article) =>
      ReadMark(readStyle, read: isRead(article));

  /// The topics the card of [article] shows as tags, in order: the filtered
  /// topic first, then the article's own order, at most [maxTopics]; none for
  /// an article without topics (its card then has no tag row at all).
  List<String> topicsOf(Article article) =>
      cardTopics(article, first: topic, max: maxTopics);
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
