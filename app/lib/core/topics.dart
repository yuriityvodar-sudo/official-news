import 'package:flutter/cupertino.dart' show CupertinoIcons, IconData;

import '../l10n/app_localizations.dart';

/// The fixed topic list from docs/contract.md. The AI picks 1 to 3 of these
/// per article; the Topics chip (#67) shows one of them. A new topic needs
/// its name here (ARB files, [topicLabel]) and its icon ([topicIcons]), as on
/// the server (`TOPICS`, `TOPIC_NAMES`); until then the app shows the
/// server's name and [otherTopicIcon].
const topicIds = [
  'foreign-affairs',
  'economy',
  'security-defence',
  'health',
  'climate',
  'trade',
  'technology',
  'energy',
  'migration',
  'elections',
  'human-rights',
  'science',
];

/// Topic [id]'s name in the app's language (lib/l10n/app_*.arb, the same names
/// as the server's `TOPIC_NAMES`), or null for an id the app does not know.
String? topicLabel(String id, AppLocalizations l10n) => switch (id) {
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
  _ => null,
};

/// What the Topics chip shows instead of the name once a topic is chosen, as
/// in the chips prototype after Yurii's review (prototype/chips 3d88cf3,
/// 16 Oct): one glyph per topic. The Topics menu shows each beside its name,
/// so the reader learns them. None means something else in the app: no
/// heart (reads as a favourite), no ticked box (reads as chosen), no weather.
const topicIcons = <String, IconData>{
  'foreign-affairs': CupertinoIcons.globe,
  'economy': CupertinoIcons.chart_bar_alt_fill,
  'security-defence': CupertinoIcons.shield_fill,
  'health': CupertinoIcons.staroflife_fill,
  'climate': CupertinoIcons.leaf_arrow_circlepath,
  'trade': CupertinoIcons.arrow_right_arrow_left,
  'technology': CupertinoIcons.desktopcomputer,
  'energy': CupertinoIcons.bolt_fill,
  'migration': CupertinoIcons.person_2_fill,
  'elections': CupertinoIcons.doc_checkmark_fill,
  'human-rights': CupertinoIcons.hand_raised_fill,
  'science': CupertinoIcons.lab_flask_solid,
};

/// The chip's glyph for a topic the app has no icon for yet (one the server
/// added after this build).
const otherTopicIcon = CupertinoIcons.square_grid_2x2;

IconData topicIcon(String id) => topicIcons[id] ?? otherTopicIcon;
