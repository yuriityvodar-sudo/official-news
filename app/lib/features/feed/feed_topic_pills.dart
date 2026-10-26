import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';

import '../../core/filters.dart';
import '../../core/topics.dart';
import '../../l10n/app_localizations.dart';

/// The topics as a row of pills you swipe sideways (Roman, 26 Oct), as Apple
/// News shows its sections: "All topics" first, then each topic with its
/// icon, busiest first. Each pill is Liquid Glass (Roman's pick 2 of the
/// mockup `handoff/glass-row-and-pull.html`): the feed shows through it,
/// blurred, under a tint of [fill]; the chosen one is glass in the look's
/// colour, glowing. [leading] goes before them: the Where pull-down, so a
/// country can still be chosen and cleared.
class TopicPills extends StatelessWidget {
  const TopicPills({
    super.key,
    required this.topic,
    required this.topics,
    required this.onTopic,
    required this.ink,
    required this.fill,
    required this.edge,
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

  /// A pill's words, the tint of its glass and its edge, and its shadow.
  final Color ink;
  final Color fill;
  final Color edge;
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
                edge: edge,
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
    required this.edge,
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
  final Color edge;
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
            // The shadow outside the glass, the blur inside its round edge.
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: _round,
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
              child: ClipRRect(
                borderRadius: _round,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isChosen ? null : fill.withValues(alpha: 0.58),
                      gradient: isChosen ? _glassy(chosen) : null,
                      borderRadius: _round,
                      border: Border.all(color: edge),
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
          ),
        ),
      ),
    );
  }
}

const _round = BorderRadius.all(Radius.circular(20));

/// The chosen pill's gradient, a little see-through: coloured glass.
Gradient _glassy(Gradient gradient) => gradient is LinearGradient
    ? LinearGradient(
        begin: gradient.begin,
        end: gradient.end,
        colors: [
          for (final c in gradient.colors) c.withValues(alpha: c.a * 0.88),
        ],
      )
    : gradient;
