import type { D1Migration } from "cloudflare:test";
import type { Env as WorkerEnv } from "../src/env";

// What tests see through `env` and `exports` from "cloudflare:workers".
declare global {
  namespace Cloudflare {
    interface Env extends WorkerEnv {
      TEST_MIGRATIONS: D1Migration[];
      TEST_CRONS: string[];
    }
    interface GlobalProps {
      mainModule: typeof import("../src/index");
    }
  }
}
