import 'package:flutter/cupertino.dart';

import '../../core/article.dart';
import '../../core/countries.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';

/// PROTOTYPE (#67, #68): the feed's two filters, shown to Yurii on the phone
/// before the real build. Filters the loaded feed on the phone; the real
/// version asks the server (`?country=`, `?topic=`).
///
/// Where (Yurii, 16 Oct): All countries, then the groups (official
/// organisations), then each country with articles in the feed. A country
/// shows only its own articles, a group its members'. Topics: all, or one.
/// A chip that narrows the feed shows its choice short, in red on the same
/// grey chip: a country's code (GB), a group's short name (G7), a topic's
/// icon. Its menu keeps the full names.

/// The groups in the Where menu, by the short name their chip shows, with
/// their members as the codes articles carry (docs/sources.csv); 'EU' is the
/// EU's own institutions. The European Union is its institutions and the
/// member states among the sources (a new EU source joins here); the EU is a
/// member of the G7 and the G20 as well. One map, for the real build too.
const countryGroups = <String, Set<String>>{
  'EU': {'EU', 'DE', 'FR', 'IT', 'ES', 'PL', 'CZ'},
  'G7': {'US', 'GB', 'CA', 'FR', 'DE', 'IT', 'JP', 'EU'},
  'G20': {
    'AR',
    'AU',
    'BR',
    'CA',
    'CN',
    'FR',
    'DE',
    'IN',
    'ID',
    'IT',
    'JP',
    'KR',
    'MX',
    'SA',
    'ZA',
    'TR',
    'GB',
    'US',
    'EU',
  },
};

/// A group's name in the menu and for VoiceOver: the European Union in the
/// app's language; G7 and G20 are written so in every language.
String groupName(String group, AppLocalizations l10n) =>
    group == 'EU' ? l10n.countryEU : group;

/// Where the feed's articles come from: every country, a group of countries
/// ([countryGroups]) or one country.
@immutable
class FeedPlace {
  const FeedPlace._(this.code, this.isGroup);

  /// One country, by its code ("GB").
  const FeedPlace.country(String this.code) : isGroup = false;

  /// A group, by its short name: a key of [countryGroups].
  const FeedPlace.group(String this.code) : isGroup = true;

  static const all = FeedPlace._(null, false);

  /// A group's short name or a country's code, in any case; anything empty
  /// is every country. For demo builds (`FILTER_DEMO=GB:economy`).
  factory FeedPlace.named(String name) {
    final code = name.trim().toUpperCase();
    if (code.isEmpty) return all;
    return countryGroups.containsKey(code)
        ? FeedPlace.group(code)
        : FeedPlace.country(code);
  }

  /// The country's code or the group's short name; null for every country.
  final String? code;
  final bool isGroup;

  bool get isAll => code == null;

  /// Whether [article] is shown here.
  bool includes(Article article) => switch ((code, isGroup)) {
    (null, _) => true,
    (final group?, true) => countryGroups[group]!.contains(article.country),
    (final country?, false) => article.country == country,
  };

  @override
  bool operator ==(Object other) =>
      other is FeedPlace && other.code == code && other.isGroup == isGroup;

  @override
  int get hashCode => Object.hash(code, isGroup);

  @override
  String toString() => isAll ? 'all' : '${isGroup ? 'group' : 'country'} $code';
}

/// Topic [id]'s name in the app's language: the same switch as #87's
/// `topicLabel` in core/topics.dart, over the same ARB keys. An id the app
/// does not know shows as it is.
String topicName(String id, AppLocalizations l10n) => switch (id) {
  'foreign-affairs' => l10n.topicForeignAffairs,
  'economy' => l10n.topicEconomy,
  'security-defence' => l10n.topicSecurityDefence,
  'health' => l10n.topicHealth,
  'climate' => l10n.topicClimate,
  'trade' => l10n.topicTrade,
  'technology' => l10n.topicTechnology,
  'energy' => l10n.topicEnergy,
  'migration' => l10n.topicMigration,
  'elections' => l10n.topicElections,
  'human-rights' => l10n.topicHumanRights,
  'science' => l10n.topicScience,
  _ => id,
};

/// What the Topics chip shows instead of the name once a topic is chosen:
/// an SF Symbols-style glyph per topic. One map, for the real build too.
const topicIcons = <String, IconData>{
  'foreign-affairs': CupertinoIcons.globe,
  'economy': CupertinoIcons.chart_bar_alt_fill,
  'security-defence': CupertinoIcons.shield_fill,
  'health': CupertinoIcons.heart_fill,
  'climate': CupertinoIcons.cloud_sun_fill,
  'trade': CupertinoIcons.arrow_right_arrow_left,
  'technology': CupertinoIcons.desktopcomputer,
  'energy': CupertinoIcons.bolt_fill,
  'migration': CupertinoIcons.person_2_fill,
  'elections': CupertinoIcons.checkmark_square_fill,
  'human-rights': CupertinoIcons.hand_raised_fill,
  'science': CupertinoIcons.lab_flask_solid,
};

/// English topic names, still read by design B's cards
/// (feed_look_b_words.dart). The filters use [topicName], in every language.
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

/// The filters a demo build starts with: `--dart-define=FILTER_DEMO=GB:economy`
/// is the United Kingdom and Economy, `G7` the G7 and every topic, `:health`
/// every country and Health. Empty (the default) is no filter.
({FeedPlace place, String? topic}) demoFilters(String spec) {
  final parts = spec.split(':');
  final topic = parts.length > 1 ? parts[1].trim().toLowerCase() : '';
  return (
    place: FeedPlace.named(parts.first),
    topic: topic.isEmpty ? null : topic,
  );
}

/// PROTOTYPE: `--dart-define=FILTER_MENU=where` (or `topics`) opens that menu
/// once the feed has loaded, for screenshots without a tap.
const _demoMenu = String.fromEnvironment('FILTER_MENU');
bool _demoMenuOpened = false;

/// Sorts names as a reader expects: Dart compares UTF-16 code units, which
/// puts Ukrainian і, ї, є, ґ and Russian ё after я ("Італія" after "Японія")
/// and accented letters after z.
int compareNames(String a, String b) => _sortKey(a).compareTo(_sortKey(b));

/// Ukrainian and Russian together, in their own order (neither alphabet has
/// the other's extra letters, so one order serves both).
const _cyrillic = 'абвгґдеєёжзиіїйклмнопрстуфхцчшщъыьэюя';
// Accented Latin letters sort with their plain letter (German, Spanish);
// Spanish ñ comes after n, German ß reads as ss.
const _accented = 'àáâäãåçèéêëìíîïòóôöõùúûüýÿ';
const _plain = 'aaaaaaceeeeiiiiooooouuuuyy';

String _sortKey(String name) {
  final key = StringBuffer();
  for (final rune in name.toLowerCase().runes) {
    final letter = String.fromCharCode(rune);
    final cyrillic = _cyrillic.indexOf(letter);
    final accented = _accented.indexOf(letter);
    if (cyrillic >= 0) {
      key.writeCharCode(0x0400 + cyrillic);
    } else if (accented >= 0) {
      key.write(_plain[accented]);
    } else if (letter == 'ñ') {
      key.write('n\u{FFFF}');
    } else if (letter == 'ß') {
      key.write('ss');
    } else {
      key.write(letter);
    }
  }
  return key.toString();
}

/// The two pull-downs under the date: Where (every country, a group or one
/// country) and Topics.
class FeedFilterBar extends StatelessWidget {
  const FeedFilterBar({
    super.key,
    required this.place,
    required this.countries,
    required this.topic,
    required this.topicCounts,
    required this.onPlace,
    required this.onTopic,
  });

  final FeedPlace place;

  /// The countries with articles in the loaded feed, as codes, in any order.
  final Iterable<String> countries;

  /// The topic id shown, or null for all topics.
  final String? topic;

  /// Topics with posts under the current Where choice, busiest first.
  final List<MapEntry<String, int>> topicCounts;
  final ValueChanged<FeedPlace> onPlace;
  final ValueChanged<String?> onTopic;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chosen = topic;

    // Each country alone, by its name. The EU's institutions are not a
    // country: they are in the European Union group, so the EU shows once.
    // The chosen country stays in the menu, checked, while it has nothing.
    final codes = {
      for (final c in countries)
        if (c != 'EU') c,
      if (!place.isAll && !place.isGroup) place.code!,
    }.toList();
    final names = {for (final c in codes) c: countryName(c, l10n)};
    codes.sort((a, b) => compareNames(names[a]!, names[b]!));

    final placeCode = place.code;
    final where = _Pulldown(
      key: const ValueKey('filter-where'),
      label: placeCode ?? l10n.filterGlobalDetail,
      active: !place.isAll,
      semanticLabel: switch (placeCode) {
        null => l10n.filterGlobalDetail,
        final g when place.isGroup => l10n.filterGroupChip(groupName(g, l10n)),
        final c => l10n.filterCountryChip(countryName(c, l10n)),
      },
      openAtStart: _demoMenu == 'where' && codes.isNotEmpty,
      sections: [
        [
          _Item(
            l10n.filterGlobalDetail,
            place.isAll,
            () => onPlace(FeedPlace.all),
          ),
        ],
        [
          for (final group in countryGroups.keys)
            _Item(
              groupName(group, l10n),
              place == FeedPlace.group(group),
              () => onPlace(FeedPlace.group(group)),
            ),
        ],
        [
          for (final code in codes)
            _Item(
              names[code]!,
              place == FeedPlace.country(code),
              () => onPlace(FeedPlace.country(code)),
            ),
        ],
      ],
    );

    final topics = _Pulldown(
      key: const ValueKey('filter-topic'),
      label: l10n.filterAllTopics,
      icon: chosen == null
          ? null
          : topicIcons[chosen] ?? CupertinoIcons.square_grid_2x2,
      active: chosen != null,
      semanticLabel: chosen == null
          ? l10n.filterAllTopics
          : l10n.filterTopicChip(topicName(chosen, l10n)),
      openAtStart: _demoMenu == 'topics' && topicCounts.isNotEmpty,
      sections: [
        [_Item(l10n.filterAllTopics, chosen == null, () => onTopic(null))],
        [
          // The chosen topic stays in the menu, checked, while it has nothing
          // under the Where choice.
          if (chosen != null && !topicCounts.any((e) => e.key == chosen))
            _Item(topicName(chosen, l10n), true, () => onTopic(chosen)),
          for (final e in topicCounts)
            _Item(
              topicName(e.key, l10n),
              e.key == chosen,
              () => onTopic(e.key),
            ),
        ],
      ],
    );

    // A chip is 15-pt text (about 1.2 lines high in SF) with 7 pt above and
    // below, in a target at least 44 pt high. The bar keeps each chip's
    // middle where the 36-pt targets had it (10 pt down, half a target), so
    // the looks' layouts around it, such as B's gear beside it, stay level;
    // the larger target takes the room around the chips instead.
    final chip = 14 + MediaQuery.textScalerOf(context).scale(15) * 1.2;
    final room = 44 - chip.clamp(36.0, 44.0);
    return Padding(
      padding: EdgeInsets.only(top: 10 - room / 2),
      child: Wrap(spacing: 8, runSpacing: 8 - room, children: [where, topics]),
    );
  }
}

class _Item {
  const _Item(this.title, this.selected, this.onTap);
  final String title;
  final bool selected;
  final VoidCallback onTap;
}

/// The red of a chip that narrows the feed: the brand red, made deeper on
/// light grounds, where the brand red on the grey chip is under 3:1.
const _activeRed = CupertinoDynamicColor.withBrightness(
  color: Color(0xFFD1203A),
  darkColor: AppColors.accent,
);

/// A rounded grey chip that opens an iOS pull-down menu, like the old
/// language menu: [label] (or [icon]) and a chevron, both red while [active].
class _Pulldown extends StatefulWidget {
  const _Pulldown({
    super.key,
    required this.label,
    this.icon,
    required this.active,
    required this.semanticLabel,
    required this.sections,
    this.openAtStart = false,
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

  /// PROTOTYPE: open the menu by itself, once ([_demoMenu]).
  final bool openAtStart;

  @override
  State<_Pulldown> createState() => _PulldownState();
}

class _PulldownState extends State<_Pulldown> {
  AnimationStatus _status = AnimationStatus.dismissed;
  final _menu = MenuController();

  void _openForDemo() {
    // The headers that measure themselves build a copy of the bar that is
    // never shown, its focus excluded: only the bar on screen opens.
    if (!widget.openAtStart ||
        _demoMenuOpened ||
        context.findAncestorWidgetOfExactType<ExcludeFocus>() != null) {
      return;
    }
    _demoMenuOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _menu.open();
    });
  }

  @override
  Widget build(BuildContext context) {
    _openForDemo();
    final fg = widget.active
        ? _activeRed.resolveFrom(context)
        : CupertinoColors.label.resolveFrom(context);
    final sections = widget.sections.where((s) => s.isNotEmpty).toList();
    return CupertinoMenuAnchor(
      controller: _menu,
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
