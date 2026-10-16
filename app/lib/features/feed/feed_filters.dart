import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/article.dart';
import '../../core/countries.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';

/// PROTOTYPE (#67, #68): the feed's two filters, shown to Yurii on the
/// simulator before the real design. Filters the loaded feed on the phone;
/// the real version asks the server (`?country=`, `?topic=`).

enum FeedScope { global, local }

/// EU members: their Local feed also shows the EU's own decisions.
const _eu = {
  'AT',
  'BE',
  'BG',
  'HR',
  'CY',
  'CZ',
  'DK',
  'EE',
  'FI',
  'FR',
  'DE',
  'GR',
  'HU',
  'IE',
  'IT',
  'LV',
  'LT',
  'LU',
  'MT',
  'NL',
  'PL',
  'PT',
  'RO',
  'SK',
  'SI',
  'ES',
  'SE',
};

/// The reader's country from the phone's region (no location permission).
String phoneCountry() =>
    WidgetsBinding.instance.platformDispatcher.locale.countryCode ?? 'US';

/// Whether [a] belongs to the Local feed of [country].
bool isLocal(Article a, String country) =>
    a.country == country || (a.country == 'EU' && _eu.contains(country));

/// Topic names for the prototype (the real menu gets them from the server).
const topicNames = {
  'economy': 'Economy',
  'technology': 'Technology',
  'health': 'Health',
  'security-defence': 'Security & defence',
  'human-rights': 'Human rights',
  'trade': 'Trade',
  'energy': 'Energy',
  'climate': 'Climate',
  'science': 'Science',
  'foreign-affairs': 'Foreign affairs',
  'elections': 'Elections',
  'migration': 'Migration',
};

/// The two pull-downs under the date: where (Global / Local) and the topic.
class FeedFilterBar extends StatelessWidget {
  const FeedFilterBar({
    super.key,
    required this.scope,
    required this.country,
    required this.topic,
    required this.topicCounts,
    required this.onScope,
    required this.onTopic,
  });

  final FeedScope scope;
  final String country;
  final String? topic;

  /// Topics with posts in the current feed, busiest first.
  final List<MapEntry<String, int>> topicCounts;
  final ValueChanged<FeedScope> onScope;
  final ValueChanged<String?> onTopic;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final place = countryName(country, l10n);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _Pulldown(
            icon: scope == FeedScope.global
                ? CupertinoIcons.globe
                : CupertinoIcons.location_solid,
            label: scope == FeedScope.global ? 'Global' : place,
            active: scope == FeedScope.local,
            items: [
              _Item(
                'Global',
                'All countries',
                scope == FeedScope.global,
                () => onScope(FeedScope.global),
              ),
              _Item(
                'Local',
                place,
                scope == FeedScope.local,
                () => onScope(FeedScope.local),
              ),
            ],
          ),
          _Pulldown(
            icon: CupertinoIcons.square_grid_2x2,
            label: topic == null
                ? 'All topics'
                : (topicNames[topic] ?? topic ?? ""),
            active: topic != null,
            items: [
              _Item('All topics', null, topic == null, () => onTopic(null)),
              for (final e in topicCounts)
                _Item(
                  topicNames[e.key] ?? e.key,
                  null,
                  topic == e.key,
                  () => onTopic(e.key),
                ),
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

/// A rounded chip that opens an iOS pull-down menu, like the old language menu.
class _Pulldown extends StatefulWidget {
  const _Pulldown({
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
      onAnimationStatusChanged: (s) => _status = s,
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
            child: Text(item.title),
          ),
      ],
      builder: (context, controller, _) => CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 36),
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
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: fg,
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
