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
const WORD = /[\p{L}\p{M}\p{N}]+/gu;
const DIGITS = /^\p{N}+$/u;
const CAPITAL = /^\p{Lu}/u;
const SPACE = /\s/u;
/** What may stand between a phrase's end and its first word: quotes and brackets. */
const PASSED = new Set([..."\"'«»„“”‚‘’()[]"]);
const PHRASE_END = new Set([..."．.!?:;…|-–—"]);

/** Whether the word at `index` begins the headline or a phrase in it ("Hackerangriff - FBI macht…"). */
function phraseStart(text: string, index: number): boolean {
  for (let i = index - 1; i >= 0; i--) {
    const c = text[i];
    if (c === " " || PASSED.has(c) || SPACE.test(c)) continue;
    return PHRASE_END.has(c);
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
  for (const match of text.matchAll(WORD)) {
    const word = match[0];
    const name = CAPITAL.test(word) && !phraseStart(text, match.index);
    const add = (term: string) => found.set(term, name || (found.get(term) ?? false));
    if (PAIRS.test(word)) {
      const chars = [...word.toLowerCase()];
      for (let i = 0; i + 1 < chars.length; i++) add(chars[i] + chars[i + 1]);
    } else if (DIGITS.test(word)) {
      add(word);
    } else {
      const chars = [...word.toLowerCase()];
      if (chars.length >= STORIES.minWordLength) add(chars.slice(0, STORIES.stemLength).join(""));
    }
  }
  return found;
}

/**
 * Headlines already read, by title: a country's stories are built every few
 * minutes from mostly the same headlines, and a call's isolate often serves
 * the next one. Emptied when it holds this many.
 */
const READ = new Map<string, Map<string, boolean>>();
const READ_MAX = 20_000;
function readTermsOnce(title: string): Map<string, boolean> {
  let found = READ.get(title);
  if (!found) {
    if (READ.size >= READ_MAX) READ.clear();
    found = readTerms(title);
    READ.set(title, found);
  }
  return found;
}

/** A headline's words as they are compared: stems, numbers, or pairs of characters. */
export const terms = (title: string): string[] => [...readTerms(title).keys()];

/** 32-bit FNV-1a, in base 36: short ids for links. */
function hash(text: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 0x01000193) >>> 0;
  return h.toString(36);
}

/** Text in the order of its UTF-16 code units: what the times and links need, cheaper than localeCompare. */
const byText = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);

/** A headline's words as numbers (this call's), in increasing order, with their weights. */
interface Member {
  headline: OutletHeadline;
  /** Its rarest words that other headlines have too: the stories it is compared with share one. */
  leads: number[];
  ids: number[];
  weights: number[];
  norm: number;
}

interface Group {
  members: Member[];
  /** The sum of its headlines' vectors, each of length 1, and that sum's squared length. */
  centre: Map<number, number>;
  centreSquared: number;
}

function toCentre(member: Member, group: Group): number {
  const centreNorm = Math.sqrt(group.centreSquared);
  if (!member.norm || !centreNorm) return 0;
  let dot = 0;
  for (let k = 0; k < member.ids.length; k++) dot += member.weights[k] * (group.centre.get(member.ids[k]) ?? 0);
  return dot / (member.norm * centreNorm);
}

function toMember(a: Member, b: Member): number {
  if (!a.norm || !b.norm) return 0;
  let dot = 0;
  for (let i = 0, j = 0; i < a.ids.length && j < b.ids.length; ) {
    if (a.ids[i] === b.ids[j]) dot += a.weights[i++] * b.weights[j++];
    else if (a.ids[i] < b.ids[j]) i++;
    else j++;
  }
  return dot / (a.norm * b.norm);
}

/**
 * Groups one country's headlines into stories. Each word weighs by how rare it
 * is among these headlines (inverse document frequency), so names, places and
 * numbers decide and words every headline has do not. Oldest first, a headline
 * joins the story whose centre it is most like, from `joinAt` up, or starts one;
 * it is compared only with the stories that share one of its rarest words.
 * Then each headline left alone looks again, now that the stories have grown: a
 * long headline that came second, to a story of one short headline, joins the
 * story it is like, as long as it is like one of its headlines too. Words are
 * numbers within a call and each headline is read once per isolate, so a call
 * stays within its 10 ms of CPU (1 Nov: India's 450 headlines took 38 ms before).
 */
export function clusterHeadlines(headlines: OutletHeadline[]): Story[] {
  const sorted = [...headlines].sort((a, b) => byText(a.publishedAt, b.publishedAt) || byText(a.url, b.url));
  const termIds = new Map<string, number>();
  const read = sorted.map((h) => {
    const found = readTermsOnce(h.title);
    const ids: number[] = [];
    const names: boolean[] = [];
    for (const [term, name] of found) {
      let id = termIds.get(term);
      if (id === undefined) termIds.set(term, (id = termIds.size));
      ids.push(id);
      names.push(name);
    }
    return { ids, names };
  });
  const df = new Int32Array(termIds.size);
  for (const { ids } of read) for (const id of ids) df[id]++;
  const total = sorted.length;
  const common = Math.max(STORIES.commonFloor, total * STORIES.commonShare);
  const corpus = Math.max(total, STORIES.idfHeadlines);

  const groups: Group[] = [];
  const index: number[][] = Array.from({ length: termIds.size }, () => []);
  const seen = new Int32Array(Math.max(1, total)).fill(-1);
  let looked = 0;
  const best = (member: Member, eligible: (g: number) => boolean) => {
    looked++;
    let found = -1;
    let top = 0;
    for (const term of member.leads) {
      for (const g of index[term]) {
        if (seen[g] === looked || !eligible(g)) continue;
        seen[g] = looked;
        const s = toCentre(member, groups[g]);
        if (s > top) [found, top] = [g, s];
      }
    }
    return top >= STORIES.joinAt ? found : -1;
  };
  const join = (g: number, member: Member) => {
    const group = groups[g];
    group.members.push(member);
    for (let k = 0; k < member.ids.length; k++) {
      const id = member.ids[k];
      const before = group.centre.get(id);
      const after = (before ?? 0) + (member.norm ? member.weights[k] / member.norm : 0);
      group.centre.set(id, after);
      group.centreSquared += after * after - (before ?? 0) * (before ?? 0);
      if (before === undefined) index[id].push(g);
    }
  };

  sorted.forEach((headline, i) => {
    const { ids: unordered, names } = read[i];
    const order = unordered.map((_, k) => k).sort((a, b) => unordered[a] - unordered[b]);
    const ids = order.map((k) => unordered[k]);
    const weights = order.map((k) => Math.log(corpus / df[unordered[k]]) * (names[k] ? STORIES.nameWeight : 1));
    // A word no other headline has leads nowhere.
    const leads = unordered
      .filter((id) => df[id] > 1 && df[id] <= common)
      .sort((a, b) => df[a] - df[b])
      .slice(0, STORIES.leadTerms);
    const member: Member = { headline, leads, ids, weights, norm: Math.sqrt(weights.reduce((sum, w) => sum + w * w, 0)) };
    const found = best(member, () => true);
    join(found >= 0 ? found : groups.push({ members: [], centre: new Map(), centreSquared: 0 }) - 1, member);
  });

  groups.forEach((group, g) => {
    if (group.members.length !== 1) return;
    const [alone] = group.members;
    const found = best(alone, (other) => other !== g && groups[other].members.length > 1);
    // Like the story's centre and like one of its headlines: a centre made of a few headlines of
    // the same kind (two shootings: "dead", "injured") draws a third of that kind.
    if (found < 0 || !groups[found].members.some((m) => toMember(alone, m) >= STORIES.joinAt)) return;
    join(found, alone);
    group.members = [];
  });

  return groups
    .filter((group) => group.members.length)
    .map((group) => {
      const byTime = [...group.members].sort((a, b) => byText(a.headline.publishedAt, b.headline.publishedAt));
      // One headline per outlet, its latest on the story.
      const latest = new Map<string, OutletHeadline>();
      for (const { headline } of byTime) latest.set(headline.outlet.id, headline);
      let typical = byTime[0];
      let closest = toCentre(typical, group);
      for (const member of byTime.slice(1)) {
        const s = toCentre(member, group);
        if (s > closest) [typical, closest] = [member, s];
      }
      const items = [...latest.values()].sort((a, b) => byText(b.publishedAt, a.publishedAt));
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
