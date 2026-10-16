import { readFileSync } from "node:fs";
import path from "node:path";
import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";
import { unstable_readConfig } from "wrangler";
import { csvPath, parseCsv } from "./scripts/sources.mjs";

// Tests run inside the Workers runtime with a local D1 database. The
// migrations (schema and seed) are read here and applied in test/setup.ts.
export default defineConfig(async () => {
  const migrations = await readD1Migrations(path.join(import.meta.dirname, "migrations"));
  // The cron triggers as deployed, so a test can check that src/index.ts knows each one.
  const crons = unstable_readConfig({ config: path.join(import.meta.dirname, "wrangler.jsonc") }).triggers.crons ?? [];
  // The countries of docs/sources.csv, so a test can check that the API has a name for each one.
  const sourceCountries = [...new Set(parseCsv(readFileSync(csvPath, "utf8")).slice(1).map((row: string[]) => row[1]))];
  return {
    plugins: [
      cloudflareTest({
        wrangler: { configPath: "./wrangler.jsonc" },
        // Workers AI only runs remotely; tests pass their own summarize function instead.
        remoteBindings: false,
        miniflare: { bindings: { TEST_MIGRATIONS: migrations, TEST_CRONS: crons, TEST_SOURCE_COUNTRIES: sourceCountries } },
      }),
    ],
    test: {
      setupFiles: ["./test/setup.ts"],
      // The Workers runtime can't read Vitest's on-disk module cache.
      fsModuleCache: false,
    },
  };
});
