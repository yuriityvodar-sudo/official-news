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
  // Not a decision (#230): what happened in the world, from Wikipedia's current events.
  "event",
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
 * The kinds of hook headline (#133). The code picks one per article
 * (`headlineKind` in prompt.ts); the model may write a plain one instead, for
 * war, disasters and deaths and for decisions that change nothing practical.
 */
export const HEADLINE_KINDS = ["question", "consequence", "contrast"] as const;
export type HeadlineKind = (typeof HEADLINE_KINDS)[number];
/** What the model says it wrote: the kind it was given, or plain. Stored as `headline_type`. */
export const HEADLINE_TYPES = [...HEADLINE_KINDS, "plain"] as const;
export type HeadlineType = (typeof HEADLINE_TYPES)[number];

/** How far a decision reaches (#230): one country, a group of countries or a region, or the whole world. */
export const REACHES = ["national", "regional", "global"] as const;
export type Reach = (typeof REACHES)[number];

/** Codes the model writes for a country that has another ISO code. */
const COUNTRY_ALIASES: Record<string, string> = { UK: "GB", EL: "GR" };

export interface Summary {
  isNews: boolean;
  decisionType: DecisionType | null;
  headline: string;
  headlineType: HeadlineType;
  shortSummary: string;
  summary: string;
  topics: Topic[];
  importance: number;
  /**
   * The countries whose people it concerns most (#230): ISO 3166-1 alpha-2
   * codes, and EU for the Union as a whole. Empty when the model gave none:
   * then the source's country is stored.
   */
  countries: string[];
  reach: Reach;
  /**
   * For its popularity (#230 step 4): the titles of up to 2 English Wikipedia
   * articles about what it is about most, whose page views per language tell
   * how much each country's readers look it up; and up to 4 English words its
   * news coverage would contain, to count that coverage. Empty when none.
   */
  wikipedia: string[];
  keywords: string[];
}

/**
 * What is accepted (#133). The prompt asks for less (a headline up to 80
 * characters, a summary of 600 to 900): a little over costs nothing, more than
 * this a retry, and on the last try it is clipped.
 */
export const LIMITS = {
  headline: 90,
  shortSummary: 200,
  summary: 1000,
  topics: 3,
  countries: 5,
  wikipedia: 2,
  keywords: 4,
};

/** A Wikipedia title or a keyword longer than this is not one: left out. */
const MAX_NAME = 100;

/**
 * JSON schema sent with the request, so the model answers in this shape. The
 * summary comes before the headline: the headline is written from it. Since
 * #133 the model writes no `impact` (what it means is in the summary) and no
 * `tags` (the app does not show them); they are stored empty.
 */
export const SUMMARY_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "isNews",
    "decisionType",
    "topics",
    "importance",
    "countries",
    "reach",
    "summary",
    "shortSummary",
    "headline",
    "headlineType",
    "wikipedia",
    "keywords",
  ],
  properties: {
    isNews: { type: "boolean" },
    decisionType: { type: ["string", "null"], enum: [...DECISION_TYPES, null] },
    topics: { type: "array", items: { type: "string", enum: [...TOPICS] }, maxItems: LIMITS.topics },
    importance: { type: "integer", minimum: 1, maximum: 5 },
    countries: { type: "array", items: { type: "string", pattern: "^[A-Z]{2}$" }, maxItems: LIMITS.countries },
    reach: { type: "string", enum: [...REACHES] },
    summary: { type: "string" },
    shortSummary: { type: "string" },
    headline: { type: "string" },
    headlineType: { type: "string", enum: [...HEADLINE_TYPES] },
    wikipedia: { type: "array", items: { type: "string" }, maxItems: LIMITS.wikipedia },
    keywords: { type: "array", items: { type: "string" }, maxItems: LIMITS.keywords },
  },
} as const;

/** Up to `max` distinct names from the model's list: trimmed, none empty or too long; anything else reads as none. */
function names(value: unknown, max: number, spaces: RegExp = /\s+/g): string[] {
  if (!Array.isArray(value)) return [];
  const out = value
    .filter((v): v is string => typeof v === "string")
    .map((v) => v.replace(spaces, " ").trim())
    .filter((v) => v.length > 0 && v.length <= MAX_NAME);
  return [...new Set(out)].slice(0, max);
}

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
 * a summary when something essential is missing or wrong. `kind` is the
 * headline kind that was asked for: an answer that names another kind keeps it.
 * News from an `event` source (#230) is of the type event, and an official
 * article never is. Lengths are not clipped here: one over its limit costs a
 * retry (`overLimits`).
 */
export function toSummary(value: unknown, kind: HeadlineKind, event = false): { summary: Summary } | { problems: string[] } {
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
  if (isNews && event) decisionType = "event";
  else if (isNews) {
    decisionType = DECISION_TYPES.includes(v.decisionType as DecisionType) && v.decisionType !== "event" ? (v.decisionType as DecisionType) : "decision";
  }
  const topics = Array.isArray(v.topics)
    ? [...new Set(v.topics.filter((t): t is Topic => TOPICS.includes(t as Topic)))].slice(0, LIMITS.topics)
    : [];
  const headlineType = HEADLINE_TYPES.includes(v.headlineType as HeadlineType) ? (v.headlineType as HeadlineType) : kind;
  // Codes only; none is not a problem: the source's country is stored then (#230).
  const codes = Array.isArray(v.countries) ? v.countries.filter((c): c is string => typeof c === "string") : [];
  const countries = [
    ...new Set(
      codes
        .map((c) => c.trim().toUpperCase())
        .map((c) => COUNTRY_ALIASES[c] ?? c)
        .filter((c) => /^[A-Z]{2}$/.test(c)),
    ),
  ].slice(0, LIMITS.countries);
  const reach = REACHES.includes(v.reach as Reach) ? (v.reach as Reach) : "national";

  return {
    summary: {
      isNews,
      decisionType,
      headline,
      headlineType,
      shortSummary: clip(shortSummary, LIMITS.shortSummary),
      summary,
      topics,
      importance,
      countries,
      reach,
      // Wikipedia's links write a title's spaces as underscores: the title has spaces.
      wikipedia: names(v.wikipedia, LIMITS.wikipedia, /[\s_]+/g),
      keywords: names(v.keywords, LIMITS.keywords),
    },
  };
}

/** The fields longer than their limit (#133): a retry, or clipped on the last try. */
export function overLimits(s: Summary): string[] {
  return (["headline", "summary"] as const)
    .filter((field) => s[field].length > LIMITS[field])
    .map((field) => `${field} is ${s[field].length} characters, more than ${LIMITS[field]}`);
}

/** The summary with its fields clipped to their limits, for a last try. */
export function clipped(s: Summary): Summary {
  return { ...s, headline: clip(s.headline, LIMITS.headline), summary: clip(s.summary, LIMITS.summary) };
}
