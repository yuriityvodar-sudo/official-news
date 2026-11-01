// Stories (#230, the aggregator, step 2): one country's headlines about the same
// event grouped together, as news aggregators group them, and ranked by how many
// of the country's outlets carry the story and how fresh it is. The same rule for
// every country and language: no word lists, no language of its own.
import type { OutletHeadline } from "../fetcher/types";

/** A story: one headline per outlet that carries it, the most recent first. */
export interface Story {
  /** Stable while its first headline is in the window: a hash of that headline's link. */
  id: string;
  /** The headline that says it most typically (nearest the story's centre). */
  title: string;
  items: OutletHeadline[];
  firstSeen: string;
  lastSeen: string;
}

export const STORIES = {
  /** A word is cut to its first letters, so "Sněžka" and "Sněžkou", "Зеленський" and "Зеленського" meet. */
  stemLength: 5,
  /** Shorter words say little in most languages ("a", "of", "на"); a frequent longer one weighs little anyway. */
  minWordLength: 3,
  /** How alike a headline must be to a story to join it (cosine of the words' weights, 0 to 1). */
  joinAt: 0.34,
  /**
   * A word in more than this share of the headlines, and in more than `commonFloor` of them, leads to
   * no story by itself ("the", "2026"): a headline is compared with few stories. The floor keeps a small
   * country's names in play, where a story every outlet carries is a big share of few headlines.
   */
  commonShare: 0.05,
  commonFloor: 10,
  /**
   * A word's weight is the log of this many headlines, or of the country's when it has more, over the
   * headlines it is in: a country with few headlines does not make its names look common.
   */
  idfHeadlines: 200,
  /** A headline is compared with the stories that share one of its rarest words, this many. */
  leadTerms: 6,
  /**
   * A name weighs this many times a word: two shootings told alike ("leaves 1 dead, 8 injured") are
   * told apart by Alabama and California. A language that writes every noun with a capital (German)
   * weighs them all alike. On 10 pairs of 1 Nov marked by hand, 1.5 got 8 right, 2 got 6 (two-word
   * names such as "New York" pulled unrelated stories together), 1 got 5.
   */
  nameWeight: 1.5,
  /** A story's weight halves in this many hours since each outlet's last headline on it. */
  halfLifeHours: 6,
} as const;

// Scripts written without spaces between words, and Hangul, whose words carry
// their endings: compared by pairs of characters instead of words.
const PAIRS = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}\p{Script=Thai}\p{Script=Lao}\p{Script=Khmer}\p{Script=Myanmar}]/u;

/** Whether the word at `index` begins the headline or a phrase in it ("Hackerangriff - FBI macht…"). */
function phraseStart(text: string, index: number): boolean {
  for (let i = index - 1; i >= 0; i--) {
    if (/[\s"'«»„“”‚‘’()[\]]/u.test(text[i])) continue;
    return /[.!?:;…|\-–—]/u.test(text[i]);
  }
  return true;
}

/**
 * A headline's words as they are compared (stems, numbers, or pairs of
 * characters), each with whether it is written as a name: a capital letter
 * that does not begin a phrase is most often a person, a place or a body.
 */
function readTerms(title: string): Map<string, boolean> {
  const text = title.normalize("NFKC");
  const found = new Map<string, boolean>();
  for (const match of text.matchAll(/[\p{L}\p{M}\p{N}]+/gu)) {
    const chars = [...match[0].toLowerCase()];
    const name = /^\p{Lu}/u.test(match[0]) && !phraseStart(text, match.index);
    const add = (term: string) => found.set(term, name || (found.get(term) ?? false));
    if (PAIRS.test(match[0])) {
      for (let i = 0; i + 1 < chars.length; i++) add(chars[i] + chars[i + 1]);
    } else if (/^\p{N}+$/u.test(match[0])) {
      add(match[0]);
    } else if (chars.length >= STORIES.minWordLength) {
      add(chars.slice(0, STORIES.stemLength).join(""));
    }
  }
  return found;
}

/** A headline's words as they are compared: stems, numbers, or pairs of characters. */
export const terms = (title: string): string[] => [...readTerms(title).keys()];

type Vector = Map<string, number>;

const norm = (v: Vector) => Math.sqrt([...v.values()].reduce((sum, w) => sum + w * w, 0));

function similarity(a: Vector, aNorm: number, b: Vector, bNorm: number): number {
  if (!aNorm || !bNorm) return 0;
  let dot = 0;
  for (const [term, weight] of a) dot += weight * (b.get(term) ?? 0);
  return dot / (aNorm * bNorm);
}

/** 32-bit FNV-1a, in base 36: short ids for links. */
function hash(text: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 0x01000193) >>> 0;
  return h.toString(36);
}

interface Member {
  headline: OutletHeadline;
  /** Its rarest words that other headlines have too: the stories it is compared with share one. */
  leads: string[];
  vector: Vector;
  norm: number;
}

interface Group {
  members: Member[];
  centre: Vector;
  centreNorm: number;
}

/**
 * Groups one country's headlines into stories. Each word weighs by how rare it
 * is among these headlines (inverse document frequency), so names, places and
 * numbers decide and words every headline has do not. Oldest first, a headline
 * joins the story whose centre it is most like, from `joinAt` up, or starts one;
 * it is compared only with the stories that share one of its rarest words.
 * Then each headline left alone looks again, now that the stories have grown: a
 * long headline that came second, to a story of one short headline, joins the
 * story it is like, as long as it is like one of its headlines too.
 */
export function clusterHeadlines(headlines: OutletHeadline[]): Story[] {
  const sorted = [...headlines].sort((a, b) => a.publishedAt.localeCompare(b.publishedAt) || a.url.localeCompare(b.url));
  const termsOf = sorted.map((h) => readTerms(h.title));
  const df = new Map<string, number>();
  for (const found of termsOf) for (const term of found.keys()) df.set(term, (df.get(term) ?? 0) + 1);
  const total = sorted.length;
  const common = Math.max(STORIES.commonFloor, total * STORIES.commonShare);

  const groups: Group[] = [];
  const index = new Map<string, Set<number>>();
  const best = (member: Member, eligible: (g: number) => boolean) => {
    const candidates = new Set<number>();
    for (const term of member.leads) for (const g of index.get(term) ?? []) if (eligible(g)) candidates.add(g);
    let found = -1;
    let top = 0;
    for (const g of candidates) {
      const s = similarity(member.vector, member.norm, groups[g].centre, groups[g].centreNorm);
      if (s > top) [found, top] = [g, s];
    }
    return top >= STORIES.joinAt ? found : -1;
  };
  const join = (g: number, member: Member) => {
    const group = groups[g];
    group.members.push(member);
    // The centre: the sum of its headlines' vectors, each of length 1.
    if (member.norm) for (const [term, weight] of member.vector) group.centre.set(term, (group.centre.get(term) ?? 0) + weight / member.norm);
    group.centreNorm = norm(group.centre);
    for (const term of member.vector.keys()) {
      if (!index.has(term)) index.set(term, new Set());
      index.get(term)!.add(g);
    }
  };

  sorted.forEach((headline, i) => {
    const vector: Vector = new Map(
      [...termsOf[i]].map(([term, name]) => [term, Math.log(Math.max(total, STORIES.idfHeadlines) / df.get(term)!) * (name ? STORIES.nameWeight : 1)]),
    );
    // A word no other headline has leads nowhere.
    const leads = [...termsOf[i].keys()]
      .filter((term) => df.get(term)! > 1 && df.get(term)! <= common)
      .sort((a, b) => df.get(a)! - df.get(b)!)
      .slice(0, STORIES.leadTerms);
    const member = { headline, leads, vector, norm: norm(vector) };
    const found = best(member, () => true);
    join(found >= 0 ? found : groups.push({ members: [], centre: new Map(), centreNorm: 0 }) - 1, member);
  });

  groups.forEach((group, g) => {
    if (group.members.length !== 1) return;
    const [alone] = group.members;
    const found = best(alone, (other) => other !== g && groups[other].members.length > 1);
    // Like the story's centre and like one of its headlines: a centre made of a few headlines of
    // the same kind (two shootings: "dead", "injured") draws a third of that kind.
    if (found < 0 || !groups[found].members.some((m) => similarity(alone.vector, alone.norm, m.vector, m.norm) >= STORIES.joinAt)) return;
    join(found, alone);
    group.members = [];
  });

  return groups
    .filter((group) => group.members.length)
    .map((group) => {
      const byTime = [...group.members].sort((a, b) => a.headline.publishedAt.localeCompare(b.headline.publishedAt));
      // One headline per outlet, its latest on the story.
      const latest = new Map<string, OutletHeadline>();
      for (const { headline } of byTime) latest.set(headline.outlet.id, headline);
      const typical = byTime.reduce((a, b) =>
        similarity(b.vector, b.norm, group.centre, group.centreNorm) > similarity(a.vector, a.norm, group.centre, group.centreNorm) ? b : a,
      );
      const items = [...latest.values()].sort((a, b) => b.publishedAt.localeCompare(a.publishedAt));
      return {
        id: hash(byTime[0].headline.url),
        title: typical.headline.title,
        items,
        firstSeen: byTime[0].headline.publishedAt,
        lastSeen: items[0].publishedAt,
      };
    });
}

/**
 * A story's weight at `now`: each outlet on it counts 1, halved every
 * `halfLifeHours` since its last headline on the story. Five outlets this hour
 * outweigh five yesterday, and two outlets one alone.
 */
export function storyScore(story: Story, now: Date): number {
  return story.items.reduce((sum, item) => {
    const hours = Math.max(0, (now.getTime() - Date.parse(item.publishedAt)) / 3_600_000);
    return sum + 2 ** (-hours / STORIES.halfLifeHours);
  }, 0);
}
