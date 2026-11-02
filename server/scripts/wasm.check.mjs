// The committed WebAssembly of the stories' grouping is its source's build (#230).
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { WASM_FILE, buildWasm } from "./wasm.mjs";

test("src/stories/group.wasm is the build of assembly/stories.ts", async () => {
  const out = path.join(mkdtempSync(path.join(tmpdir(), "stories-wasm-")), "group.wasm");
  await buildWasm(out);
  assert.ok(readFileSync(out).equals(readFileSync(WASM_FILE)), "run `npm run build:wasm` in server/ and commit src/stories/group.wasm");
});
