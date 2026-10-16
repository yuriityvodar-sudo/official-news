import 'package:flutter/cupertino.dart';

import '../../core/filters.dart';
import '../../core/theme.dart';
import '../../core/topics.dart';
import '../../l10n/app_localizations.dart';

/// The two pull-downs under the date (#67, #68), as in the chips prototype
/// Yurii saw on the simulator (16 Oct): Where (all countries, a group, or one
/// country) and Topics (all, or one). Grey chips that open an iOS pull-down
/// menu with a checkmark on the current choice; no counts in the menus.
/// While nothing is chosen they read "All countries" / "All topics"; a choice
/// keeps the grey chip and shows short, in red: a country's code (GB), a
/// group's short name (G7), a topic's icon. The menus, and VoiceOver, keep
/// the full names.
class FeedFilterBar extends StatelessWidget {
  const FeedFilterBar({
    super.key,
    required this.where,
    required this.whereMenu,
    required this.topic,
    required this.topics,
    required this.onWhere,
    required this.onTopic,
  });

  /// What the feed shows now.
  final FeedWhere where;

  /// The groups and countries to offer; null hides the Where chip (a server
  /// without them, or none known yet) unless something is chosen, so it can
  /// always be cleared.
  final WhereMenu? whereMenu;

  /// The chosen topic's id, or null for all topics.
  final String? topic;

  /// The Topics menu, busiest first; null hides the Topics chip (a server
  /// without topics) unless a topic is chosen, so it can always be cleared.
  final List<FeedTopic>? topics;

  final ValueChanged<FeedWhere> onWhere;
  final ValueChanged<String?> onTopic;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final menu = whereMenu;
    final showWhere = menu != null || !where.isAll;
    final chosen = topic;
    final showTopics = topics != null || chosen != null;
    if (!showWhere && !showTopics) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (showWhere) _whereChip(l10n, menu),
          if (showTopics) _topicsChip(l10n, chosen),
        ],
      ),
    );
  }

  Widget _whereChip(AppLocalizations l10n, WhereMenu? menu) {
    final groups = menu?.groups ?? const <FeedGroup>[];
    final countries = menu?.countries ?? const <FeedCountry>[];
    final id = where.id;
    _Item item(FeedWhere choice, String title) =>
        _Item(title, choice == where, () => onWhere(choice));
    return _Pulldown(
      key: const ValueKey('filter-where'),
      label: switch (where.kind) {
        WhereKind.all => l10n.filterAllCountries,
        WhereKind.group => groupShortName(id!),
        WhereKind.country => id!,
      },
      active: !where.isAll,
      semanticLabel: switch (where.kind) {
        WhereKind.all => l10n.filterAllCountries,
        WhereKind.group => l10n.filterGroupChip(groupName(id!, menu, l10n)),
        WhereKind.country => l10n.filterCountryChip(
          whereCountryName(id!, menu, l10n),
        ),
      },
      sections: [
        [item(FeedWhere.all, l10n.filterAllCountries)],
        [
          // A choice the menu does not list stays in it, checked, so the
          // menu always shows what the feed shows.
          if (where.kind == WhereKind.group && !groups.any((g) => g.id == id))
            item(where, groupName(id!, menu, l10n)),
          for (final g in groups)
            item(FeedWhere.group(g.id), groupName(g.id, menu, l10n)),
        ],
        [
          if (where.kind == WhereKind.country &&
              !countries.any((c) => c.code == id))
            item(where, whereCountryName(id!, menu, l10n)),
          for (final c in countries)
            item(
              FeedWhere.country(c.code),
              whereCountryName(c.code, menu, l10n),
            ),
        ],
      ],
    );
  }

  Widget _topicsChip(AppLocalizations l10n, String? chosen) {
    final menu = topics ?? const <FeedTopic>[];
    String name(String id) => topicName(id, topics, l10n);
    return _Pulldown(
      key: const ValueKey('filter-topic'),
      label: l10n.filterAllTopics,
      icon: chosen == null ? null : topicIcon(chosen),
      active: chosen != null,
      semanticLabel: chosen == null
          ? l10n.filterAllTopics
          : l10n.filterTopicChip(name(chosen)),
      sections: [
        [_Item(l10n.filterAllTopics, chosen == null, () => onTopic(null))],
        [
          // The chosen topic stays in the menu, checked, when it has no
          // articles under the Where choice now.
          if (chosen != null && !menu.any((t) => t.id == chosen))
            _Item(name(chosen), true, () => onTopic(chosen)),
          for (final t in menu)
            _Item(name(t.id), t.id == chosen, () => onTopic(t.id)),
        ],
      ],
    );
  }
}

/// One item of a chip's menu.
class _Item {
  const _Item(this.title, this.selected, this.onTap);

  final String title;
  final bool selected;
  final VoidCallback onTap;
}

/// The red of a chip's label while it narrows the feed: the brand red, made
/// deeper on light grounds, where the brand red on the grey chip is under 3:1
/// (from the chips prototype).
const filterActiveRed = CupertinoDynamicColor.withBrightness(
  color: Color(0xFFD1203A),
  darkColor: AppColors.accent,
);

/// A rounded grey chip that opens an iOS pull-down menu, like the language
/// menu had before Settings (#46): [label] (or [icon]) and a chevron, both
/// red while [active].
class _Pulldown extends StatefulWidget {
  const _Pulldown({
    super.key,
    required this.label,
    this.icon,
    required this.active,
    required this.semanticLabel,
    required this.sections,
  });

  /// What the chip shows; [icon] instead when there is one.
  final String label;
  final IconData? icon;
  final bool active;

  /// What VoiceOver says for the chip: the full name of the choice.
  final String semanticLabel;

  /// The menu's items in groups, a wide divider between groups; empty groups
  /// are left out.
  final List<List<_Item>> sections;

  @override
  State<_Pulldown> createState() => _PulldownState();
}

class _PulldownState extends State<_Pulldown> {
  AnimationStatus _status = AnimationStatus.dismissed;

  @override
  Widget build(BuildContext context) {
    final fg = widget.active
        ? filterActiveRed.resolveFrom(context)
        : CupertinoColors.label.resolveFrom(context);
    final sections = widget.sections.where((s) => s.isNotEmpty).toList();
    // The menu stays clear of the status bar and the home indicator, as iOS's
    // own do: a long one (every group and country) scrolls between them. The
    // feed's SafeArea hides those insets from the chip, so they are read from
    // the screen itself.
    final insets = MediaQueryData.fromView(View.of(context)).padding;
    return CupertinoMenuAnchor(
      overlayPadding: EdgeInsets.fromLTRB(
        8,
        insets.top + 8,
        8,
        insets.bottom + 8,
      ),
      onAnimationStatusChanged: (status) => _status = status,
      menuChildren: [
        for (final (i, section) in sections.indexed) ...[
          if (i > 0) const CupertinoMenuDivider(),
          for (final item in section)
            CupertinoMenuItem(
              onPressed: item.onTap,
              trailing: item.selected
                  ? const Icon(
                      CupertinoIcons.checkmark_alt,
                      color: AppColors.accent,
                    )
                  : null,
              // VoiceOver says which one is current.
              child: Semantics(
                selected: item.selected,
                child: Text(item.title),
              ),
            ),
        ],
      ],
      builder: (context, controller, _) => CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        // A tap while the menu is still closing opens it again.
        onPressed: () => _status.isForwardOrCompleted
            ? controller.close()
            : controller.open(),
        child: Semantics(
          label: widget.semanticLabel,
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // At the largest text sizes a long label ends in "…" instead
                // of overflowing the chip. An icon sits in a line of text, so
                // the chip is as high as one with a label, and grows with it.
                Flexible(
                  child: Text.rich(
                    widget.icon == null
                        ? TextSpan(text: widget.label)
                        : WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Icon(widget.icon, size: 17, color: fg),
                          ),
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
      ),
    );
  }
}
