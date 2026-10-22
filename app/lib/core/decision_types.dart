import '../l10n/app_localizations.dart';

/// The fixed list of decision types from docs/contract.md. The AI gives each
/// article one of them; the article screen shows its label above the
/// headline, in the app's language (#52: the labels are in
/// lib/l10n/app_*.arb). The feed's cards show topics instead (16 Oct).
const decisionTypes = [
  'law',
  'bill',
  'amendment',
  'proposal',
  'cabinet-decision',
  'decision',
  'meeting-agenda',
  'meeting-outcome',
];

/// The label for [id], or null for an unknown or missing type (shown without a label).
String? decisionTypeLabel(String? id, AppLocalizations l10n) => switch (id) {
  'law' => l10n.decisionTypeLaw,
  'bill' => l10n.decisionTypeBill,
  'amendment' => l10n.decisionTypeAmendment,
  'proposal' => l10n.decisionTypeProposal,
  'cabinet-decision' => l10n.decisionTypeCabinetDecision,
  'decision' => l10n.decisionTypeDecision,
  'meeting-agenda' => l10n.decisionTypeMeetingAgenda,
  'meeting-outcome' => l10n.decisionTypeMeetingOutcome,
  _ => null,
};
