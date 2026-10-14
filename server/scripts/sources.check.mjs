// Tests for scripts/sources.mjs. They run in Node (`node --test`), not in the
// Workers runtime that Vitest uses, because they read docs/sources.csv from disk.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, test } from "node:test";

import { COLUMNS, csvPath, parseCsv, toSources, toSql } from "./sources.mjs";

const header = COLUMNS.join(",");
const row = (overrides = {}) => {
  const s = {
    id: "de-cabinet",
    country: "DE",
    name: "Federal Government",
    kind: "rss",
    url: "https://www.bundesregierung.de/feed",
    language: "de",
    verified_by: "domain",
    verified_at: "2026-10-14",
    licence: "",
    config: "",
    evidence: "bundesregierung.de, linked from bund.de",
    ...overrides,
  };
  return COLUMNS.map((c) => (/[",\n]/.test(s[c]) ? `"${s[c].replaceAll('"', '""')}"` : s[c])).join(",");
};

describe("parseCsv", () => {
  test("handles quoted commas, quotes and line breaks", () => {
    assert.deepEqual(parseCsv('a,"b, c","say ""hi""","x\ny"\r\n1,2,3,4\n'), [
      ["a", "b, c", 'say "hi"', "x\ny"],
      ["1", "2", "3", "4"],
    ]);
  });
});

describe("toSources", () => {
  test("reads a valid row", () => {
    const [s] = toSources(`${header}\n${row({ config: '{"item":"article"}' })}\n`);
    assert.equal(s.id, "de-cabinet");
    assert.equal(s.config, '{"item":"article"}');
  });

  test("lists every problem at once", () => {
    const csv = `${header}\n${row({ kind: "feed", verified_by: "trust me" })}\n${row()}\n${row()}\n`;
    assert.throws(() => toSources(csv), /kind must be[\s\S]*verified_by must be[\s\S]*id is used twice/);
  });

  test("rejects an id that does not start with the country", () => {
    assert.throws(() => toSources(`${header}\n${row({ id: "fr-cabinet" })}\n`), /id must look like/);
  });

  test("rejects config that is not a JSON object", () => {
    assert.throws(() => toSources(`${header}\n${row({ config: "[1]" })}\n`), /config must be a JSON object/);
  });
});

describe("toSql", () => {
  test("escapes quotes, writes NULL for empty values, leaves status and seed rows alone", () => {
    const sql = toSql(toSources(`${header}\n${row({ name: "Prime Minister's Office" })}\n`));
    assert.match(sql, /'Prime Minister''s Office'/);
    assert.match(sql, /'de', 'domain', '2026-10-14', NULL\)/);
    assert.match(sql, /ON CONFLICT \(id\) DO UPDATE/);
    assert.doesNotMatch(sql, /status/);
    assert.match(sql, /WHERE json_extract\(sources.config, '\$.seed'\) IS NOT 1;/);
  });
});

test("docs/sources.csv is valid", () => {
  assert.ok(toSources(readFileSync(csvPath, "utf8")).length > 0);
});
