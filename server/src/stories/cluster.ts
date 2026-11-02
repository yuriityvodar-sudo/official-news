// Stories (#230, the aggregator, step 2): one country's headlines about the same
// event grouped together, as news aggregators group them, and ranked by how many
// of the country's outlets carry the story and how fresh it is. The same rule for
// every country and language: no word lists, no language of its own.
import type { OutletHeadline } from "../fetcher/types";
import groupWasm from "./group.wasm";

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
 * minutes from mostly the same headlines, and a call's isolate sometimes
 * serves the next one. Emptied when it holds this many.
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

/**
 * A headline's words as the fetcher keeps them with it (`words`), so a build
 * does not read them again: [terms], a name's with "^" first ("^babiš"). If
 * readTerms changes, rename the field, so headlines kept before are read anew.
 */
export function headlineWords(title: string): string[] {
  const words: string[] = [];
  for (const [term, name] of readTerms(title)) words.push(name ? `^${term}` : term);
  return words;
}

/** A headline to group, with its words when the fetcher kept them (headlineWords). */
export type StoryHeadline = OutletHeadline & { words?: string[] };

/** 32-bit FNV-1a, in base 36: short ids for links. */
function hash(text: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 0x01000193) >>> 0;
  return h.toString(36);
}

/** Text in the order of its UTF-16 code units: what the times and links need, cheaper than localeCompare. */
const byText = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);

/**
 * The grouping's WebAssembly (`assembly/stories.ts`, built into group.wasm): a
 * call's JavaScript starts cold, and its loops took most of the call's 10 ms
 * of CPU (2 Nov, India's 300 headlines about 12 ms after #287's speed-ups).
 * One instance per isolate, its memory kept for the next call.
 */
interface Grouping {
  memory: WebAssembly.Memory;
  heap(): number;
  group(base: number): number;
}
let grouping: Grouping | undefined;
const wasm = (): Grouping => (grouping ??= new WebAssembly.Instance(groupWasm, {}).exports as unknown as Grouping);

/** The slots of the grouping's header: where its arrays are (assembly/stories.ts). */
const SLOT = {
  n: 0, terms: 1, leads: 2, wordStart: 3, ids: 4, names: 5, idf: 6, rank: 7, sorted: 8, weights: 9, units: 10, norm: 11,
  unitSquared: 12, lead: 13, leadCount: 14, df: 15, probe: 16, seen: 17, count: 18, head: 19, tail: 20, next: 21,
  squared: 22, centre: 23, postHead: 24, postTail: 25, postGroup: 26, postNext: 27, centres: 28, outStart: 29,
  outMembers: 30, outTypical: 31, common: 32, joinAt: 34, nameWeight: 36,
} as const;
const HEADER_BYTES = 152;

/** The grouping's answer: each group's headlines (indices of the sorted headlines) in time order, and its most typical. */
interface Groups {
  groups: number;
  count: Int32Array;
  start: Int32Array;
  members: Int32Array;
  typical: Int32Array;
}

/**
 * Groups one country's headlines, sorted oldest first. Each word weighs by
 * how rare it is among these headlines (inverse document frequency), so names,
 * places and numbers decide and words every headline has do not. Oldest first,
 * a headline joins the group whose centre it is most like, from `joinAt` up,
 * or starts one; it is compared only with the groups that share one of its
 * rarest words. Then each headline left alone looks again, now that the groups
 * have grown: a long headline that came second, to a group of one short
 * headline, joins the group it is like, as long as it is like one of its
 * headlines too. Here the words become numbers, read once by the fetcher (a
 * headline kept before is read here); the loops run in WebAssembly.
 */
function groupHeadlines(sorted: StoryHeadline[]): Groups {
  const n = sorted.length;
  const termIds = new Map<string, number>();
  const ids: number[] = [];
  const names: number[] = [];
  const wordStart: number[] = [0];
  const number = (term: string): number => {
    let id = termIds.get(term);
    if (id === undefined) termIds.set(term, (id = termIds.size));
    return id;
  };
  for (let i = 0; i < n; i++) {
    const words = sorted[i].words;
    if (Array.isArray(words)) {
      for (let k = 0; k < words.length; k++) {
        const word = words[k];
        const name = word.charCodeAt(0) === 94; // "^"
        ids.push(number(name ? word.slice(1) : word));
        names.push(name ? 1 : 0);
      }
    } else {
      for (const [term, name] of readTermsOnce(sorted[i].title)) {
        ids.push(number(term));
        names.push(name ? 1 : 0);
      }
    }
    wordStart.push(ids.length);
  }
  const terms = termIds.size;
  const words = ids.length;

  // The arrays, one after another, each at a multiple of 8.
  const { memory, heap, group } = wasm();
  const base = heap();
  let end = base + HEADER_BYTES;
  const take = (bytes: number) => {
    const at = (end + 7) & ~7;
    end = at + bytes;
    return at;
  };
  const at: Record<string, number> = {
    wordStart: take(4 * (n + 1)), ids: take(4 * words), names: take(4 * words), idf: take(8 * (n + 1)), rank: take(4 * n),
    sorted: take(4 * words), weights: take(8 * words), units: take(8 * words), norm: take(8 * n), unitSquared: take(8 * n),
    lead: take(4 * n * STORIES.leadTerms), leadCount: take(4 * n), df: take(4 * terms), probe: take(8 * terms), seen: take(4 * n),
    count: take(4 * n), head: take(4 * n), tail: take(4 * n), next: take(4 * n), squared: take(8 * n), centre: take(4 * n),
    postHead: take(4 * terms), postTail: take(4 * terms), postGroup: take(4 * (2 * words + 1)), postNext: take(4 * (2 * words + 1)),
    outStart: take(4 * n), outMembers: take(4 * n), outTypical: take(4 * n),
    // A centre for each group of two or more: at most half the headlines.
    centres: take(8 * Math.floor(n / 2) * terms),
  };
  if (end > memory.buffer.byteLength) memory.grow(Math.ceil((end - memory.buffer.byteLength) / 65_536));
  const i32 = new Int32Array(memory.buffer);
  const f64 = new Float64Array(memory.buffer);
  for (const [slot, offset] of Object.entries(at)) i32[(base >> 2) + SLOT[slot as keyof typeof SLOT]] = offset;
  i32[(base >> 2) + SLOT.n] = n;
  i32[(base >> 2) + SLOT.terms] = terms;
  i32[(base >> 2) + SLOT.leads] = STORIES.leadTerms;
  f64[(base + 4 * SLOT.common) >> 3] = Math.max(STORIES.commonFloor, n * STORIES.commonShare);
  f64[(base + 4 * SLOT.joinAt) >> 3] = STORIES.joinAt;
  f64[(base + 4 * SLOT.nameWeight) >> 3] = STORIES.nameWeight;
  i32.set(wordStart, at.wordStart >> 2);
  i32.set(ids, at.ids >> 2);
  i32.set(names, at.names >> 2);
  // A word's weight by the number of headlines it is in: the log of this many headlines, or of the
  // country's when it has more, over them.
  const corpus = Math.max(n, STORIES.idfHeadlines);
  for (let k = 1; k <= n; k++) f64[(at.idf >> 3) + k] = Math.log(corpus / k);
  // Each headline's time as a rank: its group's headlines are ordered by time, two alike as they joined.
  for (let i = 0, rank = 0; i < n; i++) {
    if (i > 0 && sorted[i].publishedAt !== sorted[i - 1].publishedAt) rank++;
    i32[(at.rank >> 2) + i] = rank;
  }
  const groups = group(base);
  const view = (offset: number) => new Int32Array(memory.buffer, offset, n);
  return { groups, count: view(at.count), start: view(at.outStart), members: view(at.outMembers), typical: view(at.outTypical) };
}

/** Headlines oldest first, two of the same time by link: the order they are grouped in. */
const oldestFirst = (headlines: StoryHeadline[]) => headlines.slice().sort((a, b) => byText(a.publishedAt, b.publishedAt) || byText(a.url, b.url));

/** A headline as a story lists it: its words, link, time and outlet, and nothing the fetcher keeps for the build. */
const item = (h: StoryHeadline): OutletHeadline => ({ title: h.title, url: h.url, publishedAt: h.publishedAt, outlet: h.outlet });

/** Group g's headlines, in time order. */
function byTimeOf(sorted: StoryHeadline[], groups: Groups, g: number): StoryHeadline[] {
  const byTime: StoryHeadline[] = [];
  for (let x = 0, start = groups.start[g]; x < groups.count[g]; x++) byTime.push(sorted[groups.members[start + x]]);
  return byTime;
}

/** A story's items: one headline per outlet, its latest on the story, the most recent first. */
function itemsOf(byTime: StoryHeadline[]): OutletHeadline[] {
  if (byTime.length === 1) return [item(byTime[0])];
  const latest = new Map<string, StoryHeadline>();
  for (const headline of byTime) latest.set(headline.outlet.id, headline);
  return [...latest.values()].sort((a, b) => byText(b.publishedAt, a.publishedAt)).map(item);
}

function toStory(byTime: StoryHeadline[], typical: StoryHeadline, items: OutletHeadline[]): Story {
  return {
    id: hash(byTime[0].url),
    title: typical.title,
    items,
    firstSeen: byTime[0].publishedAt,
    lastSeen: items[0].publishedAt,
  };
}

/** One country's headlines grouped into stories, in the order they were found ([groupHeadlines]). */
export function clusterHeadlines(headlines: StoryHeadline[]): Story[] {
  const sorted = oldestFirst(headlines);
  const groups = groupHeadlines(sorted);
  const stories: Story[] = [];
  for (let g = 0; g < groups.groups; g++) {
    if (!groups.count[g]) continue;
    const byTime = byTimeOf(sorted, groups, g);
    stories.push(toStory(byTime, sorted[groups.typical[g]], itemsOf(byTime)));
  }
  return stories;
}

/**
 * The `count` weightiest of one country's stories at `now` ([storyScore]),
 * weightiest first, as clusterHeadlines' stories ranked: only those are made
 * into stories, of the 250 or so groups a big country has.
 */
export function topStories(headlines: StoryHeadline[], now: Date, count: number): Story[] {
  const sorted = oldestFirst(headlines);
  const groups = groupHeadlines(sorted);
  const kept: number[] = [];
  const scores: number[] = [];
  const items: (OutletHeadline[] | null)[] = [];
  for (let g = 0; g < groups.groups; g++) {
    const size = groups.count[g];
    if (!size) continue;
    kept.push(g);
    // A group of one: its one item's weight, as weight() sums it, and its items only if it is kept.
    if (size === 1) {
      scores.push(0 + itemWeight(sorted[groups.members[groups.start[g]]].publishedAt, now));
      items.push(null);
    } else {
      const list = itemsOf(byTimeOf(sorted, groups, g));
      scores.push(weight(list, now));
      items.push(list);
    }
  }
  // Weightiest first; of two alike, the one found first (a stable sort).
  const order: number[] = new Array(kept.length);
  for (let k = 0; k < kept.length; k++) order[k] = k;
  order.sort((a, b) => scores[b] - scores[a] || a - b);
  const stories: Story[] = [];
  for (let k = 0; k < order.length && k < count; k++) {
    const g = kept[order[k]];
    const byTime = byTimeOf(sorted, groups, g);
    stories.push(toStory(byTime, sorted[groups.typical[g]], items[order[k]] ?? itemsOf(byTime)));
  }
  return stories;
}

function itemWeight(publishedAt: string, now: Date): number {
  const hours = Math.max(0, (now.getTime() - Date.parse(publishedAt)) / 3_600_000);
  return 2 ** (-hours / STORIES.halfLifeHours);
}

function weight(items: OutletHeadline[], now: Date): number {
  let sum = 0;
  for (const item of items) sum += itemWeight(item.publishedAt, now);
  return sum;
}

/**
 * A story's weight at `now`: each outlet on it counts 1, halved every
 * `halfLifeHours` since its last headline on the story. Five outlets this hour
 * outweigh five yesterday, and two outlets one alone.
 */
export function storyScore(story: Story, now: Date): number {
  return weight(story.items, now);
}
