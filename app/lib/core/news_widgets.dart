import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import 'article.dart';
import 'countries.dart';
import 'decision_types.dart';
import 'read_mark.dart';
import 'theme.dart';

/// The red decision type above the article screen's headline ("CABINET
/// DECISION", "РІШЕННЯ УРЯДУ"); nothing when the article has no known type
/// yet. The feed's cards show the article's topics instead (Yurii, 16 Oct:
/// the type stays inside the article).
class KindLabel extends StatelessWidget {
  const KindLabel(this.article, {super.key});

  final Article article;

  @override
  Widget build(BuildContext context) {
    final label = decisionTypeLabel(
      article.decisionType,
      AppLocalizations.of(context),
    );
    if (label == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(label.toUpperCase(), style: NewsText.from(context).kindLabel),
    );
  }
}

/// How much of its colour a read article keeps.
const readOpacity = 0.55;

/// A style faded for an article already read; cheaper than an Opacity layer per row.
TextStyle dim(TextStyle style, bool dimmed) => dimmed && style.color != null
    ? style.copyWith(
        color: style.color!.withValues(alpha: style.color!.a * readOpacity),
      )
    : style;

/// "Federal Government · Germany" with the blue official-source mark, or,
/// in the prototype's dot styles ([mark]), the unread dot in its place.
class PublisherLine extends StatelessWidget {
  const PublisherLine(
    this.article, {
    super.key,
    this.dimmed = false,
    this.mark,
  });

  final Article article;
  final bool dimmed;

  /// How read articles look (#66); null, None or Dim shows the mark as today.
  final ReadMark? mark;

  @override
  Widget build(BuildContext context) {
    final country = countryName(article.country, AppLocalizations.of(context));
    final style = dim(NewsText.from(context).publisher, dimmed);
    final dots = mark?.dots ?? false;
    return Row(
      children: [
        Flexible(
          child: Text(
            '${article.source.name} · $country',
            style: style,
            overflow: TextOverflow.ellipsis,
            // A line cut with "…" is as wide as its last letter, not as the
            // room it was given, so the dot stays 5 pt after the "…". Dim
            // keeps today's tick where it was.
            textWidthBasis: dots
                ? TextWidthBasis.longestLine
                : TextWidthBasis.parent,
          ),
        ),
        if (dots)
          UnreadDot(mark!, fontSize: style.fontSize!)
        else ...[
          const SizedBox(width: 4),
          Icon(
            CupertinoIcons.checkmark_seal,
            size: 15,
            color: dimmed
                ? AppColors.verified.withValues(alpha: readOpacity)
                : AppColors.verified,
          ),
        ],
      ],
    );
  }
}

/// The locale of the app's dates in the language of [l10n] (#52). English
/// dates stay British, the day before the month, as in the design
/// (docs/design/mvp.png): "14 October 2026".
String _dates(AppLocalizations l10n) =>
    l10n.localeName == 'en' ? 'en_GB' : l10n.localeName;

/// A date that starts a line, with a capital: Ukrainian, Russian and Spanish
/// write weekdays in lower case ("пʼятниця, 16 жовтня").
String _capitalized(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

/// The feed's date line: "Wednesday, 14 October", "Середа, 14 жовтня",
/// "Mittwoch, 14. Oktober". English keeps the design's comma.
String longDay(DateTime date, AppLocalizations l10n) {
  final format = l10n.localeName == 'en'
      ? DateFormat('EEEE, d MMMM', 'en_GB')
      : DateFormat.MMMMEEEEd(_dates(l10n));
  return _capitalized(format.format(date.toLocal()));
}

/// "14 October 2026", "14 жовтня 2026 р.", "14 de octubre de 2026".
String fullDate(DateTime date, AppLocalizations l10n) =>
    DateFormat.yMMMMd(_dates(l10n)).format(date.toLocal());

/// "11:30": the 24-hour clock, as every language the app has writes it.
String clockTime(DateTime date, AppLocalizations l10n) =>
    DateFormat.Hm(_dates(l10n)).format(date.toLocal());

/// "5m ago", "2h ago", "3d ago"; "5 хв тому", "3 дні тому".
String timeAgo(DateTime date, AppLocalizations l10n, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(date);
  if (diff.inMinutes < 60) return l10n.minutesAgo(diff.inMinutes.clamp(1, 59));
  if (diff.inHours < 24) return l10n.hoursAgo(diff.inHours);
  return l10n.daysAgo(diff.inDays);
}

/// The local calendar day, for grouping the feed.
DateTime localDay(DateTime date) {
  final d = date.toLocal();
  return DateTime(d.year, d.month, d.day);
}

/// "Today", "Yesterday", or "Monday 12 October" ("Понеділок, 12 жовтня").
String dayLabel(DateTime date, AppLocalizations l10n, {DateTime? now}) {
  final day = localDay(date);
  final today = localDay(now ?? DateTime.now());
  // Compared as UTC dates: local midnights are 23 or 25 hours apart on a clock change.
  final days = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(day.year, day.month, day.day)).inDays;
  if (days == 0) return l10n.today;
  if (days == 1) return l10n.yesterday;
  return _capitalized(DateFormat.MMMMEEEEd(_dates(l10n)).format(day));
}

/// "2h ago" for articles with a time; the day for those whose source gave only a date.
/// The time on a feed card: when the article appeared in the feed ("5m ago"),
/// the same moment the feed is ordered by, so times only go down as you scroll.
/// The official publication date is on the article screen. Before the server
/// sends `addedAt`, the publication time.
String feedTime(Article article, AppLocalizations l10n, {DateTime? now}) =>
    article.addedAt != null
    ? timeAgo(article.addedAt!, l10n, now: now)
    : articleTime(article, l10n, now: now);

String articleTime(Article article, AppLocalizations l10n, {DateTime? now}) =>
    article.dateOnly
    ? dayLabel(article.publishedAt, l10n, now: now)
    : timeAgo(article.publishedAt, l10n, now: now);
