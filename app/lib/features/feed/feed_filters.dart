import 'package:flutter/cupertino.dart';

import '../../core/filters.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';

/// The two pull-downs under the date (#67, #68), as in the prototype Yurii saw
/// on the simulator: Where (Global, or Local with the reader's country) and
/// Topics (all, or one). Rounded chips, red while they narrow the feed, each
/// opening an iOS pull-down menu with a checkmark on the current choice. No
/// counts in the menus; the topics come busiest first from the server.
class FeedFilterBar extends StatelessWidget {
  const FeedFilterBar({
    super.key,
    required this.scope,
    required this.localName,
    required this.topic,
    required this.topics,
    required this.onScope,
    required this.onTopic,
  });

  final FeedScope scope;

  /// Local's country in the app's language; null hides the Where chip (no
  /// country to offer, so Global is all there is).
  final String? localName;

  /// The chosen topic's id, or null for all topics.
  final String? topic;

  /// The Topics menu, busiest first; null hides the Topics chip (a server
  /// without topics) unless a topic is chosen, so it can always be cleared.
  final List<FeedTopic>? topics;

  final ValueChanged<FeedScope> onScope;
  final ValueChanged<String?> onTopic;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final local = localName;
    final menu = topics;
    final chosen = topic;
    final showTopics = menu != null || chosen != null;
    String name(String id) => topicName(id, menu, l10n);
    if (local == null && !showTopics) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (local != null)
            _Pulldown(
              key: const ValueKey('filter-where'),
              icon: scope == FeedScope.local
                  ? CupertinoIcons.location_solid
                  : CupertinoIcons.globe,
              label: scope == FeedScope.local ? local : l10n.filterGlobal,
              active: scope == FeedScope.local,
              items: [
                _Item(
                  l10n.filterGlobal,
                  l10n.filterGlobalDetail,
                  scope == FeedScope.global,
                  () => onScope(FeedScope.global),
                ),
                _Item(
                  l10n.filterLocal,
                  local,
                  scope == FeedScope.local,
                  () => onScope(FeedScope.local),
                ),
              ],
            ),
          if (showTopics)
            _Pulldown(
              key: const ValueKey('filter-topic'),
              icon: CupertinoIcons.square_grid_2x2,
              label: chosen == null ? l10n.filterAllTopics : name(chosen),
              active: chosen != null,
              items: [
                _Item(
                  l10n.filterAllTopics,
                  null,
                  chosen == null,
                  () => onTopic(null),
                ),
                // The chosen topic stays in the menu, checked, when it has no
                // articles under the other filter now.
                if (chosen != null && !(menu ?? []).any((t) => t.id == chosen))
                  _Item(name(chosen), null, true, () => onTopic(chosen)),
                for (final t in menu ?? const <FeedTopic>[])
                  _Item(name(t.id), null, t.id == chosen, () => onTopic(t.id)),
              ],
            ),
        ],
      ),
    );
  }
}

class _Item {
  const _Item(this.title, this.detail, this.selected, this.onTap);

  final String title;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;
}

/// A rounded chip that opens an iOS pull-down menu, like the language menu
/// had before Settings (#46).
class _Pulldown extends StatefulWidget {
  const _Pulldown({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.items,
  });

  final IconData icon;
  final String label;
  final bool active;
  final List<_Item> items;

  @override
  State<_Pulldown> createState() => _PulldownState();
}

class _PulldownState extends State<_Pulldown> {
  AnimationStatus _status = AnimationStatus.dismissed;

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final fill = widget.active
        ? AppColors.accent
        : CupertinoColors.tertiarySystemFill.resolveFrom(context);
    final fg = widget.active ? CupertinoColors.white : label;
    return CupertinoMenuAnchor(
      onAnimationStatusChanged: (status) => _status = status,
      menuChildren: [
        for (final item in widget.items)
          CupertinoMenuItem(
            onPressed: item.onTap,
            subtitle: item.detail == null ? null : Text(item.detail!),
            trailing: item.selected
                ? const Icon(
                    CupertinoIcons.checkmark_alt,
                    color: AppColors.accent,
                  )
                : null,
            // VoiceOver says which one is current.
            child: Semantics(selected: item.selected, child: Text(item.title)),
          ),
      ],
      builder: (context, controller, _) => CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        // A tap while the menu is still closing opens it again.
        onPressed: () => _status.isForwardOrCompleted
            ? controller.close()
            : controller.open(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(CupertinoIcons.chevron_down, size: 12, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}
