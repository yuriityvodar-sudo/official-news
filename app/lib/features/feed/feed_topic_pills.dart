import 'package:flutter/cupertino.dart';

import '../../core/filters.dart';
import '../../core/topics.dart';
import '../../l10n/app_localizations.dart';

/// The topics as a row of pills you swipe sideways (Roman, 26 Oct), as Apple
/// News shows its sections: "All topics" first, then each topic with its
/// icon, busiest first; the chosen one filled with the look's colour, the
/// others on [fill] with a soft [shadow]. [leading] goes before them: the
/// Where pull-down, so a country can still be chosen and cleared.
class TopicPills extends StatelessWidget {
  const TopicPills({
    super.key,
    required this.topic,
    required this.topics,
    required this.onTopic,
    required this.ink,
    required this.fill,
    required this.shadow,
    required this.chosen,
    required this.glow,
    this.leading,
  });

  /// The chosen topic's id, or null for all topics.
  final String? topic;

  /// The topics to offer, busiest first; null while none are known.
  final List<FeedTopic>? topics;
  final ValueChanged<String?> onTopic;

  /// A pill's words and its colour, and its shadow.
  final Color ink;
  final Color fill;
  final List<BoxShadow> shadow;

  /// The chosen pill's fill, and the glow under it.
  final Gradient chosen;
  final Color glow;

  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final menu = topics ?? const <FeedTopic>[];
    final current = topic;
    final pills = <(String?, String, IconData)>[
      (null, l10n.filterAllTopics, CupertinoIcons.sparkles),
      for (final t in menu)
        (
          t.id,
          topicName(t.id, menu, l10n),
          topicIcons[t.id] ?? CupertinoIcons.tag,
        ),
      // A topic chosen before it left the menu, so it can be cleared.
      if (current != null && !menu.any((t) => t.id == current))
        (
          current,
          topicName(current, menu, l10n),
          topicIcons[current] ?? CupertinoIcons.tag,
        ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          if (leading != null)
            Padding(padding: const EdgeInsets.only(right: 8), child: leading),
          for (final (id, name, icon) in pills)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _Pill(
                key: ValueKey('topic-pill-${id ?? 'all'}'),
                name: name,
                icon: icon,
                isChosen: id == current,
                ink: ink,
                fill: fill,
                shadow: shadow,
                chosen: chosen,
                glow: glow,
                onTap: () => onTopic(id),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.name,
    required this.icon,
    required this.isChosen,
    required this.ink,
    required this.fill,
    required this.shadow,
    required this.chosen,
    required this.glow,
    required this.onTap,
  });

  final String name;
  final IconData icon;
  final bool isChosen;
  final Color ink;
  final Color fill;
  final List<BoxShadow> shadow;
  final Gradient chosen;
  final Color glow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isChosen ? const Color(0xFFFFFFFF) : ink;
    return Semantics(
      button: true,
      selected: isChosen,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isChosen ? null : fill,
                gradient: isChosen ? chosen : null,
                borderRadius: BorderRadius.circular(20),
                boxShadow: isChosen
                    ? [
                        BoxShadow(
                          color: glow,
                          blurRadius: 16,
                          spreadRadius: -4,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : shadow,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: color,
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
