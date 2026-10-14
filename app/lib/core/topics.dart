/// The fixed topic list from docs/contract.md. The AI picks 1 to 3 of these
/// per article; the user picks at least 3 during onboarding.
class Topic {
  const Topic(this.id, this.label);

  final String id;
  final String label;
}

const topics = <Topic>[
  Topic('foreign-affairs', 'Foreign affairs'),
  Topic('economy', 'Economy'),
  Topic('security-defence', 'Security and defence'),
  Topic('health', 'Health'),
  Topic('climate', 'Climate'),
  Topic('trade', 'Trade'),
  Topic('technology', 'Technology'),
  Topic('energy', 'Energy'),
  Topic('migration', 'Migration'),
  Topic('elections', 'Elections'),
  Topic('human-rights', 'Human rights'),
  Topic('science', 'Science'),
];

String topicLabel(String id) =>
    topics.firstWhere((t) => t.id == id, orElse: () => Topic(id, id)).label;
