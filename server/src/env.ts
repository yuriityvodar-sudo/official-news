export interface Env {
  DB: D1Database;
  /** Workers AI, for the article summaries (item 7). */
  AI: Ai;
  /**
   * Groq API key, for the translations (#46). A Worker secret, never in the repo
   * (`npx wrangler secret put GROQ_API_KEY`; locally in `.dev.vars`). Without it
   * the translator skips its runs and the API returns English.
   */
  GROQ_API_KEY?: string;
}
