// The API's rate limit in wrangler.jsonc is the one src/api/index.ts names
// (API_LIMIT), so a change to one is never forgotten in the other (S2 of the
// release audit, 4 Nov).
import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

test("wrangler.jsonc's ratelimits match API_LIMIT", () => {
  const config = readFileSync(new URL("../wrangler.jsonc", import.meta.url), "utf8");
  const source = readFileSync(new URL("../src/api/index.ts", import.meta.url), "utf8");
  const limit = /export const API_LIMIT = (\d+);/.exec(source)?.[1];
  assert.ok(limit, "API_LIMIT in src/api/index.ts");
  assert.match(config, new RegExp(`"name": "API_LIMIT", "namespace_id": "1001", "simple": \\{ "limit": ${limit}, "period": 60 \\}`));
  assert.match(config, /"pattern": "api\.outernews\.app", "custom_domain": true/);
});
