import 'package:flutter/cupertino.dart';

import 'article.dart';
import 'countries.dart';
import 'decision_types.dart';
import 'theme.dart';

/// The red decision type above a headline ("CABINET DECISION"); nothing when
/// the article has no known type yet.
class KindLabel extends StatelessWidget {
  const KindLabel(this.article, {super.key, this.dimmed = false});

  final Article article;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final label = decisionTypeLabel(article.decisionType);
    if (label == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label.toUpperCase(),
        style: dim(NewsText.from(context).kindLabel, dimmed),
      ),
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

/// "Federal Government · Germany" with the blue official-source mark.
class PublisherLine extends StatelessWidget {
  const PublisherLine(this.article, {super.key, this.dimmed = false});

  final Article article;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            '${article.source.name} · ${countryName(article.country)}',
            style: dim(NewsText.from(context).publisher, dimmed),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        Icon(
          CupertinoIcons.checkmark_seal,
          size: 15,
          color: dimmed
              ? AppColors.verified.withValues(alpha: readOpacity)
              : AppColors.verified,
        ),
      ],
    );
  }
}

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "Wednesday, 14 October".
String longDay(DateTime date) {
  final d = date.toLocal();
  return '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
}

/// "14 October 2026".
String fullDate(DateTime date) {
  final d = date.toLocal();
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// "5m ago", "2h ago", "3d ago".
String timeAgo(DateTime date, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(date);
  if (diff.inMinutes < 60) return '${diff.inMinutes.clamp(1, 59)}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// The local calendar day, for grouping the feed.
DateTime localDay(DateTime date) {
  final d = date.toLocal();
  return DateTime(d.year, d.month, d.day);
}

/// "Today", "Yesterday", or "Monday 12 October".
String dayLabel(DateTime date, {DateTime? now}) {
  final day = localDay(date);
  final today = localDay(now ?? DateTime.now());
  // Compared as UTC dates: local midnights are 23 or 25 hours apart on a clock change.
  final days = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(day.year, day.month, day.day)).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  return '${_weekdays[day.weekday - 1]} ${day.day} ${_months[day.month - 1]}';
}

/// "2h ago" for articles with a time; the day for those whose source gave only a date.
String articleTime(Article article, {DateTime? now}) => article.dateOnly
    ? dayLabel(article.publishedAt, now: now)
    : timeAgo(article.publishedAt, now: now);
