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
   * Z.ai API key, for the Spanish and German translations (#46). A Worker
   * secret (`npx wrangler secret put ZAI_API_KEY`; locally in `.dev.vars`).
   * Without it Spanish and German wait in the queue.
   */
  ZAI_API_KEY?: string;
}
