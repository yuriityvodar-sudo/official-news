// Item 5: turns docs/sources.csv into SQL that adds or updates rows in the
// `sources` table, and docs/outlets.csv (#230) rows in `outlets`. Status and
// check times are left alone: the fetcher and the health checks own them.
// Each source's names in the app's other languages (#76) come from
// docs/source-names.csv and go into its config as `names`.
// Run with `npm run sources:local` or `sources:remote`.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

/** Columns of docs/sources.csv, in order. `evidence` is for people only and is not loaded. */
export const COLUMNS = ["id", "country", "name", "kind", "url", "language", "verified_by", "verified_at", "licence", "config", "evidence"];

/** Columns of docs/source-names.csv, in order. */
export const NAME_COLUMNS = ["id", "lang", "name"];

/** Columns of docs/outlets.csv (#230), in order. `note` is for people only and is not loaded. */
export const OUTLET_COLUMNS = ["id", "country", "name", "url", "site", "language", "config", "checked_at", "note"];

/**
 * The languages a source can be named in: the API's languages other than
 * English (LANGS in server/src/translator/languages.ts; a check keeps them equal).
 */
export const NAME_LANGS = ["uk", "ru", "es", "de"];

const KINDS = new Set(["rss", "page", "api"]);
const VERIFIED_BY = new Set(["domain", "portal", "wikidata"]);

/** Parses CSV text (RFC 4180: quoted fields may hold commas, quotes as "", and line breaks). */
export function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = "";
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') {
        field += '"';
        i++;
      } else if (c === '"') {
        quoted = false;
      } else {
        field += c;
      }
    } else if (c === '"') {
      quoted = true;
    } else if (c === ",") {
      row.push(field);
      field = "";
    } else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      row.push(field);
      if (row.some((f) => f !== "")) rows.push(row);
      row = [];
      field = "";
    } else {
      field += c;
    }
  }
  row.push(field);
  if (row.some((f) => f !== "")) rows.push(row);
  return rows;
}

/** Source ids of the Kickoff seed (server/migrations/0002_seed.sql); a CSV row may not reuse one. */
export function seedIds(seedSql) {
  return new Set([...seedSql.matchAll(/INSERT INTO sources \([^)]*\) VALUES \('([^']+)'/g)].map((m) => m[1]));
}

/** Reads and checks every row; throws one error listing all problems. */
export function toSources(text, { reserved = new Set() } = {}) {
  const [header, ...rows] = parseCsv(text);
  if (header?.join(",") !== COLUMNS.join(",")) {
    throw new Error(`sources.csv header must be: ${COLUMNS.join(",")}`);
  }
  const problems = [];
  const seen = new Set();
  const sources = rows.map((cells, index) => {
    const line = index + 2;
    const s = Object.fromEntries(COLUMNS.map((name, i) => [name, (cells[i] ?? "").trim()]));
    const fail = (message) => problems.push(`line ${line} (${s.id || "no id"}): ${message}`);
    if (cells.length !== COLUMNS.length) fail(`has ${cells.length} fields, expected ${COLUMNS.length}`);
    if (!/^[A-Z]{2}$/.test(s.country)) fail("country must be a 2-letter code such as DE or EU");
    if (!s.id.startsWith(`${s.country.toLowerCase()}-`) || !/^[a-z]{2}-[a-z0-9-]+$/.test(s.id)) {
      fail("id must look like <country>-<short-name>, lower case");
    }
    if (seen.has(s.id)) fail("id is used twice");
    if (reserved.has(s.id)) fail("id belongs to a Kickoff seed source; choose another");
    seen.add(s.id);
    if (!s.name) fail("name is empty");
    if (!KINDS.has(s.kind)) fail(`kind must be one of ${[...KINDS].join(", ")}`);
    // Plain http can be altered on the way, and we show the text as official.
    if (!/^https:\/\/[^\s]+$/.test(s.url)) fail("url must start with https://");
    if (!/^[a-z]{2}$/.test(s.language)) fail("language must be a 2-letter code such as en");
    if (!VERIFIED_BY.has(s.verified_by)) fail(`verified_by must be one of ${[...VERIFIED_BY].join(", ")}`);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(s.verified_at)) fail("verified_at must be a date such as 2026-10-14");
    if (!s.evidence) fail("evidence is empty: say how the source was verified as official");
    if (s.config) {
      try {
        const config = JSON.parse(s.config);
        if (typeof config !== "object" || config === null || Array.isArray(config)) fail("config must be a JSON object");
        else if ("names" in config) fail("config.names comes from docs/source-names.csv; put the names there");
      } catch {
        fail("config is not valid JSON");
      }
    }
    return s;
  });
  if (problems.length) throw new Error(`docs/sources.csv has problems:\n${problems.join("\n")}`);
  return sources;
}

/**
 * Reads docs/source-names.csv (#76): each source's name in the languages of
 * NAME_LANGS, as a Map from source id to `{ uk: "…", ru: "…", … }`. Every id
 * must be a source of `sources` (from toSources), and a source has at most one
 * name per language. Throws one error listing all problems.
 */
export function toNames(text, sources) {
  const [header, ...rows] = parseCsv(text);
  if (header?.join(",") !== NAME_COLUMNS.join(",")) {
    throw new Error(`source-names.csv header must be: ${NAME_COLUMNS.join(",")}`);
  }
  const ids = new Set(sources.map((s) => s.id));
  const names = new Map();
  const problems = [];
  rows.forEach((cells, index) => {
    const n = Object.fromEntries(NAME_COLUMNS.map((column, i) => [column, (cells[i] ?? "").trim()]));
    const before = problems.length;
    const fail = (message) => problems.push(`line ${index + 2} (${n.id || "no id"}, ${n.lang || "no lang"}): ${message}`);
    if (cells.length !== NAME_COLUMNS.length) fail(`has ${cells.length} fields, expected ${NAME_COLUMNS.length}`);
    if (!ids.has(n.id)) fail("id is not a source in docs/sources.csv");
    if (!NAME_LANGS.includes(n.lang)) fail(`lang must be one of ${NAME_LANGS.join(", ")} (the English name is the one in docs/sources.csv)`);
    if (!n.name) fail("name is empty");
    if (names.get(n.id)?.[n.lang] !== undefined) fail("this source has a name in this language already");
    if (problems.length === before) names.set(n.id, { ...names.get(n.id), [n.lang]: n.name });
  });
  if (problems.length) throw new Error(`docs/source-names.csv has problems:\n${problems.join("\n")}`);
  return names;
}

/**
 * The sources with their names (from toNames) in `config.names`, which the API
 * reads for `?lang=` (docs/contract.md). A source without names keeps its
 * config exactly as written in docs/sources.csv.
 */
export function withNames(sources, names) {
  return sources.map((s) => {
    const own = names.get(s.id);
    if (!own) return s;
    // In NAME_LANGS order, so the stored JSON does not depend on the order of the rows.
    const ordered = Object.fromEntries(NAME_LANGS.filter((lang) => lang in own).map((lang) => [lang, own[lang]]));
    return { ...s, config: JSON.stringify({ ...(s.config ? JSON.parse(s.config) : {}), names: ordered }) };
  });
}

const sqlValue = (v) => (v === "" ? "NULL" : `'${v.replaceAll("'", "''")}'`);

/**
 * One upsert per source, so running it again is safe. Seed rows are never
 * overwritten. Sources no longer in the CSV are set to `blocked`, so the
 * fetcher stops reading them (rows stay, because articles point to them).
 */
export function toSql(sources) {
  const ids = sources.map((s) => sqlValue(s.id)).join(", ");
  const upserts = sources
    .map(
      (s) =>
        "INSERT INTO sources (id, country, name, kind, url, config, language, verified_by, verified_at, licence) VALUES (" +
        [s.id, s.country, s.name, s.kind, s.url, s.config, s.language, s.verified_by, s.verified_at, s.licence].map(sqlValue).join(", ") +
        ") ON CONFLICT (id) DO UPDATE SET country = excluded.country, name = excluded.name, kind = excluded.kind, url = excluded.url, " +
        "config = excluded.config, language = excluded.language, verified_by = excluded.verified_by, verified_at = excluded.verified_at, licence = excluded.licence " +
        // Kickoff seed rows keep their data even if a CSV row reuses their id.
        "WHERE json_extract(sources.config, '$.seed') IS NOT 1;\n",
    )
    .join("");
  return (
    upserts +
    `UPDATE sources SET status = 'blocked' WHERE id NOT IN (${ids || "''"}) AND status != 'blocked' ` +
    "AND (config IS NULL OR json_extract(config, '$.seed') IS NOT 1);\n"
  );
}

/**
 * Reads and checks docs/outlets.csv (#230): the news outlets whose headlines
 * and links the fetcher keeps, never their text. An id looks like a source's
 * and is never one of `sourceIds`, so a check's log names one or the other.
 * Throws one error listing all problems.
 */
export function toOutlets(text, { sourceIds = new Set() } = {}) {
  const [header, ...rows] = parseCsv(text);
  if (header?.join(",") !== OUTLET_COLUMNS.join(",")) {
    throw new Error(`outlets.csv header must be: ${OUTLET_COLUMNS.join(",")}`);
  }
  const problems = [];
  const seen = new Set();
  const outlets = rows.map((cells, index) => {
    const o = Object.fromEntries(OUTLET_COLUMNS.map((name, i) => [name, (cells[i] ?? "").trim()]));
    const fail = (message) => problems.push(`line ${index + 2} (${o.id || "no id"}): ${message}`);
    if (cells.length !== OUTLET_COLUMNS.length) fail(`has ${cells.length} fields, expected ${OUTLET_COLUMNS.length}`);
    if (!/^[A-Z]{2}$/.test(o.country)) fail("country must be a 2-letter code such as DE, or EU or WW");
    if (!o.id.startsWith(`${o.country.toLowerCase()}-`) || !/^[a-z]{2}-[a-z0-9-]+$/.test(o.id)) {
      fail("id must look like <country>-<short-name>, lower case");
    }
    if (seen.has(o.id)) fail("id is used twice");
    if (sourceIds.has(o.id)) fail("id belongs to a source in docs/sources.csv; choose another");
    seen.add(o.id);
    if (!o.name) fail("name is empty");
    if (!/^https:\/\/[^\s]+$/.test(o.url)) fail("url must start with https://");
    // Links are kept only on this site or a subdomain of it (config.allowedHosts for others).
    if (!/^https:\/\/[^\s/]+\/?$/.test(o.site)) fail("site must be the outlet's home page, such as https://www.example.com");
    if (!/^[a-z]{2}$/.test(o.language)) fail("language must be a 2-letter code such as en");
    if (!/^\d{4}-\d{2}-\d{2}$/.test(o.checked_at)) fail("checked_at must be a date such as 2026-11-01");
    if (o.config) {
      try {
        const config = JSON.parse(o.config);
        if (typeof config !== "object" || config === null || Array.isArray(config)) fail("config must be a JSON object");
      } catch {
        fail("config is not valid JSON");
      }
    }
    return o;
  });
  if (problems.length) throw new Error(`docs/outlets.csv has problems:\n${problems.join("\n")}`);
  return outlets;
}

/**
 * One upsert per outlet (#230). An outlet taken out of docs/outlets.csv is set
 * to `blocked`, so the fetcher stops reading it and its headlines are no longer
 * shown; put back, it is read again.
 */
export function outletsSql(outlets) {
  const ids = outlets.map((o) => sqlValue(o.id)).join(", ");
  const upserts = outlets
    .map(
      (o) =>
        "INSERT INTO outlets (id, country, name, url, site, language, config) VALUES (" +
        [o.id, o.country, o.name, o.url, o.site, o.language, o.config].map(sqlValue).join(", ") +
        ") ON CONFLICT (id) DO UPDATE SET country = excluded.country, name = excluded.name, url = excluded.url, site = excluded.site, " +
        "language = excluded.language, config = excluded.config, status = CASE WHEN outlets.status = 'blocked' THEN 'active' ELSE outlets.status END;\n",
    )
    .join("");
  return upserts + `UPDATE outlets SET status = 'blocked' WHERE id NOT IN (${ids || "''"}) AND status != 'blocked';\n`;
}

export const csvPath = fileURLToPath(new URL("../../docs/sources.csv", import.meta.url));
export const namesPath = fileURLToPath(new URL("../../docs/source-names.csv", import.meta.url));
export const seedPath = fileURLToPath(new URL("../migrations/0002_seed.sql", import.meta.url));
export const outletsPath = fileURLToPath(new URL("../../docs/outlets.csv", import.meta.url));

/** The sources of docs/sources.csv with their names from docs/source-names.csv, checked: what the deploy loads. */
export function readSources() {
  const reserved = seedIds(readFileSync(seedPath, "utf8"));
  const sources = toSources(readFileSync(csvPath, "utf8"), { reserved });
  return withNames(sources, toNames(readFileSync(namesPath, "utf8"), sources));
}

/** The outlets of docs/outlets.csv, checked against the ids of `sources` (from readSources): what the deploy loads. */
export function readOutlets(sources) {
  return toOutlets(readFileSync(outletsPath, "utf8"), { sourceIds: new Set(sources.map((s) => s.id)) });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const sources = readSources();
    process.stdout.write(toSql(sources) + outletsSql(readOutlets(sources)));
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
}
