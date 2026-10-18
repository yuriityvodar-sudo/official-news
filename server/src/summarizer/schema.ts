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
  "education",
  "justice",
] as const;

export type DecisionType = (typeof DECISION_TYPES)[number];
export type Topic = (typeof TOPICS)[number];

/**
 * What a decision means in practice (#63): direct consequences of its stated
 * terms, an AI analysis the app labels as such. Every part may be missing.
 */
export interface Impact {
  /** For any reader: who must or may do what, pays or gets what, from when. */
  general: string | null;
  /** One line per topic of the article, from that topic's angle (docs/style-guide.md). */
  byTopic: { topic: Topic; text: string }[];
  /** For people and businesses in the country or bloc that decided. */
  residents: string | null;
  /** For people and businesses outside it. */
  abroad: string | null;
}

export interface Summary {
  isNews: boolean;
  decisionType: DecisionType | null;
  headline: string;
  shortSummary: string;
  summary: string;
  topics: Topic[];
  tags: string[];
  importance: number;
  /** null when the article is not news, or nothing follows directly from it. */
  impact: Impact | null;
}

export const LIMITS = {
  headline: 90,
  shortSummary: 200,
  summary: 1200,
  tags: 8,
  tagLength: 60,
  topics: 3,
  impactGeneral: 250,
  impactLine: 200,
};

/** JSON schema sent with the request, so the model answers in this shape. */
export const SUMMARY_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["isNews", "decisionType", "headline", "shortSummary", "summary", "topics", "tags", "importance", "impact"],
  properties: {
    isNews: { type: "boolean" },
    decisionType: { type: ["string", "null"], enum: [...DECISION_TYPES, null] },
    headline: { type: "string" },
    shortSummary: { type: "string" },
    summary: { type: "string" },
    topics: { type: "array", items: { type: "string", enum: [...TOPICS] }, maxItems: LIMITS.topics },
    tags: { type: "array", items: { type: "string" }, maxItems: LIMITS.tags },
    importance: { type: "integer", minimum: 1, maximum: 5 },
    impact: {
      type: ["object", "null"],
      additionalProperties: false,
      required: ["general", "byTopic", "residents", "abroad"],
      properties: {
        general: { type: ["string", "null"] },
        byTopic: {
          type: "array",
          maxItems: LIMITS.topics,
          items: {
            type: "object",
            additionalProperties: false,
            required: ["topic", "text"],
            properties: { topic: { type: "string", enum: [...TOPICS] }, text: { type: "string" } },
          },
        },
        residents: { type: ["string", "null"] },
        abroad: { type: ["string", "null"] },
      },
    },
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
      impact: isNews ? toImpact(v.impact, topics) : null,
    },
  };
}

/**
 * The impact part, cleaned: lines only for the article's own topics, and no
 * line that repeats another (the model tends to copy `general` into every
 * part). null when nothing is left.
 */
function toImpact(value: unknown, topics: Topic[]): Impact | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const v = value as Record<string, unknown>;
  const seen = new Set<string>();
  const line = (x: unknown, max: number): string | null => {
    const text = clean(x);
    const key = text.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, "");
    if (!text || seen.has(key)) return null;
    seen.add(key);
    return clip(text, max);
  };
  const general = line(v.general, LIMITS.impactGeneral);
  const byTopic: Impact["byTopic"] = [];
  for (const entry of Array.isArray(v.byTopic) ? v.byTopic : []) {
    const e = entry as Record<string, unknown> | null;
    const topic = e?.topic as Topic;
    if (!topics.includes(topic) || byTopic.some((b) => b.topic === topic)) continue;
    const text = line(e?.text, LIMITS.impactLine);
    if (text) byTopic.push({ topic, text });
  }
  const residents = line(v.residents, LIMITS.impactLine);
  const abroad = line(v.abroad, LIMITS.impactLine);
  return general || byTopic.length || residents || abroad ? { general, byTopic, residents, abroad } : null;
}
