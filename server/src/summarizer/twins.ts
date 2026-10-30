// An event that both Wikipedias report (#230) is shown once, the one summarized
// first. The English and the Russian page tell it in their own words, so the
// two summaries are compared, not the pages: the model writes both in English,
// from the same facts. Tried on the first 26 live events, each summarized twice
// (30 Oct): the same event shares at least 47% of the words of its headline and
// short summary, two different events at most 22%.
import type { Env } from "../env";
import type { Summary } from "./schema";

/** The share of words two summaries must share to tell the same event. */
export const SAME_EVENT = 0.4;

/** How far apart two pages may date the same event. */
const DAYS = 2;

/** Words that say nothing of which event it is. */
const COMMON = new Set(
  "the and for with from after over into its his her their was were has have had been are this that than who which".split(" "),
);

/** The words of a headline and short summary that tell an event: 3 letters or more, numbers of any length. */
function words(text: string): Set<string> {
  return new Set((text.toLowerCase().match(/[\p{L}\p{N}]+/gu) ?? []).filter((w) => (w.length >= 3 || /^\d+$/.test(w)) && !COMMON.has(w)));
}

const numbers = (set: Set<string>) => [...set].filter((w) => /^\d+$/.test(w));

interface Told {
  headline: string;
  shortSummary: string;
  countries: string[];
}

/**
 * Whether two summaries tell the same event: they share a country, SAME_EVENT
 * of their words, and a number when both give one ("12 killed" and "5 killed"
 * in the same city are two strikes).
 */
export function sameEvent(a: Told, b: Told): boolean {
  if (!a.countries.some((c) => b.countries.includes(c))) return false;
  const x = words(`${a.headline} ${a.shortSummary}`);
  const y = words(`${b.headline} ${b.shortSummary}`);
  const shared = [...x].filter((w) => y.has(w));
  if (shared.length / new Set([...x, ...y]).size < SAME_EVENT) return false;
  const nx = numbers(x);
  const ny = numbers(y);
  return !nx.length || !ny.length || nx.some((n) => ny.includes(n));
}

/**
 * The id of an event in the feed's news that `summary` tells again, dated
 * within DAYS of it; null when none. With no countries from the model, the
 * source's, as the summarizer stores them.
 */
export async function twinOf(env: Env, id: string, summary: Summary, publishedAt: string, sourceCountry: string): Promise<string | null> {
  const day = 86_400_000;
  const at = new Date(publishedAt).getTime();
  const stamp = (t: number) => `${new Date(t).toISOString().slice(0, 19)}Z`;
  // Through articles_feed (is_news, published_at): the news of a few days, not the table.
  const { results } = await env.DB.prepare(
    `SELECT a.id, a.headline, a.short_summary,
            (SELECT json_group_array(c.country) FROM article_countries c WHERE c.article_id = a.id) AS countries
     FROM articles a
     WHERE a.is_news = 1 AND a.published_at BETWEEN ?2 AND ?3 AND a.decision_type = 'event' AND a.id <> ?1
     ORDER BY a.summarized_at, a.id`,
  )
    .bind(id, stamp(at - DAYS * day), stamp(at + DAYS * day))
    .all<{ id: string; headline: string | null; short_summary: string | null; countries: string }>();
  const countries = summary.countries.length ? summary.countries : [sourceCountry];
  const told = { headline: summary.headline, shortSummary: summary.shortSummary, countries };
  const twin = results.find((r) =>
    sameEvent(told, { headline: r.headline ?? "", shortSummary: r.short_summary ?? "", countries: JSON.parse(r.countries) as string[] }),
  );
  return twin?.id ?? null;
}
