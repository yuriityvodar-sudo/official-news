import 'dart:ui' show ImageFilter;

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

/// The two looks after Apple News that Roman picked (26 Oct), in our own
/// colours ([NewsPalette]): a light grey page, a large title with a seal in
/// the colour's gradient and the date in grey, and every decision on a white
/// card with a soft shadow of the colour, its picture on the right. Liquid
/// Glass for the "N new" pill. A card grows into its article when opened
/// (#141). Every card alike, as in every look (Yurii, 16 Oct): no bigger
/// first story yet.
class NewsLook extends FeedLook {
  NewsLook(this.palette);

  final NewsPalette palette;

  @override
  Color background(BuildContext context) =>
      _NewsStyle.of(context, palette).page;

  @override
  Color cardColor(BuildContext context) => _NewsStyle.of(context, palette).card;

  @override
  double get cardRadius => _NewsStyle.radius;

  @override
  Widget masthead(BuildContext context, FeedMasthead masthead) {
    final style = _NewsStyle.of(context, palette);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _Seal(style: style),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              masthead.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: style.title,
                            ),
                          ),
                        ],
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          masthead.date,
                          maxLines: 1,
                          style: style.title.copyWith(
                            fontSize: 26,
                            color: style.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                masthead.settingsButton,
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: masthead.filterBar,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget articles(BuildContext context, FeedList list) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
    sliver: SliverList.builder(
      itemCount: list.length,
      itemBuilder: (context, i) {
        final a = list.articles[i];
        list.shown(i);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: list.tile(
            i,
            _Card(
              palette: palette,
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
    final style = _NewsStyle.of(context, palette);
    final l10n = AppLocalizations.of(context);
    final meta = TextStyle(fontSize: 15, color: style.muted);
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
                style: meta.copyWith(color: style.accent),
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
  }) {
    final style = _NewsStyle.of(context, palette);
    // Liquid Glass: the feed shows through, blurred, under a tint of the card.
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: const Color(0x24000000),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: style.card.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: style.glassEdge),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.arrow_up, size: 15, color: style.accent),
                  const SizedBox(width: 6),
                  Text(
                    AppLocalizations.of(context).newDecisions(count),
                    style: TextStyle(
                      color: style.accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The two colours of [NewsLook]: garnet, a red of our own, deeper than
/// Apple's; and seal, the green of an official seal.
enum NewsPalette { garnet, seal }

/// The official-source seal before the app's name, in the colour's
/// gradient on a soft glow.
class _Seal extends StatelessWidget {
  const _Seal({required this.style});

  final _NewsStyle style;

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    decoration: BoxDecoration(
      gradient: style.gradient,
      borderRadius: BorderRadius.circular(9),
      boxShadow: [
        BoxShadow(
          color: style.glow,
          blurRadius: 14,
          spreadRadius: -2,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: const Icon(
      CupertinoIcons.checkmark_seal_fill,
      size: 18,
      color: Color(0xFFFFFFFF),
    ),
  );
}

/// One decision on a white card: where it comes from with the official
/// seal, the headline, when and its topics; its picture on the right.
/// Drawn as its article's top ([ZoomSource.isArticleTop]), it has no shadow:
/// the card has become the page.
class _Card extends StatelessWidget {
  const _Card({
    required this.palette,
    required this.article,
    required this.mark,
    required this.topics,
    required this.onTap,
  });

  final NewsPalette palette;
  final Article article;

  /// Opened or not, and how that shows ([ReadStyle]): fainter in Dim, or the
  /// unread dot between the country and the institution in the dot styles.
  final ReadMark mark;

  /// The topic tags, in order ([FeedList.topicsOf]).
  final List<String> topics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = _NewsStyle.of(context, palette);
    final l10n = AppLocalizations.of(context);
    final read = mark.dimmed;
    final time = feedTime(article, l10n);
    final url = article.imageUrl;
    final grey = Theme.of(context).colorScheme.onSurfaceVariant;
    final source = dim(style.source, read);
    final meta = TextStyle(fontSize: 14, color: style.muted);
    final timeText = !read && isFresh(article)
        ? FreshTime(
            time,
            articleId: article.id,
            style: meta.copyWith(fontWeight: FontWeight.w600),
            color: style.accent,
          )
        : Text(time, style: meta);
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
            color: style.card,
            borderRadius: BorderRadius.circular(_NewsStyle.radius),
            boxShadow: ZoomSource.isArticleTop(context)
                ? null
                : style.cardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              // The dot takes the official seal's place.
                              if (!mark.dots) ...[
                                Icon(
                                  CupertinoIcons.checkmark_seal_fill,
                                  size: 15,
                                  color: style.accent,
                                ),
                                const SizedBox(width: 5),
                              ],
                              Flexible(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: countryName(
                                          article.country,
                                          l10n,
                                        ),
                                        style: source,
                                      ),
                                      // In the dot styles the unread dot stands
                                      // between the two, a small grey dot once
                                      // read, so the institution never moves.
                                      if (mark.dots)
                                        unreadDotSpan(
                                          context,
                                          mark,
                                          fontSize: style.source.fontSize!,
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
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            article.headline,
                            style: dim(style.headline(context), read),
                          ),
                          const SizedBox(height: 8),
                          timeText,
                        ],
                      ),
                    ),
                    if (url != null) ...[
                      const SizedBox(width: 12),
                      FeedPicture(
                        url: url,
                        width: 92,
                        height: 92,
                        radius: 14,
                        dimmed: read,
                      ),
                    ],
                  ],
                ),
                // The topics last, across the whole card, under the picture
                // too: three long names take two lines at most. Grey, faded
                // once read in Dim.
                if (topics.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  TopicTags(
                    topics,
                    color: dim(TextStyle(color: grey), read).color!,
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

/// [NewsLook]'s colours and type, light or dark.
class _NewsStyle {
  _NewsStyle._(this.dark, this.accent, this.accent2)
    : page = dark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      card = dark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF),
      ink = dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
      muted = dark ? const Color(0xFF98989F) : const Color(0xFF8A8A8E);

  factory _NewsStyle.of(BuildContext context, NewsPalette palette) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (palette) {
      NewsPalette.garnet => _NewsStyle._(
        dark,
        dark ? const Color(0xFFFF5A72) : const Color(0xFFC41230),
        dark ? const Color(0xFFFF8A9C) : const Color(0xFFE4566E),
      ),
      NewsPalette.seal => _NewsStyle._(
        dark,
        dark ? const Color(0xFF3DD4A3) : const Color(0xFF0E7A5E),
        dark ? const Color(0xFF7BE6C2) : const Color(0xFF2DB88D),
      ),
    };
  }

  static const radius = 24.0;

  final bool dark;

  /// The look's colour, and the lighter end of its gradient.
  final Color accent;
  final Color accent2;

  final Color page;
  final Color card;
  final Color ink;
  final Color muted;

  LinearGradient get gradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accent2],
  );

  /// The glow under what is filled with the colour.
  Color get glow => accent.withValues(alpha: dark ? 0.35 : 0.3);

  /// The edge of Liquid Glass.
  Color get glassEdge =>
      dark ? const Color(0x24FFFFFF) : const Color(0x8CFFFFFF);

  /// A card's shadow: close and grey, then wide in a tint of the colour.
  List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: dark ? const Color(0x00000000) : const Color(0x0D000000),
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
    BoxShadow(
      color: accent.withValues(alpha: dark ? 0.16 : 0.18),
      blurRadius: 34,
      spreadRadius: -10,
      offset: const Offset(0, 16),
    ),
  ];

  TextStyle get title => TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    letterSpacing: -1,
    height: 1.08,
    color: ink,
  );

  TextStyle get source =>
      TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink);

  /// The headline, in the system's sans, in the weight chosen in Settings.
  TextStyle headline(BuildContext context) => TextStyle(
    fontSize: 18,
    height: 1.22,
    letterSpacing: -0.3,
    fontWeight: NewsText.from(context).headline.fontWeight,
    color: ink,
  );
}
