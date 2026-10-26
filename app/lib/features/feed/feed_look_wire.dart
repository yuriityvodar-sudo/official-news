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
import 'feed_look_paper.dart';
import 'feed_topic_tags.dart';
import 'feed_touches.dart';

/// Design «Wire» (Roman, 26 Oct), after Reuters and government sites such
/// as GOV.UK: a dark-blue band at the top with the name and the topics as
/// tabs ([TopicTabs]), under it a light grey page with each decision on a
/// white card (dark ones in dark mode), sans-serif headlines, and one blue
/// for the official-source mark, a decision of the last hour, the topic tag
/// and the "N new" pill. Every card alike, as in every look (Yurii, 16 Oct).
class WireLook extends FeedLook {
  @override
  Color background(BuildContext context) => _Wire.of(context).page;

  @override
  Color? topInset(BuildContext context) => _Wire.of(context).band;

  @override
  Widget masthead(BuildContext context, FeedMasthead masthead) {
    final wire = _Wire.of(context);
    final cupertino = CupertinoTheme.of(context);
    // The band is dark in both modes: its system pieces (the settings
    // button, the Where chip) are drawn as on a dark screen.
    Widget onBand(Widget child) => CupertinoTheme(
      data: cupertino.copyWith(brightness: Brightness.dark),
      child: child,
    );
    return SliverToBoxAdapter(
      child: ColoredBox(
        color: wire.band,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: wire.accent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      CupertinoIcons.building_2_fill,
                      size: 15,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      masthead.title,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        color: Color(0xFFFFFFFF),
                      ),
                    ),
                  ),
                  onBand(masthead.settingsButton),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                masthead.date,
                style: TextStyle(fontSize: 13, color: wire.bandMuted),
              ),
            ),
            onBand(
              TopicTabs(
                topic: masthead.topic,
                topics: masthead.topics,
                onTopic: masthead.onTopic,
                color: wire.bandMuted,
                chosenColor: const Color(0xFFFFFFFF),
                mark: wire.accent,
                markHeight: 3,
                leading: masthead.whereChip,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget articles(BuildContext context, FeedList list) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
    sliver: SliverList.builder(
      itemCount: list.length,
      itemBuilder: (context, i) {
        final a = list.articles[i];
        list.shown(i);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: list.tile(
            i,
            _Card(
              article: a,
              mark: list.markOf(a),
              topics: list.topicsOf(a),
              onTap: () => list.open(i),
            ),
          ),
        );
      },
    ),
  );

  @override
  Widget feedEnd(BuildContext context, FeedEnd end) {
    final wire = _Wire.of(context);
    final l10n = AppLocalizations.of(context);
    final meta = TextStyle(fontSize: 13, color: wire.muted);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
      sliver: SliverToBoxAdapter(
        child: Center(
          child: switch (end.state) {
            FeedEndState.failed => CupertinoButton(
              onPressed: end.retry,
              child: Text(
                l10n.feedLoadMoreFailed,
                textAlign: TextAlign.center,
                style: meta.copyWith(color: wire.accent),
              ),
            ),
            FeedEndState.loading => const CupertinoActivityIndicator(),
            FeedEndState.end => Text(l10n.feedEnd, style: meta),
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
  }) => NewsPill(
    label: AppLocalizations.of(context).newDecisions(count),
    color: _Wire.of(context).accent,
    onColor: const Color(0xFFFFFFFF),
    onTap: onTap,
  );
}

/// One decision on a white card: who published it and its mark, the
/// headline, when and its first topic as a blue tag; its picture small on
/// the right.
class _Card extends StatelessWidget {
  const _Card({
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
    final wire = _Wire.of(context);
    final l10n = AppLocalizations.of(context);
    final read = mark.dimmed;
    final time = feedTime(article, l10n);
    final url = article.imageUrl;
    final meta = TextStyle(fontSize: 13, color: wire.muted);
    final grey = Theme.of(context).colorScheme.onSurfaceVariant;
    final source = dim(
      TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: wire.muted),
      read,
    );
    final timeText = ZoomPart(
      id: article.id,
      piece: ZoomPiece.time,
      child: !read && isFresh(article)
          ? FreshTime(
              time,
              articleId: article.id,
              style: meta.copyWith(
                color: wire.accent,
                fontWeight: FontWeight.w600,
              ),
            )
          : Text(time, style: meta),
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
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: wire.card,
            border: Border.all(color: wire.line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(13),
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
                                        fontSize: source.fontSize!,
                                        scaler: MediaQuery.textScalerOf(
                                          context,
                                        ),
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
                              color: wire.accent,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),
                      ZoomPart(
                        id: article.id,
                        piece: ZoomPiece.headline,
                        child: Text(
                          article.headline,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: dim(
                            TextStyle(
                              fontSize: 17,
                              // The weight chosen in Settings.
                              fontWeight: NewsText.from(
                                context,
                              ).headline.fontWeight,
                              height: 1.25,
                              letterSpacing: -0.2,
                              color: wire.ink,
                            ),
                            read,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // The time leads the footer, the topics after it, as
                      // in Cards (B): grey, faded once read in Dim.
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
                    radius: 6,
                    dimmed: read,
                    articleId: article.id,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What VoiceOver reads for a card, once: the headline first, then where it
/// comes from, its topics and when ("Unread" is the card's value).
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

/// The wire look's colours, light or dark.
class _Wire {
  _Wire._(bool dark)
    : band = dark ? const Color(0xFF0A1724) : const Color(0xFF0B1F33),
      bandMuted = dark ? const Color(0xFF8496A8) : const Color(0xFF9FB0C2),
      page = dark ? const Color(0xFF0D1218) : const Color(0xFFF2F3F5),
      card = dark ? const Color(0xFF161D25) : const Color(0xFFFFFFFF),
      line = dark ? const Color(0xFF243039) : const Color(0xFFE1E4E8),
      ink = dark ? const Color(0xFFEEF2F6) : const Color(0xFF14181D),
      muted = dark ? const Color(0xFF97A3AF) : const Color(0xFF5E6670),
      accent = dark ? const Color(0xFF5AA9E6) : const Color(0xFF1D70B8);

  factory _Wire.of(BuildContext context) =>
      _Wire._(Theme.of(context).brightness == Brightness.dark);

  /// The dark-blue band at the top, and its grey words.
  final Color band;
  final Color bandMuted;

  /// The page under the cards, and the cards.
  final Color page;
  final Color card;
  final Color line;
  final Color ink;
  final Color muted;

  /// The look's one blue.
  final Color accent;
}
