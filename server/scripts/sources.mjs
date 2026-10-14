// Item 5: turns docs/sources.csv into SQL that adds or updates rows in the
// `sources` table. Status and check times are left alone: the fetcher and the
// health checks own them. Run with `npm run sources:local` or `sources:remote`.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

/** Columns of docs/sources.csv, in order. `evidence` is for people only and is not loaded. */
export const COLUMNS = ["id", "country", "name", "kind", "url", "language", "verified_by", "verified_at", "licence", "config", "evidence"];

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

/** Reads and checks every row; throws one error listing all problems. */
export function toSources(text) {
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
    seen.add(s.id);
    if (!s.name) fail("name is empty");
    if (!KINDS.has(s.kind)) fail(`kind must be one of ${[...KINDS].join(", ")}`);
    if (!/^https?:\/\/[^\s]+$/.test(s.url)) fail("url must start with http:// or https://");
    if (!/^[a-z]{2}$/.test(s.language)) fail("language must be a 2-letter code such as en");
    if (!VERIFIED_BY.has(s.verified_by)) fail(`verified_by must be one of ${[...VERIFIED_BY].join(", ")}`);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(s.verified_at)) fail("verified_at must be a date such as 2026-10-14");
    if (!s.evidence) fail("evidence is empty: say how the source was verified as official");
    if (s.config) {
      try {
        const config = JSON.parse(s.config);
        if (typeof config !== "object" || config === null || Array.isArray(config)) fail("config must be a JSON object");
      } catch {
        fail("config is not valid JSON");
      }
    }
    return s;
  });
  if (problems.length) throw new Error(`docs/sources.csv has problems:\n${problems.join("\n")}`);
  return sources;
}

const sqlValue = (v) => (v === "" ? "NULL" : `'${v.replaceAll("'", "''")}'`);

/** One upsert per source, so running it again is safe. Seed rows are never overwritten. */
export function toSql(sources) {
  return sources
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
}

export const csvPath = fileURLToPath(new URL("../../docs/sources.csv", import.meta.url));

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    process.stdout.write(toSql(toSources(readFileSync(csvPath, "utf8"))));
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
}
