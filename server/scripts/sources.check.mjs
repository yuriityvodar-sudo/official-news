// Tests for scripts/sources.mjs. They run in Node (`node --test`), not in the
// Workers runtime that Vitest uses, because they read docs/sources.csv from disk.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, test } from "node:test";

import { COLUMNS, csvPath, parseCsv, seedIds, seedPath, toSources, toSql } from "./sources.mjs";

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

  test("requires https", () => {
    assert.throws(() => toSources(`${header}\n${row({ url: "http://kremlin.ru/feed" })}\n`), /url must start with https:\/\//);
  });

  test("rejects an id that belongs to a seed source", () => {
    const reserved = seedIds(readFileSync(seedPath, "utf8"));
    assert.ok(reserved.has("de-federal-government"));
    assert.equal(reserved.size, 20);
    assert.throws(() => toSources(`${header}\n${row({ id: "de-federal-government" })}\n`, { reserved }), /belongs to a Kickoff seed source/);
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
    assert.doesNotMatch(sql.split("\n")[0], /status/); // the upsert never changes status
    assert.match(sql, /WHERE json_extract\(sources.config, '\$.seed'\) IS NOT 1;/);
    assert.match(sql, /UPDATE sources SET status = 'blocked' WHERE id NOT IN \('de-cabinet'\) AND status != 'blocked'/);
  });
});

test("docs/sources.csv is valid", () => {
  const reserved = seedIds(readFileSync(seedPath, "utf8"));
  assert.ok(toSources(readFileSync(csvPath, "utf8"), { reserved }).length > 0);
});

test("the app has a name for every country and language in docs/sources.csv", () => {
  // Cards show "source · country" and "translated from <language>"; a missing name shows the bare code.
  const names = (file) => new Set([...readFileSync(new URL(`../../app/lib/core/${file}`, import.meta.url), "utf8").matchAll(/^\s*'([A-Za-z]{2})'\s*(?::|=>)/gm)].map((m) => m[1]));
  const countries = names("countries.dart");
  const languages = names("languages.dart");
  const sources = toSources(readFileSync(csvPath, "utf8"));
  assert.deepEqual([...new Set(sources.map((s) => s.country))].filter((c) => !countries.has(c)), [], "add these to app/lib/core/countries.dart");
  assert.deepEqual([...new Set(sources.map((s) => s.language))].filter((l) => !languages.has(l)), [], "add these to app/lib/core/languages.dart");
});
