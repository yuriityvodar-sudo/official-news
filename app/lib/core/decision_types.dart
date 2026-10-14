/// The fixed list of decision types from docs/contract.md. The AI gives each
/// article one of them; the app shows its label above the headline.
class DecisionType {
  const DecisionType(this.id, this.label);

  final String id;
  final String label;
}

const decisionTypes = <DecisionType>[
  DecisionType('law', 'Law'),
  DecisionType('bill', 'Bill'),
  DecisionType('amendment', 'Amendment'),
  DecisionType('proposal', 'Proposal'),
  DecisionType('cabinet-decision', 'Cabinet decision'),
  DecisionType('decision', 'Decision'),
  DecisionType('meeting-agenda', 'Meeting agenda'),
  DecisionType('meeting-outcome', 'Meeting outcome'),
];

/// The label for [id], or null for an unknown or missing type (shown without a label).
String? decisionTypeLabel(String? id) {
  for (final type in decisionTypes) {
    if (type.id == id) return type.label;
  }
  return null;
}
