// Builds the stories' grouping (#230), assembly/stories.ts in AssemblyScript,
// into src/stories/group.wasm: `npm run build:wasm`. The built file is
// committed, so the Worker, its deploy and its tests need no build step;
// scripts/wasm.check.mjs checks that it is this source's build.
import { fileURLToPath } from "node:url";
import asc from "assemblyscript/asc";

export const WASM_FILE = "src/stories/group.wasm";

/** Builds assembly/stories.ts into `outFile`, from server/. */
export async function buildWasm(outFile = WASM_FILE) {
  // No runtime and no imports: the module allocates nothing and never aborts.
  const { error, stderr } = await asc.main(["assembly/stories.ts", "--outFile", outFile, "--optimize", "--runtime", "stub", "--noAssert", "--use", "abort="]);
  if (error) throw new Error(`${error.message}\n${stderr.toString()}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) await buildWasm();
