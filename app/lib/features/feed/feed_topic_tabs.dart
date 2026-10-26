import 'package:flutter/cupertino.dart';

import '../../core/filters.dart';
import '../../l10n/app_localizations.dart';

/// The topics as a row of tabs you swipe sideways (Roman, 26 Oct), as news
/// apps show their sections: "All topics" first, then each topic, busiest
/// first, the chosen one underlined. [leading] goes before the tabs: the
/// Where pull-down, so a country can still be chosen and cleared.
class TopicTabs extends StatelessWidget {
  const TopicTabs({
    super.key,
    required this.topic,
    required this.topics,
    required this.onTopic,
    required this.color,
    required this.chosenColor,
    required this.mark,
    this.markHeight = 2,
    this.leading,
  });

  /// The chosen topic's id, or null for all topics.
  final String? topic;

  /// The topics to offer, busiest first; null while none are known.
  final List<FeedTopic>? topics;
  final ValueChanged<String?> onTopic;

  /// A tab's words, and the chosen tab's.
  final Color color;
  final Color chosenColor;

  /// The line under the chosen tab, and how thick it is.
  final Color mark;
  final double markHeight;

  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final menu = topics ?? const <FeedTopic>[];
    final chosen = topic;
    final tabs = <(String?, String)>[
      (null, l10n.filterAllTopics),
      for (final t in menu) (t.id, topicName(t.id, menu, l10n)),
      // A topic chosen before it left the menu, so it can be cleared.
      if (chosen != null && !menu.any((t) => t.id == chosen))
        (chosen, topicName(chosen, menu, l10n)),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          if (leading != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 6),
              child: leading,
            ),
          for (final (id, name) in tabs)
            _Tab(
              key: ValueKey('topic-tab-${id ?? 'all'}'),
              name: name,
              chosen: id == chosen,
              color: id == chosen ? chosenColor : color,
              mark: mark,
              markHeight: markHeight,
              onTap: () => onTopic(id),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.name,
    required this.chosen,
    required this.color,
    required this.mark,
    required this.markHeight,
    required this.onTap,
  });

  final String name;
  final bool chosen;
  final Color color;
  final Color mark;
  final double markHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: chosen,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          // The line as wide as the words.
          child: IntrinsicWidth(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 8),
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: markHeight,
                  color: chosen ? mark : const Color(0x00000000),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
