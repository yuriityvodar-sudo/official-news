import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/article.dart';
import '../../core/card_zoom.dart';
import '../../core/countries.dart';
import '../../core/news_widgets.dart';
import '../../core/read_mark.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import 'feed_look.dart';
import 'feed_look_now.dart';
import 'feed_topic_tags.dart';
import 'feed_touches.dart';

/// Design «Newspaper» (Roman, 26 Oct), after The New York Times app: black
/// on white (white on near-black in dark mode), the nameplate centred over
/// a black rule, serif headlines, hairlines between the rows instead of
/// cards, and the topics as tabs under the nameplate ([TopicTabs]). The
/// only colours are the pictures' and one dark blue, for the official-source
/// mark and a decision of the last hour. Every row alike, as in every look
/// (Yurii, 16 Oct).
class PaperLook extends FeedLook {
  @override
  Color background(BuildContext context) => _Paper.of(context).paper;

  @override
  Widget masthead(BuildContext context, FeedMasthead masthead) {
    final paper = _Paper.of(context);
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 10, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    masthead.title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: paper.nameplate,
                  ),
                ),
                masthead.settingsButton,
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
            child: Text(
              masthead.date.toUpperCase(),
              textAlign: TextAlign.center,
              style: paper.dateline,
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: paper.ink),
                bottom: BorderSide(color: paper.rule),
              ),
            ),
            child: TopicTabs(
              topic: masthead.topic,
              topics: masthead.topics,
              onTopic: masthead.onTopic,
              color: paper.muted,
              chosenColor: paper.ink,
              mark: paper.ink,
              leading: masthead.whereChip,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget? foldedTitle(BuildContext context, String title) =>
      FeedLook.smallTitle(context, title);

  @override
  Widget articles(BuildContext context, FeedList list) {
    final paper = _Paper.of(context);
    return SliverPadding(
      padding: const EdgeInsets.only(top: 4),
      sliver: SliverList.separated(
        itemCount: list.length,
        separatorBuilder: (_, i) => list.line(
          i,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(height: 1, thickness: 1, color: paper.rule),
          ),
        ),
        itemBuilder: (context, i) {
          final a = list.articles[i];
          list.shown(i);
          return list.tile(
            i,
            _Row(
              article: a,
              mark: list.markOf(a),
              topics: list.topicsOf(a),
              onTap: () => list.open(i),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget feedEnd(BuildContext context, FeedEnd end) {
    final paper = _Paper.of(context);
    final l10n = AppLocalizations.of(context);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 48),
      sliver: SliverToBoxAdapter(
        child: Center(
          child: switch (end.state) {
            FeedEndState.failed => CupertinoButton(
              onPressed: end.retry,
              child: Text(
                l10n.feedLoadMoreFailed,
                textAlign: TextAlign.center,
                style: paper.meta.copyWith(color: paper.accent),
              ),
            ),
            FeedEndState.loading => const CupertinoActivityIndicator(),
            FeedEndState.end => Text(l10n.feedEnd, style: paper.meta),
          },
        ),
      ),
    );
  }

  @override
  Widget newPill(
    BuildContext context, {
    required int count,
    required VoidCallback onTap,
  }) {
    final paper = _Paper.of(context);
    return NewsPill(
      label: AppLocalizations.of(context).newDecisions(count),
      color: paper.ink,
      onColor: paper.paper,
      onTap: onTap,
    );
  }
}

/// "↑ 3 new decisions" on a capsule of [color], floating over the feed on a
/// soft shadow; the newspaper look's in ink, the wire look's in its blue.
class NewsPill extends StatelessWidget {
  const NewsPill({
    super.key,
    required this.label,
    required this.color,
    required this.onColor,
    required this.onTap,
  });

  final String label;
  final Color color;
  final Color onColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
          BoxShadow(
            color: Color(0x47000000),
            blurRadius: 24,
            spreadRadius: -8,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.arrow_up, size: 15, color: onColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: onColor,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ],
      ),
    ),
  );
}

/// One decision: where it comes from and its official-source mark, the
/// serif headline, when and its topics; its picture small on the right.
class _Row extends StatelessWidget {
  const _Row({
    required this.article,
    required this.mark,
    required this.topics,
    required this.onTap,
  });

  final Article article;

  /// Opened or not, and how that shows ([ReadStyle]): fainter in Dim, or the
  /// unread dot between the country and the institution in the dot styles.
  final ReadMark mark;

  /// The topic tags, in order ([FeedList.topicsOf]).
  final List<String> topics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final paper = _Paper.of(context);
    final l10n = AppLocalizations.of(context);
    final read = mark.dimmed;
    final time = feedTime(article, l10n);
    final url = article.imageUrl;
    final grey = Theme.of(context).colorScheme.onSurfaceVariant;
    final source = dim(paper.source, read);
    final timeText = ZoomPart(
      id: article.id,
      piece: ZoomPiece.time,
      child: !read && isFresh(article)
          ? FreshTime(
              time,
              articleId: article.id,
              style: paper.meta.copyWith(
                color: paper.accent,
                fontWeight: FontWeight.w600,
              ),
            )
          : Text(time, style: paper.meta),
    );
    return Semantics(
      container: true,
      button: true,
      label: _spoken(context, article, topics),
      value: mark.unread ? l10n.feedUnread : null,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: ZoomPart(
                            id: article.id,
                            piece: ZoomPiece.publisher,
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: countryName(article.country, l10n),
                                    style: source,
                                  ),
                                  // In the dot styles the unread dot stands
                                  // between the two, a small grey dot once
                                  // read, so the institution never moves.
                                  if (mark.dots)
                                    unreadDotSpan(
                                      context,
                                      mark,
                                      fontSize: paper.source.fontSize!,
                                      scaler: MediaQuery.textScalerOf(context),
                                      separator: grey,
                                    )
                                  else
                                    TextSpan(text: ' · ', style: source),
                                  TextSpan(
                                    text: article.source.name,
                                    style: source,
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        // The dot takes the official-source mark's place.
                        if (!mark.dots) ...[
                          const SizedBox(width: 4),
                          Icon(
                            CupertinoIcons.checkmark_seal_fill,
                            size: 13,
                            color: paper.accent,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    ZoomPart(
                      id: article.id,
                      piece: ZoomPiece.headline,
                      child: Text(
                        article.headline,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: dim(paper.headline(context), read),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // The time leads the footer, the topics after it, as in
                    // Cards (B): grey, faded once read in Dim.
                    if (topics.isEmpty)
                      timeText
                    else
                      TopicTags(
                        topics,
                        color: dim(TextStyle(color: grey), read).color!,
                        leading: timeText,
                      ),
                  ],
                ),
              ),
              if (url != null) ...[
                const SizedBox(width: 12),
                FeedPicture(
                  url: url,
                  width: 72,
                  height: 72,
                  radius: 3,
                  dimmed: read,
                  articleId: article.id,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// What VoiceOver reads for a row, once: the headline first, then where it
/// comes from, its topics and when ("Unread" is the row's value).
String _spoken(BuildContext context, Article a, List<String> topics) {
  final l10n = AppLocalizations.of(context);
  // One sentence each; a text that already ends in a full stop keeps one.
  String sentence(String s) => RegExp(r'[.!?…]$').hasMatch(s) ? s : '$s.';
  return [
    a.headline,
    '${countryName(a.country, l10n)}, ${a.source.name}',
    ?spokenTopics(topics, l10n),
    feedTime(a, l10n),
  ].map(sentence).join(' ');
}

/// The newspaper look's colours and type, light or dark.
class _Paper {
  _Paper._(this.dark)
    : paper = dark ? const Color(0xFF121212) : const Color(0xFFFFFFFF),
      ink = dark ? const Color(0xFFF0F0F0) : const Color(0xFF121212),
      muted = dark ? const Color(0xFFA3A3A3) : const Color(0xFF5F5F5F),
      rule = dark ? const Color(0xFF2C2C2C) : const Color(0xFFE2E2E2),
      accent = dark ? const Color(0xFF7FB0E6) : const Color(0xFF1F5C99);

  factory _Paper.of(BuildContext context) =>
      _Paper._(Theme.of(context).brightness == Brightness.dark);

  final bool dark;
  final Color paper;
  final Color ink;
  final Color muted;

  /// The hairlines between rows and under the tabs.
  final Color rule;

  /// A dark blue, the look's one colour.
  final Color accent;

  TextStyle get nameplate => TextStyle(
    fontFamily: 'Georgia',
    fontFamilyFallback: const ['serif'],
    fontSize: 30,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.15,
    color: ink,
  );

  TextStyle get dateline => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
    color: muted,
  );

  TextStyle get source =>
      TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ink);

  /// The app's serif headline at the row's size, in the weight chosen in
  /// Settings.
  TextStyle headline(BuildContext context) => NewsText.from(
    context,
  ).headline.copyWith(fontSize: 18, height: 1.25, color: ink);

  TextStyle get meta => TextStyle(fontSize: 13, color: muted);
}
