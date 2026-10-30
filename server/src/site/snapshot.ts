// A list page from the language's snapshot (api/snapshot.ts): the filters,
// the paging and the top stories as GET /articles and GET /topics answer them
// (api/index.ts: feedFilters, listArticles, topQuery, listTopics), worked out
// here over the snapshot's articles instead of in SQL, so a page reads one D1
// row. test/site-snapshot.test.ts and site-filters.test.ts check the answers
// against the API's, page by page.
import { TOP_HOURS, TOP_SIZE, encodeCursor } from "../api";
import { GROUPS, groupCountries, rankTopics } from "../api/filters";
import type { Snapshot, SnapshotArticle, TopCandidate } from "../api/snapshot";
import type { SiteLang } from "./texts";
import type { ListFilter, Place } from "./urls";

/** A page of the list, as the API's (DEFAULT_LIMIT). */
const PAGE = 20;

/** The source countries `place` shows (the API's whereCountries): one country alone, a group's members (and the EU institutions where it includes them), or null for all. */
const placeCountries = (place: Place): string[] | null =>
  place === null ? null : "country" in place ? [place.country] : groupCountries(GROUPS.find((g) => g.id === place.group)!);

/** Whether the article passes the filters (feedFilters): its source's country among `countries`, and the topic among its topics. */
const passes = (article: { country: string; topics: string[] }, countries: string[] | null, topic: string | null) =>
  (countries === null || countries.includes(article.country)) && (topic === null || article.topics.includes(topic));

/** The time stored for `date` (docs/contract.md), which compares as text. */
const stored = (date: Date) => `${date.toISOString().slice(0, 19)}Z`;

/**
 * The top stories (#164, topQuery) among the candidates that pass the filters
 * and are of the last 72 hours as of `now`: scored as the API scores them (the
 * importance less half a point a day since publication; the same `now` for
 * every candidate, so the order is the API's), best first, the newer on equal
 * scores, then the higher id; at most one a source country, or TOP_SIZE when
 * Where is one country; TOP_SIZE in all. In a language, the English picks it
 * has a shown translation of (translatedTop), in that order: fewer when some
 * are not translated yet.
 */
export function snapshotTop(snapshot: Snapshot, filter: ListFilter, now: Date): SnapshotArticle[] {
  const countries = placeCountries(filter.place);
  const since = stored(new Date(now.getTime() - TOP_HOURS * 3_600_000));
  const score = (c: TopCandidate) => c.importance - (0.5 * (now.getTime() - Date.parse(c.publishedAt))) / 86_400_000;
  const compare = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);
  const ranked = snapshot.top
    .filter((c) => c.publishedAt >= since && passes(c, countries, filter.topic))
    .sort((a, b) => score(b) - score(a) || compare(b.publishedAt, a.publishedAt) || compare(b.id, a.id));
  const perCountry = filter.place !== null && "country" in filter.place ? TOP_SIZE : 1;
  const taken = new Map<string, number>();
  const picked: TopCandidate[] = [];
  for (const candidate of ranked) {
    const n = taken.get(candidate.country) ?? 0;
    if (n >= perCountry) continue;
    taken.set(candidate.country, n + 1);
    picked.push(candidate);
    if (picked.length === TOP_SIZE) break;
  }
  const shown = new Map(snapshot.articles.map((a) => [a.id, a]));
  return picked.map((c) => shown.get(c.id)).filter((a): a is SnapshotArticle => a !== undefined);
}

/**
 * A page of the list (listArticles): the snapshot's articles that pass the
 * filters, in feed order (newest feedSeq first, as the snapshot is kept),
 * after `before` (the feedSeq the page continues from; null for the first
 * page), PAGE of them, with the API's cursor when more follow; the top stories
 * on the first page only.
 */
export function snapshotPage(snapshot: Snapshot, filter: ListFilter, before: number | null, now: Date) {
  const countries = placeCountries(filter.place);
  const matching = snapshot.articles.filter((a) => passes(a, countries, filter.topic) && (before === null || (a.feedSeq !== null && a.feedSeq < before)));
  const items = matching.slice(0, PAGE);
  const last = items.at(-1);
  const nextCursor = matching.length > PAGE && last?.feedSeq != null ? encodeCursor(last.feedSeq) : null;
  return { items, nextCursor, top: before === null ? snapshotTop(snapshot, filter, now) : [] };
}

/** The Topics menu (listTopics): the topics of the language's feed in `place` (all of it with null), busiest first, named in `lang`. */
export function snapshotTopics(snapshot: Snapshot, lang: SiteLang, place: Place) {
  const countries = placeCountries(place);
  return rankTopics(
    snapshot.articles.filter((a) => passes(a, countries, null)).map((a) => a.topics),
    lang,
  );
}
