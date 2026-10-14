import 'package:flutter/cupertino.dart';

import 'article.dart';
import 'decision_types.dart';
import 'theme.dart';

/// The red decision type above a headline ("CABINET DECISION"); nothing when
/// the article has no known type yet.
class KindLabel extends StatelessWidget {
  const KindLabel(this.article, {super.key});

  final Article article;

  @override
  Widget build(BuildContext context) {
    final label = decisionTypeLabel(article.decisionType);
    if (label == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(label.toUpperCase(), style: NewsText.from(context).kindLabel),
    );
  }
}

/// "Federal Government · DE" with the blue official-source mark.
class PublisherLine extends StatelessWidget {
  const PublisherLine(this.article, {super.key});

  final Article article;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            '${article.source.name} · ${article.country}',
            style: NewsText.from(context).publisher,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        const Icon(
          CupertinoIcons.checkmark_seal,
          size: 15,
          color: AppColors.verified,
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
