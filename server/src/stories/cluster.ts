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

/** A headline's words as numbers (this call's), in increasing order, with their weights. */
interface Member {
  headline: StoryHeadline;
  /** Its rarest words that other headlines have too: the stories it is compared with share one. */
  leads: number[];
  ids: number[];
  weights: number[];
  norm: number;
  /** Its vector of length 1 (weights over norm), and that one's squared length as a group's centre sums it. */
  unit: Float64Array;
  unitSquared: number;
}

interface Group {
  members: Member[];
  /**
   * The sum of its headlines' vectors, each of length 1, by word (dense: a call has a few thousand
   * words), from its second headline on; a group of one is its headline's `unit`. And the sum's
   * squared length.
   */
  centre: Float64Array | null;
  centreSquared: number;
}

/**
 * How alike a headline and a group's centre are (cosine). The centre of a group of one is read
 * through `probe`, which holds the headline's weights by word: the same sum, in the same order
 * of words, as reading the centre by the headline's words, without a lookup each.
 */
function toCentre(member: Member, group: Group, probe: Float64Array): number {
  const centreNorm = Math.sqrt(group.centreSquared);
  if (!member.norm || !centreNorm) return 0;
  let dot = 0;
  const centre = group.centre;
  if (centre) {
    const { ids, weights } = member;
    for (let k = 0; k < ids.length; k++) dot += weights[k] * centre[ids[k]];
  } else {
    const { ids, unit } = group.members[0];
    for (let k = 0; k < ids.length; k++) dot += probe[ids[k]] * unit[k];
  }
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
 * Groups one country's headlines. Each word weighs by how rare it is among
 * these headlines (inverse document frequency), so names, places and numbers
 * decide and words every headline has do not. Oldest first, a headline joins
 * the group whose centre it is most like, from `joinAt` up, or starts one; it
 * is compared only with the groups that share one of its rarest words. Then
 * each headline left alone looks again, now that the groups have grown: a long
 * headline that came second, to a group of one short headline, joins the group
 * it is like, as long as it is like one of its headlines too.
 *
 * Written for a call that starts cold (2 Nov: Yurii's check of #282 on
 * Workers, 12 to 40 ms where a warmed-up laptop took 3): words are numbers
 * within the call, read once by the fetcher, and a headline's are sorted and
 * picked in plain loops, without the arrays and callbacks that cost most before
 * the code has warmed up.
 */
function groupHeadlines(headlines: StoryHeadline[]): Group[] {
  const sorted = headlines.slice().sort((a, b) => byText(a.publishedAt, b.publishedAt) || byText(a.url, b.url));
  const total = sorted.length;
  const termIds = new Map<string, number>();
  const idsOf: number[][] = new Array(total);
  const namesOf: boolean[][] = new Array(total);
  const number = (term: string): number => {
    let id = termIds.get(term);
    if (id === undefined) termIds.set(term, (id = termIds.size));
    return id;
  };
  for (let i = 0; i < total; i++) {
    const ids: number[] = [];
    const names: boolean[] = [];
    const words = sorted[i].words;
    if (Array.isArray(words)) {
      for (let k = 0; k < words.length; k++) {
        const word = words[k];
        const name = word.charCodeAt(0) === 94; // "^"
        ids.push(number(name ? word.slice(1) : word));
        names.push(name);
      }
    } else {
      for (const [term, name] of readTermsOnce(sorted[i].title)) {
        ids.push(number(term));
        names.push(name);
      }
    }
    idsOf[i] = ids;
    namesOf[i] = names;
  }
  const df = new Int32Array(termIds.size);
  for (let i = 0; i < total; i++) for (const id of idsOf[i]) df[id]++;
  const common = Math.max(STORIES.commonFloor, total * STORIES.commonShare);
  const corpus = Math.max(total, STORIES.idfHeadlines);
  // A word's weight by the number of headlines it is in: one log each, not one a word.
  const idf = new Float64Array(total + 1);
  for (let n = 1; n <= total; n++) idf[n] = Math.log(corpus / n);

  const groups: Group[] = [];
  const index: number[][] = new Array(termIds.size);
  for (let t = 0; t < index.length; t++) index[t] = [];
  const seen = new Int32Array(Math.max(1, total)).fill(-1);
  const probe = new Float64Array(termIds.size);
  let looked = 0;
  /** The group `member` is most like, from joinAt up, or -1; with `alone`, another group of 2 or more. */
  const best = (member: Member, alone: number): number => {
    looked++;
    let found = -1;
    let top = 0;
    const { ids, weights, leads } = member;
    for (let k = 0; k < ids.length; k++) probe[ids[k]] = weights[k];
    for (let l = 0; l < leads.length; l++) {
      const list = index[leads[l]];
      for (let x = 0; x < list.length; x++) {
        const g = list[x];
        if (seen[g] === looked || (alone >= 0 && (g === alone || groups[g].members.length < 2))) continue;
        seen[g] = looked;
        const s = toCentre(member, groups[g], probe);
        if (s > top) {
          found = g;
          top = s;
        }
      }
    }
    for (let k = 0; k < ids.length; k++) probe[ids[k]] = 0;
    return top >= STORIES.joinAt ? found : -1;
  };
  const join = (g: number, member: Member) => {
    const group = groups[g];
    group.members.push(member);
    if (group.members.length === 1) {
      // A group of one is its headline: its centre is the headline's vector of length 1.
      group.centreSquared = member.unitSquared;
      for (const id of member.ids) index[id].push(g);
      return;
    }
    let centre = group.centre;
    if (!centre) {
      centre = group.centre = new Float64Array(termIds.size);
      const first = group.members[0];
      for (let k = 0; k < first.ids.length; k++) centre[first.ids[k]] = first.unit[k];
    }
    const { ids, unit } = member;
    for (let k = 0; k < ids.length; k++) {
      const id = ids[k];
      const before = centre[id];
      const after = before + unit[k];
      centre[id] = after;
      group.centreSquared += after * after - before * before;
      if (before === 0) index[id].push(g);
    }
  };

  for (let i = 0; i < total; i++) {
    const unordered = idsOf[i];
    const names = namesOf[i];
    const m = unordered.length;
    // Its words in increasing order with their weights, by insertion: a headline has a dozen.
    const ids: number[] = new Array(m);
    const weights: number[] = new Array(m);
    for (let k = 0; k < m; k++) {
      const id = unordered[k];
      const weight = idf[df[id]] * (names[k] ? STORIES.nameWeight : 1);
      let j = k;
      for (; j > 0 && ids[j - 1] > id; j--) {
        ids[j] = ids[j - 1];
        weights[j] = weights[j - 1];
      }
      ids[j] = id;
      weights[j] = weight;
    }
    let squared = 0;
    for (let k = 0; k < m; k++) squared += weights[k] * weights[k];
    const norm = Math.sqrt(squared);
    const unit = new Float64Array(m);
    let unitSquared = 0;
    for (let k = 0; k < m; k++) {
      unit[k] = norm ? weights[k] / norm : 0;
      unitSquared += unit[k] * unit[k];
    }
    // Its rarest words that another headline has too, rarest first, the earlier of two alike first:
    // a word no other headline has leads nowhere.
    const leads: number[] = [];
    for (let k = 0; k < m; k++) {
      const id = unordered[k];
      const n = df[id];
      if (n <= 1 || n > common) continue;
      let at = leads.length;
      while (at > 0 && df[leads[at - 1]] > n) at--;
      if (at >= STORIES.leadTerms) continue;
      if (leads.length < STORIES.leadTerms) leads.push(id);
      for (let j = leads.length - 1; j > at; j--) leads[j] = leads[j - 1];
      leads[at] = id;
    }
    const member: Member = { headline: sorted[i], leads, ids, weights, norm, unit, unitSquared };
    const found = best(member, -1);
    join(found >= 0 ? found : groups.push({ members: [], centre: null, centreSquared: 0 }) - 1, member);
  }

  for (let g = 0; g < groups.length; g++) {
    const group = groups[g];
    if (group.members.length !== 1) continue;
    const alone = group.members[0];
    if (!alone.leads.length) continue;
    const found = best(alone, g);
    if (found < 0) continue;
    // Like the group's centre and like one of its headlines: a centre made of a few headlines of
    // the same kind (two shootings: "dead", "injured") draws a third of that kind.
    const members = groups[found].members;
    let like = false;
    for (let k = 0; k < members.length && !like; k++) like = toMember(alone, members[k]) >= STORIES.joinAt;
    if (!like) continue;
    join(found, alone);
    group.members = [];
  }
  return groups;
}

/** A headline as a story lists it: its words, link, time and outlet, and nothing the fetcher keeps for the build. */
const item = (h: StoryHeadline): OutletHeadline => ({ title: h.title, url: h.url, publishedAt: h.publishedAt, outlet: h.outlet });

/** A group's items: one headline per outlet, its latest on the story, the most recent first; and its members by time. */
function itemsOf(group: Group): { byTime: Member[]; items: OutletHeadline[] } {
  if (group.members.length === 1) return { byTime: group.members, items: [item(group.members[0].headline)] };
  const byTime = group.members.slice().sort((a, b) => byText(a.headline.publishedAt, b.headline.publishedAt));
  const latest = new Map<string, StoryHeadline>();
  for (const { headline } of byTime) latest.set(headline.outlet.id, headline);
  const items = [...latest.values()].sort((a, b) => byText(b.publishedAt, a.publishedAt)).map(item);
  return { byTime, items };
}

/** No probe: a group of two or more reads its own centre. */
const NO_PROBE = new Float64Array(0);

function toStory(group: Group, byTime: Member[], items: OutletHeadline[]): Story {
  // The headline nearest the centre; a group of one has only its own.
  let typical = byTime[0];
  if (byTime.length > 1) {
    let closest = toCentre(typical, group, NO_PROBE);
    for (let k = 1; k < byTime.length; k++) {
      const s = toCentre(byTime[k], group, NO_PROBE);
      if (s > closest) {
        typical = byTime[k];
        closest = s;
      }
    }
  }
  return {
    id: hash(byTime[0].headline.url),
    title: typical.headline.title,
    items,
    firstSeen: byTime[0].headline.publishedAt,
    lastSeen: items[0].publishedAt,
  };
}

/** One country's headlines grouped into stories, in the order they were found ([groupHeadlines]). */
export function clusterHeadlines(headlines: StoryHeadline[]): Story[] {
  const stories: Story[] = [];
  for (const group of groupHeadlines(headlines)) {
    if (!group.members.length) continue;
    const { byTime, items } = itemsOf(group);
    stories.push(toStory(group, byTime, items));
  }
  return stories;
}

/**
 * The `count` weightiest of one country's stories at `now` ([storyScore]),
 * weightiest first, as clusterHeadlines' stories ranked: only those are made
 * into stories, of the 250 or so groups a big country has.
 */
export function topStories(headlines: StoryHeadline[], now: Date, count: number): Story[] {
  const groups = groupHeadlines(headlines);
  const kept: number[] = [];
  const scores: number[] = [];
  const parts: ({ byTime: Member[]; items: OutletHeadline[] } | null)[] = [];
  for (let g = 0; g < groups.length; g++) {
    const members = groups[g].members;
    if (!members.length) continue;
    kept.push(g);
    // A group of one: its one item's weight, as weight() sums it, and its items only if it is kept.
    if (members.length === 1) {
      scores.push(0 + itemWeight(members[0].headline.publishedAt, now));
      parts.push(null);
    } else {
      const part = itemsOf(groups[g]);
      scores.push(weight(part.items, now));
      parts.push(part);
    }
  }
  // Weightiest first; of two alike, the one found first (a stable sort).
  const order: number[] = new Array(kept.length);
  for (let k = 0; k < kept.length; k++) order[k] = k;
  order.sort((a, b) => scores[b] - scores[a] || a - b);
  const stories: Story[] = [];
  for (let k = 0; k < order.length && k < count; k++) {
    const group = groups[kept[order[k]]];
    const part = parts[order[k]] ?? itemsOf(group);
    stories.push(toStory(group, part.byTime, part.items));
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
