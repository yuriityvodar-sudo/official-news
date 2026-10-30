// Tests for scripts/sources.mjs. They run in Node (`node --test`), not in the
// Workers runtime that Vitest uses, because they read docs/sources.csv from disk.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, test } from "node:test";

import {
  COLUMNS,
  NAME_COLUMNS,
  NAME_LANGS,
  csvPath,
  namesPath,
  parseCsv,
  readSources,
  seedIds,
  seedPath,
  toNames,
  toSources,
  toSql,
  withNames,
} from "./sources.mjs";

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

describe("source names (#76)", () => {
  const namesHeader = NAME_COLUMNS.join(",");
  const sources = toSources(`${header}\n${row()}\n${row({ id: "de-gazette", config: '{"item":"article"}' })}\n`);

  test("go into config.names in language order, next to the config of docs/sources.csv", () => {
    const names = toNames(`${namesHeader}\nde-gazette,ru,Вестник\nde-gazette,uk,"Вісник, федеральний"\nde-cabinet,es,Gobierno Federal\n`, sources);
    const [cabinet, gazette] = withNames(sources, names);
    assert.deepEqual(JSON.parse(cabinet.config), { names: { es: "Gobierno Federal" } });
    assert.deepEqual(JSON.parse(gazette.config), { item: "article", names: { uk: "Вісник, федеральний", ru: "Вестник" } });
    assert.equal(gazette.config, '{"item":"article","names":{"uk":"Вісник, федеральний","ru":"Вестник"}}');
    assert.match(toSql([gazette]), /'\{"item":"article","names":\{"uk":"Вісник, федеральний","ru":"Вестник"\}\}'/);
  });

  test("leave a source without names exactly as written", () => {
    const [cabinet, gazette] = withNames(sources, toNames(`${namesHeader}\nde-cabinet,uk,Федеральний уряд\n`, sources));
    assert.equal(gazette, sources[1]);
    assert.equal(gazette.config, '{"item":"article"}');
    assert.deepEqual(JSON.parse(cabinet.config), { names: { uk: "Федеральний уряд" } });
  });

  test("list every problem at once: unknown source, a language we do not serve, an empty name, a language twice", () => {
    const csv = `${namesHeader}\nfr-cabinet,uk,Уряд\nde-cabinet,en,Federal Government\nde-cabinet,pl,Rząd\nde-cabinet,UK,Уряд\nde-cabinet,ru,\nde-cabinet,uk,А\nde-cabinet,uk,Б\nde-cabinet,de,Bundesregierung,extra\n`;
    assert.throws(
      () => toNames(csv, sources),
      (error) => {
        const lines = error.message.split("\n").slice(1);
        assert.deepEqual(lines, [
          "line 2 (fr-cabinet, uk): id is not a source in docs/sources.csv",
          "line 3 (de-cabinet, en): lang must be one of uk, ru, es, de (the English name is the one in docs/sources.csv)",
          "line 4 (de-cabinet, pl): lang must be one of uk, ru, es, de (the English name is the one in docs/sources.csv)",
          "line 5 (de-cabinet, UK): lang must be one of uk, ru, es, de (the English name is the one in docs/sources.csv)",
          "line 6 (de-cabinet, ru): name is empty",
          "line 8 (de-cabinet, uk): this source has a name in this language already",
          "line 9 (de-cabinet, de): has 4 fields, expected 3",
        ]);
        return true;
      },
    );
  });

  test("need the header id,lang,name", () => {
    assert.throws(() => toNames("id,language,name\nde-cabinet,uk,Уряд\n", sources), /source-names.csv header must be: id,lang,name/);
  });

  test("are never written in docs/sources.csv", () => {
    assert.throws(() => toSources(`${header}\n${row({ config: '{"names":{"uk":"Уряд"}}' })}\n`), /config.names comes from docs\/source-names.csv/);
  });

  test("are in the languages the API serves (LANGS)", () => {
    const languages = readFileSync(new URL("../src/translator/languages.ts", import.meta.url), "utf8");
    const langs = /export const LANGS = \[([^\]]*)\]/.exec(languages)?.[1];
    assert.ok(langs, "LANGS not found in server/src/translator/languages.ts");
    assert.deepEqual([...langs.matchAll(/"([a-z]{2})"/g)].map((m) => m[1]), NAME_LANGS);
  });
});

test("docs/sources.csv is valid", () => {
  const reserved = seedIds(readFileSync(seedPath, "utf8"));
  assert.ok(toSources(readFileSync(csvPath, "utf8"), { reserved }).length > 0);
});

test("docs/source-names.csv is valid and names every source in every language", () => {
  const sources = toSources(readFileSync(csvPath, "utf8"));
  const names = toNames(readFileSync(namesPath, "utf8"), sources);
  // A source without a name in a language shows its English name there (the app in Ukrainian reads "UK Government").
  const missing = sources.flatMap((s) => NAME_LANGS.filter((lang) => !names.get(s.id)?.[lang]).map((lang) => `${s.id} ${lang}`));
  assert.deepEqual(missing, [], "add these to docs/source-names.csv");
  // What the deploy loads: every source's config as in docs/sources.csv, plus its names.
  const loaded = readSources();
  for (const [i, s] of sources.entries()) {
    const { names: own, ...config } = JSON.parse(loaded[i].config);
    assert.deepEqual(Object.keys(own), NAME_LANGS, s.id);
    assert.deepEqual(config, s.config ? JSON.parse(s.config) : {}, s.id);
  }
});

test("the app has a name for every country and language in docs/sources.csv", () => {
  // Cards show "source · country" and "translated from <language>"; a missing name shows the bare code.
  const names = (file) => new Set([...readFileSync(new URL(`../../app/lib/core/${file}`, import.meta.url), "utf8").matchAll(/^\s*'([A-Za-z]{2})'\s*(?::|=>)/gm)].map((m) => m[1]));
  const countries = names("countries.dart");
  const languages = names("languages.dart");
  // A hidden source's articles never reach the app (#230): its country gets a name when it is shown.
  const sources = toSources(readFileSync(csvPath, "utf8")).filter((s) => !(s.config && JSON.parse(s.config).hidden));
  assert.deepEqual([...new Set(sources.map((s) => s.country))].filter((c) => !countries.has(c)), [], "add these to app/lib/core/countries.dart");
  assert.deepEqual([...new Set(sources.map((s) => s.language))].filter((l) => !languages.has(l)), [], "add these to app/lib/core/languages.dart");
});
