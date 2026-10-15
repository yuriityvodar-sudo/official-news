import type { Env } from "../env";
import { toStoredTime } from "../fetcher/text";
import { type ArticleInput, SYSTEM_PROMPT, userMessage } from "./prompt";
import { SUMMARY_SCHEMA, type Summary, parseJson, toSummary } from "./schema";

/** The Workers AI model that writes the summaries (Roman's choice, docs/decisions.md). */
export const MODEL = "@cf/zai-org/glm-4.7-flash";

/** An article gets this many tries with an unusable answer, then it stays hidden. */
export const MAX_ATTEMPTS = 3;

const MAX_COMPLETION_TOKENS = 1500;

/** A claim older than this is from a run that was cut off, so its articles are free again. */
export const CLAIM_MINUTES = 10;

interface ArticleRow {
  id: string;
  original_title: string;
  text: string | null;
  original_language: string | null;
  source_name: string;
  country: string;
}

/** What happened to one article in a run, for the log. */
export interface SummaryResult {
  articleId: string;
  ok: boolean;
  isNews?: boolean;
  error?: string;
}

/** The model answered, but not with something we can store. Counts as a failed attempt. */
class UnusableAnswer extends Error {}

/** The one call to the model; tests pass their own. */
export type Summarize = (article: ArticleInput) => Promise<string>;

function workersAi(env: Env): Summarize {
  return async (article) => {
    const output = await env.AI.run(MODEL, {
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: userMessage(article) },
      ],
      response_format: { type: "json_schema", json_schema: { name: "article_summary", schema: SUMMARY_SCHEMA, strict: true } },
      // A summary needs no long reasoning; turning it off saves most of the output tokens.
      chat_template_kwargs: { enable_thinking: false },
      max_completion_tokens: MAX_COMPLETION_TOKENS,
      temperature: 0.2,
    });
    const choice = output.choices[0];
    if (choice?.finish_reason === "length") throw new UnusableAnswer("the answer was cut off at the token limit");
    const content = choice?.message?.content;
    if (typeof content !== "string" || !content.trim()) throw new UnusableAnswer("the answer was empty");
    return content;
  };
}

function store(env: Env, id: string, s: Summary, now: string): D1PreparedStatement {
  return env.DB.prepare(
    // feed_seq and added_at: the article's place in the feed and when it got it, given in
    // this same statement when it becomes visible and never changed afterwards. D1 runs one
    // statement at a time, so MAX + 1 cannot be handed out twice (a unique index also
    // guards it). `WHERE feed_seq IS NOT NULL` lets SQLite read MAX from that partial
    // index (1 row) instead of scanning the table. Inside an UPDATE the columns still hold
    // their old values, so `feed_seq IS NULL` means "not numbered before this statement".
    `UPDATE articles SET headline = ?, short_summary = ?, summary = ?, decision_type = ?, topics = ?, tags = ?,
            importance = ?, is_news = ?, summarized_at = ?, model = ?,
            feed_seq = CASE WHEN ? = 1 THEN COALESCE(feed_seq, (SELECT COALESCE(MAX(feed_seq), 0) + 1 FROM articles WHERE feed_seq IS NOT NULL)) ELSE feed_seq END,
            added_at = CASE WHEN ? = 1 AND feed_seq IS NULL THEN ? ELSE added_at END
     WHERE id = ?`,
  ).bind(
    s.headline,
    s.shortSummary,
    s.summary,
    s.decisionType,
    JSON.stringify(s.topics),
    JSON.stringify(s.tags),
    s.importance,
    s.isNews ? 1 : 0,
    now,
    MODEL,
    // The new is_news, for feed_seq and added_at: inside an UPDATE, the column itself
    // still holds the old value.
    s.isNews ? 1 : 0,
    s.isNews ? 1 : 0,
    now,
    id,
  );
}

/**
 * Item 7. Summarizes up to `maxArticles` articles that have no summary yet,
 * newest first: one AI call each, writing the fields in docs/style-guide.md
 * and `is_news`, which decides whether the article shows in the feed.
 *
 * An unusable answer counts as an attempt; after MAX_ATTEMPTS the article
 * stays hidden. An error from Workers AI itself (an outage, or the daily free
 * allocation used up) costs no attempt and ends the run, to try again later.
 *
 * The run claims its articles first, so a run that starts while this one is
 * still going takes other ones and the free allocation is not spent twice.
 */
export async function runSummarizer(
  env: Env,
  options: { maxArticles: number },
  summarize: Summarize = workersAi(env),
): Promise<SummaryResult[]> {
  const now = new Date();
  // Claim before calling the model, in one statement (as the fetcher claims its sources).
  const { results: claimed } = await env.DB.prepare(
    `UPDATE articles SET summary_claimed_at = ?1
     WHERE id IN (
       SELECT id FROM articles
       WHERE summarized_at IS NULL AND summary_attempts < ?2
         AND (summary_claimed_at IS NULL OR summary_claimed_at < ?3)
       ORDER BY fetched_at DESC, id DESC
       LIMIT ?4
     )
     RETURNING id`,
  )
    .bind(toStoredTime(now), MAX_ATTEMPTS, toStoredTime(new Date(now.getTime() - CLAIM_MINUTES * 60_000)), options.maxArticles)
    .all<{ id: string }>();
  if (!claimed.length) return [];

  const { results: rows } = await env.DB.prepare(
    `SELECT a.id, a.original_title, a.text, a.original_language, s.name AS source_name, s.country
     FROM articles a JOIN sources s ON s.id = a.source_id
     WHERE a.id IN (SELECT value FROM json_each(?))
     ORDER BY a.fetched_at DESC, a.id DESC`,
  )
    .bind(JSON.stringify(claimed.map((c) => c.id)))
    .all<ArticleRow>();

  const results: SummaryResult[] = [];
  for (const [index, row] of rows.entries()) {
    const article: ArticleInput = {
      sourceName: row.source_name,
      country: row.country,
      language: row.original_language,
      title: row.original_title,
      text: row.text,
    };
    try {
      const answer = await summarize(article);
      let parsed: unknown;
      try {
        parsed = parseJson(answer);
      } catch {
        throw new UnusableAnswer("the answer is not valid JSON");
      }
      const checked = toSummary(parsed);
      if ("problems" in checked) throw new UnusableAnswer(checked.problems.join("; "));
      await store(env, row.id, checked.summary, toStoredTime(new Date())).run();
      results.push({ articleId: row.id, ok: true, isNews: checked.summary.isNews });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      results.push({ articleId: row.id, ok: false, error: message });
      if (!(error instanceof UnusableAnswer)) {
        // Not the article's fault: free it and the ones not tried yet for the next run.
        await env.DB.prepare("UPDATE articles SET summary_claimed_at = NULL WHERE id IN (SELECT value FROM json_each(?))")
          .bind(JSON.stringify(rows.slice(index).map((r) => r.id)))
          .run();
        break;
      }
      await env.DB.prepare("UPDATE articles SET summary_attempts = summary_attempts + 1, summary_claimed_at = NULL WHERE id = ?")
        .bind(row.id)
        .run();
    }
  }

  if (results.length) console.log(JSON.stringify({ message: "summarizer run", model: MODEL, results }));
  return results;
}
