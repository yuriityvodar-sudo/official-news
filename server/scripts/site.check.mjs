// Guards for the website Worker (#88), `node --test` in `npm test`: it binds
// only the api's database, has no AI binding, cron, secret or other binding,
// and its code never runs SQL or a request of its own. What it shows and
// writes comes only through the API's handler (src/api), which the site calls
// for GET routes only; D1 has no read-only binding, so this is where "reads
// only" is kept.
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, test } from "node:test";

const server = fileURLToPath(new URL("../", import.meta.url));

/** JSON with // and /* comments, as wrangler reads it (strings may hold "//"). */
export function parseJsonc(text) {
  let out = "";
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '"') {
      const end = /"(?:[^"\\]|\\.)*"/y;
      end.lastIndex = i;
      const m = end.exec(text);
      out += m[0];
      i += m[0].length - 1;
    } else if (c === "/" && text[i + 1] === "/") {
      while (i < text.length && text[i] !== "\n") i++;
      out += "\n";
    } else if (c === "/" && text[i + 1] === "*") {
      i = text.indexOf("*/", i + 2) + 1;
    } else out += c;
  }
  return JSON.parse(out.replace(/,(\s*[}\]])/g, "$1"));
}

const config = (name) => parseJsonc(readFileSync(join(server, name), "utf8"));

/** Everything wrangler.site.jsonc may hold. A binding of any other kind (ai, kv, r2, services, queues, …) or triggers fails. */
const ALLOWED = new Set(["$schema", "name", "main", "compatibility_date", "account_id", "workers_dev", "preview_urls", "routes", "d1_databases", "vars", "cache", "observability"]);

describe("wrangler.site.jsonc", () => {
  const site = config("wrangler.site.jsonc");
  const api = config("wrangler.jsonc");

  test("has no AI binding, no cron and no binding but the database", () => {
    assert.deepEqual(
      Object.keys(site).filter((key) => !ALLOWED.has(key)),
      [],
    );
    assert.deepEqual(Object.keys(site.vars), ["SITE_ORIGIN"]);
    assert.match(site.vars.SITE_ORIGIN, /^https:\/\/[^/]+$/);
  });

  test("serves the domain only, the same as SITE_ORIGIN, with no workers.dev copy", () => {
    assert.equal(site.workers_dev, false);
    assert.deepEqual(site.routes, [{ pattern: new URL(site.vars.SITE_ORIGIN).host, custom_domain: true }]);
  });

  test("binds the api's own database as DB, without its migrations", () => {
    assert.equal(site.d1_databases.length, 1);
    const [db] = site.d1_databases;
    const [apiDb] = api.d1_databases;
    assert.deepEqual(db, { binding: "DB", database_name: apiDb.database_name, database_id: apiDb.database_id });
  });

  test("is the Worker `site` on the same account, with no preview URLs", () => {
    assert.equal(site.name, "site");
    assert.equal(site.main, "src/site/index.ts");
    assert.equal(site.account_id, api.account_id);
    assert.equal(site.compatibility_date, api.compatibility_date);
    assert.equal(site.preview_urls, false);
  });
});

describe("src/site", () => {
  const dir = join(server, "src/site");
  const files = readdirSync(dir, { recursive: true }).filter((f) => f.endsWith(".ts"));

  test("runs no SQL and no request of its own", () => {
    assert.ok(files.length > 5);
    for (const file of files) {
      const code = readFileSync(join(dir, file), "utf8");
      // A statement on the database (env.DB.prepare, .batch, .exec), or a request to anywhere
      // (the Worker's own `fetch(request: Request…` handler in index.ts is not one).
      for (const call of [/\.DB\./, /\.prepare\(/, /(?<![\w.])fetch\((?!request: Request)/, /(?:globalThis|self)\.fetch\b/]) {
        assert.ok(!call.test(code), `src/site/${file} matches ${call}: the site reads only through handleApi (src/api)`);
      }
    }
  });
});
