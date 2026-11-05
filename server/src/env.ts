export interface Env {
  DB: D1Database;
  /** Workers AI, for the article summaries (item 7). */
  AI: Ai;
  /**
   * Groq API key, for the Ukrainian and Russian translations (#46). A Worker secret, never in the repo
   * (`npx wrangler secret put GROQ_API_KEY`; locally in `.dev.vars`). Without it
   * Ukrainian and Russian wait in the translation queue, so `?lang=uk` and
   * `?lang=ru` stay empty.
   */
  GROQ_API_KEY?: string;
  /**
   * Z.ai API key, for the German translations (#46; German is off for now: Z.ai blocks Cloudflare Workers). A Worker
   * secret (`npx wrangler secret put ZAI_API_KEY`; locally in `.dev.vars`).
   * Without it German waits in the queue.
   */
  ZAI_API_KEY?: string;
  /**
   * The Google service account that sends push notifications (#62): the whole
   * JSON key file of `fcm-sender` (client_email, private_key, project_id), whose
   * only role is Firebase Cloud Messaging API Admin. A Worker secret, never in
   * the repo (`npx wrangler secret put FCM_SERVICE_ACCOUNT`; locally in
   * `.dev.vars` on one line). Without it no push is sent and each run logs
   * `push skipped`.
   */
  FCM_SERVICE_ACCOUNT?: string;
  /**
   * OpenAI API key, for the AI chat by subscription (#146), the one paid AI.
   * A Worker secret Roman puts in himself, with a monthly spending limit in
   * the OpenAI account (`npx wrangler secret put OPENAI_API_KEY`; locally in
   * `.dev.vars`). Without it `POST /v1/chat` answers 503.
   */
  OPENAI_API_KEY?: string;
  /**
   * The team's key for Sandbox purchases in the AI chat (#146, Roman, 28 Oct),
   * which only Roman's local builds have. They cost nothing (TestFlight, a
   * build run from a Mac), so Sandbox purchases without a team key, App
   * Review's among them, get a small week (`SANDBOX_WEEK_MICROS` in
   * `chat/usage.ts`) and stop at a cap a week (`SANDBOX_WEEKLY_QUESTIONS` in
   * `chat/index.ts`); a request that carries this key or
   * [CHAT_SANDBOX_KEY_TESTFLIGHT] as `X-Chat-Sandbox-Key` gets the App
   * Store's week and is not held to the cap.
   * A Worker secret Roman puts in himself (`npx wrangler secret put
   * CHAT_SANDBOX_KEY`; locally in `.dev.vars`).
   */
  CHAT_SANDBOX_KEY?: string;
  /**
   * The same for the team's TestFlight builds (#146, Roman and Yurii, 29 Oct):
   * the TestFlight workflow builds it into `testflight` builds, never `store`
   * ones, from the GitHub secret of the same name. Yurii puts the one value
   * into both himself. Without it TestFlight builds' Sandbox purchases get
   * the small week and share that cap.
   */
  CHAT_SANDBOX_KEY_TESTFLIGHT?: string;
  /**
   * Cloudflare's rate limiter for the API (S2 of the release audit, 4 Nov):
   * how many requests one address may make a minute in one Cloudflare
   * location (`ratelimits` in wrangler.jsonc). A flood is answered 429 before
   * it reads D1, whose 5 million rows a day the fetcher needs too. Absent in a
   * local run without it: nothing is limited.
   */
  API_LIMIT?: RateLimit;
}
