import type { DateSpec } from "./dates";

/** A source row from D1. */
export interface SourceRow {
  id: string;
  country: string;
  name: string;
  kind: "rss" | "page" | "api";
  url: string;
  config: string | null;
  language: string | null;
}

/**
 * A field to read: a CSS selector inside the item, `selector@attribute`, or
 * `@attribute` of the item element itself (pages); a field name (feeds); a
 * dotted path or `{path}` template (APIs).
 */
export type FieldSpec = string;

export interface DateFieldSpec extends DateSpec {
  /** Pages: CSS selector inside the item. */
  selector?: string;
  /** Pages: read this attribute instead of the text, e.g. "datetime". */
  attr?: string;
  /** Feeds: element name holding the date, e.g. "valueDate". APIs: path(s), first non-empty wins. */
  field?: string | string[];
  /** Take the date from the item link with this regular expression (one group: yyyymmdd). */
  fromLink?: string;
}

/** The `config` column of a source (docs/sources.md). */
export interface SourceConfig {
  seed?: boolean;
  /** Keep only items whose field matches (regular expressions; "(?i)" at the start ignores case). */
  match?: Partial<Record<"title" | "category", string>>;
  exclude?: Partial<Record<"title" | "category", string>>;
  /** Character set when the server does not say it, e.g. "iso-8859-1". */
  encoding?: string;
  /** false: never open item pages (robots.txt forbids it); use the list text only. */
  itemPages?: boolean;
  /** CSS selector of the main text on item pages; default: main, then article. */
  textSelector?: string;
  /** A new stage of the same item (same link, new date) counts as a new item. */
  newStageIsNewItem?: boolean;
  /** Seconds between our requests to this site (from its robots.txt). */
  crawlDelaySeconds?: number;
  /** Days to keep the extracted text (default 30). */
  textDays?: number;

  // Pages
  item?: string;
  link?: FieldSpec;
  title?: FieldSpec;
  summary?: FieldSpec;
  image?: FieldSpec;
  category?: FieldSpec;
  date?: string | DateFieldSpec;

  // APIs
  items?: string;
  itemRoot?: string;
  keep?: Record<string, string>;
  text?: string;
  /** Extra part of the stored URL, so one link can hold several items (e.g. bill stages). */
  key?: string;
}

/** One item found on a source's list, before it is saved. */
export interface FoundItem {
  url: string;
  title: string;
  publishedAt: string | null;
  dateOnly: boolean;
  text: string | null;
  imageUrl: string | null;
  category: string | null;
}

export function readConfig(source: SourceRow): SourceConfig {
  if (!source.config) return {};
  try {
    const parsed: unknown = JSON.parse(source.config);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? (parsed as SourceConfig) : {};
  } catch {
    return {};
  }
}

/** Normalises the `date` entry of a config. */
export function dateSpec(config: SourceConfig): DateFieldSpec {
  if (typeof config.date === "string") return { selector: config.date, field: config.date };
  return config.date ?? {};
}

/** A regular expression from config; "(?i)" at the start makes it ignore case. */
export function configRegex(source: string): RegExp {
  return source.startsWith("(?i)") ? new RegExp(source.slice(4), "i") : new RegExp(source);
}
