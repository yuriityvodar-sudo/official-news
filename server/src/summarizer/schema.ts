// What one AI call returns for an article (docs/style-guide.md), and the
// check that turns the model's JSON into values safe to store.

/** The fixed lists from docs/contract.md. */
export const DECISION_TYPES = [
  "law",
  "bill",
  "amendment",
  "proposal",
  "cabinet-decision",
  "decision",
  "meeting-agenda",
  "meeting-outcome",
] as const;

export const TOPICS = [
  "foreign-affairs",
  "economy",
  "security-defence",
  "health",
  "climate",
  "trade",
  "technology",
  "energy",
  "migration",
  "elections",
  "human-rights",
  "science",
] as const;

export type DecisionType = (typeof DECISION_TYPES)[number];
export type Topic = (typeof TOPICS)[number];

export interface Summary {
  isNews: boolean;
  decisionType: DecisionType | null;
  headline: string;
  shortSummary: string;
  summary: string;
  topics: Topic[];
  tags: string[];
  importance: number;
}

export const LIMITS = {
  headline: 90,
  shortSummary: 200,
  summary: 1200,
  tags: 8,
  tagLength: 60,
  topics: 3,
};

/** JSON schema sent with the request, so the model answers in this shape. */
export const SUMMARY_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["isNews", "decisionType", "headline", "shortSummary", "summary", "topics", "tags", "importance"],
  properties: {
    isNews: { type: "boolean" },
    decisionType: { type: ["string", "null"], enum: [...DECISION_TYPES, null] },
    headline: { type: "string" },
    shortSummary: { type: "string" },
    summary: { type: "string" },
    topics: { type: "array", items: { type: "string", enum: [...TOPICS] }, maxItems: LIMITS.topics },
    tags: { type: "array", items: { type: "string" }, maxItems: LIMITS.tags },
    importance: { type: "integer", minimum: 1, maximum: 5 },
  },
} as const;

/** Trims to `max` characters at a word boundary when one is close. */
function clip(text: string, max: number): string {
  if (text.length <= max) return text;
  const cut = text.slice(0, max - 1);
  const space = cut.lastIndexOf(" ");
  return `${(space > max * 0.6 ? cut.slice(0, space) : cut).replace(/[\s,;:.-]+$/, "")}…`;
}

const clean = (value: unknown): string => (typeof value === "string" ? value.replace(/\s+\n/g, "\n").trim() : "");

/** Reads the model's text as JSON, also when it wraps it in a ```json fence. */
export function parseJson(text: string): unknown {
  const fenced = text.trim().match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  return JSON.parse(fenced ? fenced[1] : text);
}

/**
 * Checks the model's answer and normalises it. Returns the problems instead of
 * a summary when something essential is missing or wrong.
 */
export function toSummary(value: unknown): { summary: Summary } | { problems: string[] } {
  if (!value || typeof value !== "object" || Array.isArray(value)) return { problems: ["not a JSON object"] };
  const v = value as Record<string, unknown>;
  const problems: string[] = [];

  if (typeof v.isNews !== "boolean") problems.push("isNews is not true or false");
  const headline = clean(v.headline).replace(/\.$/, "");
  if (!headline) problems.push("headline is empty");
  const shortSummary = clean(v.shortSummary);
  if (!shortSummary) problems.push("shortSummary is empty");
  const summary = clean(v.summary);
  if (!summary) problems.push("summary is empty");
  const importance = typeof v.importance === "number" ? Math.round(v.importance) : Number.NaN;
  if (!(importance >= 1 && importance <= 5)) problems.push("importance is not 1 to 5");
  if (problems.length) return { problems };

  const isNews = v.isNews === true;
  let decisionType: DecisionType | null = null;
  if (isNews) {
    decisionType = DECISION_TYPES.includes(v.decisionType as DecisionType) ? (v.decisionType as DecisionType) : "decision";
  }

  const topics = Array.isArray(v.topics)
    ? [...new Set(v.topics.filter((t): t is Topic => TOPICS.includes(t as Topic)))].slice(0, LIMITS.topics)
    : [];
  const tags = Array.isArray(v.tags)
    ? [...new Set(v.tags.map(clean).filter(Boolean).map((t) => clip(t, LIMITS.tagLength)))].slice(0, LIMITS.tags)
    : [];

  return {
    summary: {
      isNews,
      decisionType,
      headline: clip(headline, LIMITS.headline),
      shortSummary: clip(shortSummary, LIMITS.shortSummary),
      summary: clip(summary, LIMITS.summary),
      topics,
      tags,
      importance,
    },
  };
}
