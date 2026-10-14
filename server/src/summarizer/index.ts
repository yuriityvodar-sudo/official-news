import type { Env } from "../env";
import { type ArticleInput, SYSTEM_PROMPT, userMessage } from "./prompt";
import { SUMMARY_SCHEMA, type Summary, parseJson, toSummary } from "./schema";

/** The Workers AI model that writes the summaries (Roman's choice, docs/decisions.md). */
export const MODEL = "@cf/zai-org/glm-4.7-flash";

/** An article gets this many tries with an unusable answer, then it stays hidden. */
export const MAX_ATTEMPTS = 3;

const MAX_COMPLETION_TOKENS = 1500;

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
    `UPDATE articles SET headline = ?, short_summary = ?, summary = ?, decision_type = ?, topics = ?, tags = ?,
            importance = ?, is_news = ?, summarized_at = ?, model = ?
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
 */
export async function runSummarizer(
  env: Env,
  options: { maxArticles: number },
  summarize: Summarize = workersAi(env),
): Promise<SummaryResult[]> {
  const { results: rows } = await env.DB.prepare(
    `SELECT a.id, a.original_title, a.text, a.original_language, s.name AS source_name, s.country
     FROM articles a JOIN sources s ON s.id = a.source_id
     WHERE a.summarized_at IS NULL AND a.summary_attempts < ?
     ORDER BY a.fetched_at DESC, a.id DESC
     LIMIT ?`,
  )
    .bind(MAX_ATTEMPTS, options.maxArticles)
    .all<ArticleRow>();

  const results: SummaryResult[] = [];
  for (const row of rows) {
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
      await store(env, row.id, checked.summary, `${new Date().toISOString().slice(0, 19)}Z`).run();
      results.push({ articleId: row.id, ok: true, isNews: checked.summary.isNews });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      results.push({ articleId: row.id, ok: false, error: message });
      if (!(error instanceof UnusableAnswer)) break;
      await env.DB.prepare("UPDATE articles SET summary_attempts = summary_attempts + 1 WHERE id = ?").bind(row.id).run();
    }
  }

  if (results.length) console.log(JSON.stringify({ message: "summarizer run", model: MODEL, results }));
  return results;
}
