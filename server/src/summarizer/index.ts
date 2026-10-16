import type { Env } from "../env";
import { toStoredTime } from "../fetcher/text";
import { checkSummary } from "./checks";
import { type ArticleInput, MAX_TEXT, SYSTEM_PROMPT, userMessage } from "./prompt";
import { SUMMARY_SCHEMA, type Summary, parseJson, toSummary } from "./schema";

/**
 * The Workers AI model that writes the summaries (docs/decisions.md). Gemma 4
 * since #63: in the 16 Oct test on 12 real articles it kept names and numbers
 * right where GLM-4.7 Flash invented some, at about 1.2 times its cost per call
 * on the same prompt (estimate). With #63's longer prompt, "what it means" and
 * retries, an article costs about 2 to 2.5 times what it did (estimate, to be
 * measured after a day live).
 */
export const MODEL = "@cf/google/gemma-4-26b-a4b-it";

/** An article gets this many tries with an unusable answer, then it stays hidden. */
export const MAX_ATTEMPTS = 3;

/** The answer with its impact part is about 300 to 450 tokens. */
const MAX_COMPLETION_TOKENS = 2000;

/** A claim older than this is from a run that was cut off, so its articles are free again. */
export const CLAIM_MINUTES = 10;

interface ArticleRow {
  id: string;
  original_title: string;
  text: string | null;
  original_language: string | null;
  source_name: string;
  country: string;
  fetched_at: string;
  summary_attempts: number;
}

/** What happened to one article in a run, for the log. */
export interface SummaryResult {
  articleId: string;
  ok: boolean;
  isNews?: boolean;
  error?: string;
  /** Stored with ruled-out words, as its last try (checks.ts). */
  warning?: string;
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
  // No feed_seq here: an article enters the feed when it is released, in English
  // and every language at once (release together, #46: translator/release.ts).
  return env.DB.prepare(
    `UPDATE articles SET headline = ?, short_summary = ?, summary = ?, decision_type = ?, topics = ?, tags = ?,
            importance = ?, is_news = ?, summarized_at = ?, model = ?, impact = ?
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
    s.impact ? JSON.stringify(s.impact) : null,
    id,
  );
}

/**
 * Item 7. Summarizes up to `maxArticles` articles that have no summary yet,
 * newest first: one AI call each, writing the fields in docs/style-guide.md
 * and `is_news`, which decides whether the article goes to the feed.
 *
 * An official decision is not shown yet: the release gives it its place in
 * the feed (feed_seq) once it is translated into every enabled language, or at
 * once while the translator is not running (#46, translator/release.ts). The
 * scheduled run (../index.ts) releases after each summarizer run.
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
    `SELECT a.id, a.original_title, a.text, a.original_language, s.name AS source_name, s.country,
            a.fetched_at, a.summary_attempts
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
      // A number the article does not give, or a summary not in English, is never
      // stored (#63); ruled-out words get another try, and on the last one the summary
      // is stored anyway, so a decision is not hidden for a word. Readers never see an
      // article that is not news, so its answer is not checked: a retry would only cost Neurons.
      let summary = checked.summary;
      const warnings: string[] = [];
      if (summary.isNews) {
        const source = `${row.original_title}\n${(row.text ?? "").slice(0, MAX_TEXT)}`;
        const year = Number(row.fetched_at.slice(0, 4));
        const lastTry = row.summary_attempts >= MAX_ATTEMPTS - 1;
        let found = checkSummary(summary, source, year);
        // On the last try, numbers only in "what it means" cost that part, not the decision.
        if (found.invented.length && lastTry && summary.impact) {
          const withoutImpact = checkSummary({ ...summary, impact: null }, source, year);
          if (!withoutImpact.invented.length) {
            warnings.push(`impact dropped: numbers not in the article: ${found.invented.join(", ")}`);
            summary = { ...summary, impact: null };
            found = withoutImpact;
          }
        }
        if (found.invented.length) throw new UnusableAnswer(`numbers not in the article: ${found.invented.join(", ")}`);
        if (found.notEnglish) throw new UnusableAnswer("the summary is not in English");
        if (found.banned.length && !lastTry) throw new UnusableAnswer(`ruled-out words: ${found.banned.join(", ")}`);
        if (found.banned.length) warnings.push(`stored on its last try with: ${found.banned.join(", ")}`);
      }
      await store(env, row.id, summary, toStoredTime(new Date())).run();
      results.push({
        articleId: row.id,
        ok: true,
        isNews: summary.isNews,
        ...(warnings.length ? { warning: warnings.join("; ") } : {}),
      });
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
