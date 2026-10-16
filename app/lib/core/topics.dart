import '../l10n/app_localizations.dart';

/// The fixed topic list from docs/contract.md. The AI picks 1 to 3 of these
/// per article; the Topics chip (#67) shows one of them.
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
