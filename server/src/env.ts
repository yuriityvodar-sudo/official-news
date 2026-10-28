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
}
