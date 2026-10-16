import 'package:flutter/cupertino.dart';

import '../../core/article.dart';
import '../../l10n/app_localizations.dart';
import 'feed_filters.dart';

/// PROTOTYPE (Yurii, 16 Oct): the feed's cards show their topics instead of
/// their decision type ("Bill", "ЗАКОНОПРОЄКТ"), which stays on the article
/// screen. Each topic is a small grey tag with the icon and the name the
/// Topics filter shows ([topicIcon], [topicName]): one source for both, so a
/// card and the filter never name a topic differently. Every look uses these
/// tags, each in the place its decision type had.

/// The most topic tags a card shows: the AI gives an article 1 to 3 topics
/// (docs/contract.md). The prototype can show fewer ([FeedList.maxTopics]).
const maxCardTopics = 3;

/// The topics [article]'s card shows, in order: [first] (the topic the feed
/// is filtered by) when the article has it, then the article's own topics in
/// its order, each once, at most [max]. Empty for an article without topics.
List<String> cardTopics(
  Article article, {
  String? first,
  int max = maxCardTopics,
}) => <String>{
  if (first != null && article.topics.contains(first)) first,
  for (final id in article.topics)
    if (id.trim().isNotEmpty) id,
}.take(max).toList();

/// What VoiceOver says for the tags of [ids]: "Topics: Economy, Trade",
/// "Тема: Економіка"; null for none.
String? spokenTopics(List<String> ids, AppLocalizations l10n) => ids.isEmpty
    ? null
    : l10n.feedCardTopics(
        ids.length,
        [for (final id in ids) topicName(id, l10n)].join(', '),
      );

/// The topic tags of a card, on one line when they fit and on more when they
/// do not, a whole tag at a time; a tag wider than the whole line (only at
/// the largest text sizes) wraps its own name between words. A name is never
/// cut with "…" and never broken inside a word: when a word would not fit
/// even on a line of its own, the tags' text is made a little smaller.
///
/// Nothing at all for no topics (no empty row): a look leaves out the gap
/// above it too. [trailing] (the time, in looks that have it after the
/// decision type) follows the last tag on the same line, or starts the next.
///
/// VoiceOver hears the tags once, as "Topics: Economy, Trade"
/// ([spokenTopics]); looks whose card has one label of its own put that in
/// it.
class TopicTags extends StatelessWidget {
  const TopicTags(
    this.ids, {
    super.key,
    required this.color,
    this.fill,
    this.trailing,
    this.maxScale = 2,
  });

  /// The topics, in the order shown ([cardTopics]).
  final List<String> ids;

  /// The text and icon colour: the look's secondary grey, faded as the look
  /// fades grey text on a read card. Never red: the tags are secondary.
  final Color color;

  /// The tag's light fill; iOS's quaternary fill when not given (on white,
  /// #6C6C70 text on it is 4.7:1; in dark, #98989F on it is 6.4:1 on black
  /// and 4.7:1 on a dark grey card).
  final Color? fill;

  /// What follows the tags on their line: in A and B the time.
  final Widget? trailing;

  /// How far the tags grow with the reader's text size: they are labels, so
  /// at most twice their size (24 pt).
  final double maxScale;

  static const fontSize = 12.0;
  static const _lineHeight = 1.25;
  static const _padH = 5.0;
  static const _padV = 2.0;
  static const _gap = 3.0;

  /// Between two tags, and between the last one and [trailing].
  static const spacing = 5.0;

  /// Between two lines of tags.
  static const runSpacing = 4.0;

  @override
  Widget build(BuildContext context) {
    if (ids.isEmpty) return trailing ?? const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final names = [for (final id in ids) topicName(id, l10n)];
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      height: _lineHeight,
      color: color,
    );
    final background =
        fill ?? CupertinoColors.quaternarySystemFill.resolveFrom(context);
    final scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: maxScale);
    return LayoutBuilder(
      builder: (context, constraints) {
        final fitted = _fitWords(
          context,
          scaler,
          constraints.maxWidth,
          style,
          names,
        );
        final tags = <Widget>[
          for (final (i, id) in ids.indexed)
            TopicTag(
              id: id,
              name: names[i],
              style: style,
              scaler: fitted,
              fill: background,
            ),
        ];
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // One VoiceOver phrase for all the tags, on the first.
            Semantics(
              label: spokenTopics(ids, l10n),
              child: ExcludeSemantics(child: tags.first),
            ),
            for (final tag in tags.skip(1)) ExcludeSemantics(child: tag),
            ?trailing,
          ],
        );
      },
    );
  }

  /// [scaler], made smaller for these tags only if a word of [names] would
  /// not fit beside its icon in a tag as wide as [width]: Flutter would break
  /// such a word between two letters. Measured in the font that draws it,
  /// bold when iOS Bold Text is on (Text draws it so).
  static TextScaler _fitWords(
    BuildContext context,
    TextScaler scaler,
    double width,
    TextStyle style,
    List<String> names,
  ) {
    if (!width.isFinite || width <= 0) return scaler;
    var drawn = DefaultTextStyle.of(context).style.merge(style);
    if (MediaQuery.boldTextOf(context)) {
      drawn = drawn.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final words = [
      for (final name in names) ...name.trim().split(RegExp(r'\s+')),
    ];
    final painter = TextPainter(
      text: TextSpan(text: words.join('\n'), style: drawn),
      textDirection: Directionality.of(context),
    );
    var fitted = scaler;
    try {
      for (var tries = 0; tries < 4; tries++) {
        painter
          ..textScaler = fitted
          ..layout();
        final size = fitted.scale(fontSize);
        // The padding and the icon take their room beside the name.
        final room = width - 2 * _padH - size - _gap - 0.5;
        final widest = painter.maxIntrinsicWidth;
        if (widest <= room || room <= 0) break;
        fitted = scaler.clamp(maxScaleFactor: size / fontSize * room / widest);
      }
    } finally {
      painter.dispose();
    }
    return fitted;
  }
}

/// One topic: its icon ([topicIcon]) and name on a light fill with soft
/// corners (the filter chips are round pills: these are labels, not
/// buttons). Built by [TopicTags].
class TopicTag extends StatelessWidget {
  const TopicTag({
    super.key,
    required this.id,
    required this.name,
    required this.style,
    required this.scaler,
    required this.fill,
  });

  /// The topic's id, as [Article.topics] has it.
  final String id;

  /// Its name in the app's language ([topicName]).
  final String name;
  final TextStyle style;
  final TextScaler scaler;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    final size = scaler.scale(TopicTags.fontSize);
    final line = size * TopicTags._lineHeight;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: fill,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TopicTags._padH,
          vertical: TopicTags._padV,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Level with the name's first line, also when it takes two.
            Padding(
              padding: EdgeInsets.only(top: (line - size) / 2),
              child: Icon(topicIcon(id), size: size, color: style.color),
            ),
            const SizedBox(width: TopicTags._gap),
            Flexible(
              child: Text(name, style: style, textScaler: scaler),
            ),
          ],
        ),
      ),
    );
  }
}
