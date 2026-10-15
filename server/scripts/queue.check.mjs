// Tests for the command line of scripts/queue.mjs (`node --test`). What each
// statement does to the database is tested in the Worker tests
// (test/queue-script.test.ts), against the real schema.
import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { parse } from "./queue.mjs";

describe("queue.mjs", () => {
  test("runs one wrangler d1 execute on the chosen database, local or remote", () => {
    const plan = parse(["list", "--state", "failed", "--lang", "es", "--remote"]);
    assert.equal(plan.reads, true);
    assert.deepEqual(plan.wrangler.slice(0, 8), ["wrangler", "d1", "execute", "official-news", "--remote", "--json", "--yes", "--command"]);
    assert.match(plan.wrangler[8], /WHERE state = 'failed' AND lang = 'es'/);
    assert.equal(parse(["status", "--local", "--db", "official-news-preview"]).wrangler[3], "official-news-preview");
    assert.equal(parse(["status", "--local"]).wrangler[4], "--local");
  });

  test("enable also queues the backlog, in one command", () => {
    const plan = parse(["enable", "de", "--remote"]);
    assert.equal(plan.reads, false);
    assert.equal(plan.statements.length, 2);
    assert.equal(plan.wrangler.at(-1), plan.statements.join(";\n"));
  });

  for (const [argv, message] of [
    [["status"], /choose --local or --remote/],
    [["status", "--local", "--remote"], /choose --local or --remote/],
    [["pause", "pl", "--remote"], /language must be one of: uk, ru, es, de/],
    [["list", "--state", "done", "--local"], /state must be one of/],
    [["requeue", "x'; DROP TABLE articles; --", "uk", "--local"], /article id must be/],
    [["requeue", "01JA2B3C", "--local"], /requeue takes 2 arguments/],
    [["list", "--limit", "0", "--local"], /limit must be/],
    [["list", "--lang", "--local"], /--lang needs a value/],
    [["drop", "--local"], /unknown command drop/],
    [["status", "--force", "--local"], /unknown option --force/],
  ]) {
    test(`refuses ${argv.join(" ")} before running anything`, () => {
      assert.throws(() => parse(argv), message);
    });
  }
});
