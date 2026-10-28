import type { Lang } from "../translator/languages";
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
  last_checked_at: string | null;
  list_etag: string | null;
  list_last_modified: string | null;
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

/**
 * One step towards an item's whole text when its item page does not hold it
 * (#71): a JSON data endpoint, or a page that links to the text.
 */
export interface FullTextStep {
  /** Regular expression matched on the item link (first step) or the previous step's result; its groups fill `{1}`, `{2}`… in `url`. */
  from?: string;
  /** What to read; default `{0}`, the whole match (the previous step's result as it is). */
  url?: string;
  /**
   * The answer is JSON: dotted path to the result (HTML or plain text in the
   * last step). A list of paths joins what each finds, in order, in the last
   * step (the first found is used before it); `*` goes through a list, and
   * after `*.` a `{path}` template is filled from each entry.
   */
  json?: string | string[];
  /** The answer is a page: the result is the link of the first element matching this selector (`selector@attr`, default `href`). */
  link?: string;
  /** Character set of the answer when the server does not say it, e.g. "iso-8859-1". */
  encoding?: string;
}

/** The item fields `match` and `exclude` test. */
export type FilterField = "title" | "category" | "url";

/** The `config` column of a source (docs/sources.md). */
export interface SourceConfig {
  seed?: boolean;
  /**
   * Keep only items whose field matches (regular expressions; "(?i)" at the
   * start ignores case). A feed whose title comes from another field (`title`)
   * also passes `match.title` on its own headline.
   */
  match?: Partial<Record<FilterField, string>>;
  exclude?: Partial<Record<FilterField, string>>;
  /** Character set when the server does not say it, e.g. "iso-8859-1". */
  encoding?: string;
  /** false: never open item pages (robots.txt forbids it, or they are built by JavaScript); `fullText` is still read when set. */
  itemPages?: boolean;
  /**
   * false: never take og:image/twitter:image from item pages (the site's only
   * picture is its emblem, which its terms forbid with adaptations: the ILO).
   * The item page is then opened only for a teaser's text, never for a picture.
   */
  pageImage?: boolean;
  /** CSS selector of the main text on item pages (and on the last page of `fullText`); default: main, then article, then body. */
  textSelector?: string;
  /**
   * Where the whole text is when the item page does not have it (#71). Read
   * instead of the item page, for items whose list text is a teaser; the last
   * step's answer is the text (its `json` value, or the page's main text).
   */
  fullText?: FullTextStep | FullTextStep[];
  /** A new stage of the same item (same link, new date) counts as a new item. */
  newStageIsNewItem?: boolean;
  /** Seconds between our requests to this site (from its robots.txt). */
  crawlDelaySeconds?: number;
  /** Send back the list's ETag / Last-Modified; a 304 answer means nothing new (saves big downloads). */
  conditionalGet?: boolean;
  /** Other hosts whose links count as this source's own (e.g. the Chamber's site for its open-data API). */
  allowedHosts?: string[];
  /** Days to keep the extracted text (default 30). */
  textDays?: number;
  /**
   * The source's name in the app's other languages (#76), from
   * docs/source-names.csv (never written in docs/sources.csv). Not read by the
   * fetcher: the API sends it as `source.name` for `?lang=`.
   */
  names?: Partial<Record<Lang, string>>;

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
  /** Feeds: the item's own `<title>`, when the config takes the title from another field. */
  headline?: string;
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
