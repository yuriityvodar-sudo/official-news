// The stories' grouping (#230, the aggregator) in WebAssembly: the loops of
// src/stories/cluster.ts's grouping, which a call that starts cold ran too
// slowly as JavaScript (2 Nov: India's 300 headlines took about 12 ms of a
// call's 10), and the words' numbers (3 Nov: about 1 ms of Germany's build).
// WebAssembly runs fast from the call's start. The same steps in the same
// order, with the same sums, so the same stories: cluster.ts says what each
// step is for and why.
//
// Built into src/stories/group.wasm by `npm run build:wasm` (AssemblyScript);
// `npm test` checks that the committed file is this source's build. All
// memory is laid out by cluster.ts, which writes its offsets in the header:
// this module only reads and writes there, and allocates nothing.

// The header: byte offsets of the arrays, by slot (cluster.ts, SLOTS).
const N = 0; // headlines, oldest first
const TERMS = 1; // their distinct words
const LEADS = 2; // words a headline is compared by, at most
const WORD_START = 3; // i32[n + 1]: headline i's words are at [start[i], start[i + 1])
const IDS = 4; // i32[w]: each headline's words as read
const NAMES = 5; // i32[w]: 1 for a word written as a name
const IDF = 6; // f64[n + 1]: a word's weight by the number of headlines it is in
const RANK = 7; // i32[n]: the headline's time, as a rank (equal times, equal ranks)
const SORTED = 8; // i32[w]: each headline's words in increasing order
const WEIGHTS = 9; // f64[w]: their weights
const UNITS = 10; // f64[w]: their weights over the headline's norm
const NORM = 11; // f64[n]
const UNIT_SQUARED = 12; // f64[n]
const LEAD = 13; // i32[n * leads]: the rarest words a headline shares
const LEAD_COUNT = 14; // i32[n]
const DF = 15; // i32[terms]: headlines a word is in
const PROBE = 16; // f64[terms]: the weights of the headline being compared
const SEEN = 17; // i32[n]: the comparison a group was last looked at in
const COUNT = 18; // i32[n]: a group's headlines (out: 0 for a group emptied)
const HEAD = 19; // i32[n]: a group's first headline...
const TAIL = 20; // i32[n]: ...and last, in the order they joined
const NEXT = 21; // i32[n]: the headline that joined a group after this one
const SQUARED = 22; // f64[n]: a group's centre's squared length
const CENTRE = 23; // i32[n]: a group's centre block, -1 for a group of one
const POST_HEAD = 24; // i32[terms]: the groups a word is in...
const POST_TAIL = 25; // i32[terms]
const POST_GROUP = 26; // i32[postings]
const POST_NEXT = 27; // i32[postings]
const CENTRES = 28; // f64[terms] blocks: centres of groups of two or more
const OUT_START = 29; // i32[n]: where a group's headlines are in OUT_MEMBERS
const OUT_MEMBERS = 30; // i32[n]: each group's headlines in time order
const OUT_TYPICAL = 31; // i32[n]: each group's headline nearest its centre
const COMMON = 32; // f64 (two slots): a word in more headlines leads to no group
const JOIN_AT = 34; // f64: how alike a headline must be to join
const NAME_WEIGHT = 36; // f64: a name's weight over a word's
// The words' numbers (number), laid out first: the arrays above are sized by them.
const TEXT = 38; // u8[textLength]: the headlines' words as UTF-8, a line each
const TEXT_LENGTH = 39;
const TABLE = 40; // i32[tableMask + 1]: the words' numbers by their hash, -1 for none
const TABLE_MASK = 41; // the table's size less one: a power of two less one
const TERM_START = 42; // i32[terms]: where a word is first in TEXT...
const TERM_LENGTH = 43; // ...its bytes...
const TERM_HASH = 44; // ...and its hash
const WORDS = 45; // out: the headlines' words in all

let header: usize = 0;
let terms: i32 = 0;
let leads: i32 = 0;
let joinAt: f64 = 0;
let looked: i32 = 0;
let groups: i32 = 0;
let centres: i32 = 0;
let postings: i32 = 0;

@inline function at(slot: i32): usize {
  return <usize>load<i32>(header + (<usize>slot << 2));
}
@inline function i32At(slot: i32, i: i32): i32 {
  return load<i32>(at(slot) + (<usize>i << 2));
}
@inline function setI32(slot: i32, i: i32, value: i32): void {
  store<i32>(at(slot) + (<usize>i << 2), value);
}
@inline function f64At(slot: i32, i: i32): f64 {
  return load<f64>(at(slot) + (<usize>i << 3));
}
@inline function setF64(slot: i32, i: i32, value: f64): void {
  store<f64>(at(slot) + (<usize>i << 3), value);
}
@inline function param(slot: i32): f64 {
  return load<f64>(header + (<usize>slot << 2));
}
/** JavaScript's truthiness of a number: neither 0 nor NaN. */
@inline function truthy(x: f64): bool {
  return x != 0 && !isNaN(x);
}
@inline function block(c: i32): usize {
  return at(CENTRES) + ((<usize>c * <usize>terms) << 3);
}

/** Where the arrays may start: past this module's own data. */
export function heap(): usize {
  return (__heap_base + 7) & ~7;
}

/**
 * The headlines' words as numbers (groupHeadlines): TEXT holds them as the
 * fetcher keeps them (headlineWords), a line a headline, separated by spaces,
 * a name's with "^" first. A word gets the next number when it is first
 * found, in the text's order, as a Map numbered them before: its bytes are
 * looked up by their hash (32-bit FNV-1a). Fills WORD_START, IDS and NAMES,
 * and the header's TERMS and WORDS; returns the distinct words.
 */
export function number(base: usize): i32 {
  header = base;
  const n = load<i32>(header + (<usize>N << 2));
  const end = at(TEXT) + <usize>load<i32>(header + (<usize>TEXT_LENGTH << 2));
  const table = at(TABLE);
  const mask = <u32>load<i32>(header + (<usize>TABLE_MASK << 2));
  memory.fill(table, 0xff, (<usize>mask + 1) << 2);
  let p = at(TEXT);
  let words = 0;
  let count = 0;
  for (let i = 0; i < n; i++) {
    setI32(WORD_START, i, words);
    while (p < end) {
      let c = load<u8>(p);
      // "\n": the next headline's words.
      if (c == 0x0a) {
        p++;
        break;
      }
      if (c == 0x20) {
        p++;
        continue;
      }
      const name = c == 0x5e; // "^"
      if (name) p++;
      const start = p;
      let hash: u32 = 0x811c9dc5;
      while (p < end) {
        c = load<u8>(p);
        if (c == 0x20 || c == 0x0a) break;
        hash = (hash ^ <u32>c) * 0x01000193;
        p++;
      }
      const length = <i32>(p - start);
      let slot = hash & mask;
      let id = load<i32>(table + (<usize>slot << 2));
      while (
        id >= 0 &&
        !(<u32>i32At(TERM_HASH, id) == hash && i32At(TERM_LENGTH, id) == length && memory.compare(<usize>i32At(TERM_START, id), start, <usize>length) == 0)
      ) {
        slot = (slot + 1) & mask;
        id = load<i32>(table + (<usize>slot << 2));
      }
      if (id < 0) {
        id = count++;
        store<i32>(table + (<usize>slot << 2), id);
        setI32(TERM_START, id, <i32>start);
        setI32(TERM_LENGTH, id, length);
        setI32(TERM_HASH, id, <i32>hash);
      }
      setI32(IDS, words, id);
      setI32(NAMES, words, name ? 1 : 0);
      words++;
    }
  }
  setI32(WORD_START, n, words);
  store<i32>(header + (<usize>TERMS << 2), count);
  store<i32>(header + (<usize>WORDS << 2), words);
  return count;
}

/** A word's group added to the groups it is in, last. */
function post(term: i32, g: i32): void {
  const p = postings++;
  setI32(POST_GROUP, p, g);
  setI32(POST_NEXT, p, -1);
  const tail = i32At(POST_TAIL, term);
  if (tail < 0) setI32(POST_HEAD, term, p);
  else setI32(POST_NEXT, tail, p);
  setI32(POST_TAIL, term, p);
}

/** How alike headline i and group g's centre are (toCentre). */
function toCentre(i: i32, g: i32): f64 {
  const centreNorm = Math.sqrt(f64At(SQUARED, g));
  const norm = f64At(NORM, i);
  if (!truthy(norm) || !truthy(centreNorm)) return 0;
  let dot: f64 = 0;
  const c = i32At(CENTRE, g);
  if (c >= 0) {
    const centre = block(c);
    for (let k = i32At(WORD_START, i), end = i32At(WORD_START, i + 1); k < end; k++) {
      dot += f64At(WEIGHTS, k) * load<f64>(centre + (<usize>i32At(SORTED, k) << 3));
    }
  } else {
    const first = i32At(HEAD, g);
    for (let k = i32At(WORD_START, first), end = i32At(WORD_START, first + 1); k < end; k++) {
      dot += f64At(PROBE, i32At(SORTED, k)) * f64At(UNITS, k);
    }
  }
  return dot / (norm * centreNorm);
}

/** How alike two headlines are (toMember). */
function toMember(a: i32, b: i32): f64 {
  const normA = f64At(NORM, a);
  const normB = f64At(NORM, b);
  if (!truthy(normA) || !truthy(normB)) return 0;
  let dot: f64 = 0;
  let i = i32At(WORD_START, a);
  let j = i32At(WORD_START, b);
  const endA = i32At(WORD_START, a + 1);
  const endB = i32At(WORD_START, b + 1);
  while (i < endA && j < endB) {
    const x = i32At(SORTED, i);
    const y = i32At(SORTED, j);
    if (x == y) dot += f64At(WEIGHTS, i++) * f64At(WEIGHTS, j++);
    else if (x < y) i++;
    else j++;
  }
  return dot / (normA * normB);
}

/** The group headline i is most like, from joinAt up, or -1; with `alone`, another group of 2 or more (best). */
function best(i: i32, alone: i32): i32 {
  looked++;
  let found = -1;
  let top: f64 = 0;
  const start = i32At(WORD_START, i);
  const end = i32At(WORD_START, i + 1);
  for (let k = start; k < end; k++) setF64(PROBE, i32At(SORTED, k), f64At(WEIGHTS, k));
  const count = i32At(LEAD_COUNT, i);
  for (let l = 0; l < count; l++) {
    for (let p = i32At(POST_HEAD, i32At(LEAD, i * leads + l)); p >= 0; p = i32At(POST_NEXT, p)) {
      const g = i32At(POST_GROUP, p);
      if (i32At(SEEN, g) == looked || (alone >= 0 && (g == alone || i32At(COUNT, g) < 2))) continue;
      setI32(SEEN, g, looked);
      const s = toCentre(i, g);
      if (s > top) {
        found = g;
        top = s;
      }
    }
  }
  for (let k = start; k < end; k++) setF64(PROBE, i32At(SORTED, k), 0);
  return top >= joinAt ? found : -1;
}

/** Headline i joins group g, a new one when g has none yet (join). */
function join(g: i32, i: i32): void {
  setI32(NEXT, i, -1);
  const count = i32At(COUNT, g);
  const start = i32At(WORD_START, i);
  const end = i32At(WORD_START, i + 1);
  if (count == 0) {
    // A group of one is its headline: its centre is the headline's vector of length 1.
    setI32(HEAD, g, i);
    setI32(TAIL, g, i);
    setI32(COUNT, g, 1);
    setF64(SQUARED, g, f64At(UNIT_SQUARED, i));
    for (let k = start; k < end; k++) post(i32At(SORTED, k), g);
    return;
  }
  setI32(NEXT, i32At(TAIL, g), i);
  setI32(TAIL, g, i);
  setI32(COUNT, g, count + 1);
  let c = i32At(CENTRE, g);
  if (c < 0) {
    c = centres++;
    setI32(CENTRE, g, c);
    memory.fill(block(c), 0, <usize>terms << 3);
    const first = i32At(HEAD, g);
    const centre = block(c);
    for (let k = i32At(WORD_START, first), stop = i32At(WORD_START, first + 1); k < stop; k++) {
      store<f64>(centre + (<usize>i32At(SORTED, k) << 3), f64At(UNITS, k));
    }
  }
  const centre = block(c);
  let squared = f64At(SQUARED, g);
  for (let k = start; k < end; k++) {
    const id = i32At(SORTED, k);
    const before = load<f64>(centre + (<usize>id << 3));
    const after = before + f64At(UNITS, k);
    store<f64>(centre + (<usize>id << 3), after);
    squared += after * after - before * before;
    if (before == 0) post(id, g);
  }
  setF64(SQUARED, g, squared);
}

/**
 * Groups the headlines laid out at `base` (groupHeadlines): the first pass,
 * the second for headlines left alone, then each group's headlines in time
 * order and the one nearest its centre. Returns how many groups it made.
 */
export function group(base: usize): i32 {
  header = base;
  const n = load<i32>(header + (<usize>N << 2));
  terms = load<i32>(header + (<usize>TERMS << 2));
  leads = load<i32>(header + (<usize>LEADS << 2));
  const common = param(COMMON);
  joinAt = param(JOIN_AT);
  const nameWeight = param(NAME_WEIGHT);
  looked = 0;
  groups = 0;
  centres = 0;
  postings = 0;
  // The work areas, as new: a call's isolate keeps this memory for the next one.
  memory.fill(at(DF), 0, <usize>terms << 2);
  memory.fill(at(PROBE), 0, <usize>terms << 3);
  memory.fill(at(POST_HEAD), 0xff, <usize>terms << 2);
  memory.fill(at(POST_TAIL), 0xff, <usize>terms << 2);
  memory.fill(at(SEEN), 0xff, <usize>n << 2);
  memory.fill(at(COUNT), 0, <usize>n << 2);
  memory.fill(at(CENTRE), 0xff, <usize>n << 2);
  memory.fill(at(SQUARED), 0, <usize>n << 3);

  for (let i = 0; i < n; i++) {
    for (let k = i32At(WORD_START, i), end = i32At(WORD_START, i + 1); k < end; k++) {
      const id = i32At(IDS, k);
      setI32(DF, id, i32At(DF, id) + 1);
    }
  }

  for (let i = 0; i < n; i++) {
    const start = i32At(WORD_START, i);
    const m = i32At(WORD_START, i + 1) - start;
    // Its words in increasing order with their weights, by insertion.
    for (let k = 0; k < m; k++) {
      const id = i32At(IDS, start + k);
      const weight = f64At(IDF, i32At(DF, id)) * (i32At(NAMES, start + k) ? nameWeight : 1.0);
      let j = k;
      for (; j > 0 && i32At(SORTED, start + j - 1) > id; j--) {
        setI32(SORTED, start + j, i32At(SORTED, start + j - 1));
        setF64(WEIGHTS, start + j, f64At(WEIGHTS, start + j - 1));
      }
      setI32(SORTED, start + j, id);
      setF64(WEIGHTS, start + j, weight);
    }
    let squared: f64 = 0;
    for (let k = 0; k < m; k++) squared += f64At(WEIGHTS, start + k) * f64At(WEIGHTS, start + k);
    const norm = Math.sqrt(squared);
    setF64(NORM, i, norm);
    let unitSquared: f64 = 0;
    for (let k = 0; k < m; k++) {
      const unit = truthy(norm) ? f64At(WEIGHTS, start + k) / norm : 0;
      setF64(UNITS, start + k, unit);
      unitSquared += unit * unit;
    }
    setF64(UNIT_SQUARED, i, unitSquared);
    // Its rarest words that another headline has too, rarest first, the earlier of two alike first.
    let count = 0;
    const lead = i * leads;
    for (let k = 0; k < m; k++) {
      const id = i32At(IDS, start + k);
      const df = i32At(DF, id);
      if (df <= 1 || <f64>df > common) continue;
      let place = count;
      while (place > 0 && i32At(DF, i32At(LEAD, lead + place - 1)) > df) place--;
      if (place >= leads) continue;
      if (count < leads) count++;
      for (let j = count - 1; j > place; j--) setI32(LEAD, lead + j, i32At(LEAD, lead + j - 1));
      setI32(LEAD, lead + place, id);
    }
    setI32(LEAD_COUNT, i, count);
    const found = best(i, -1);
    join(found >= 0 ? found : groups++, i);
  }

  for (let g = 0; g < groups; g++) {
    if (i32At(COUNT, g) != 1) continue;
    const alone = i32At(HEAD, g);
    if (!i32At(LEAD_COUNT, alone)) continue;
    const found = best(alone, g);
    if (found < 0) continue;
    // Like the group's centre and like one of its headlines.
    let like = false;
    for (let m = i32At(HEAD, found); m >= 0 && !like; m = i32At(NEXT, m)) like = toMember(alone, m) >= joinAt;
    if (!like) continue;
    join(found, alone);
    setI32(COUNT, g, 0);
    setI32(HEAD, g, -1);
  }

  let place = 0;
  for (let g = 0; g < groups; g++) {
    const count = i32At(COUNT, g);
    setI32(OUT_START, g, place);
    if (!count) continue;
    // Its headlines in the order they joined, then by time, the earlier joined first of two alike.
    let k = 0;
    for (let m = i32At(HEAD, g); m >= 0; m = i32At(NEXT, m)) setI32(OUT_MEMBERS, place + k++, m);
    for (let x = 1; x < count; x++) {
      const member = i32At(OUT_MEMBERS, place + x);
      const rank = i32At(RANK, member);
      let y = x;
      for (; y > 0 && i32At(RANK, i32At(OUT_MEMBERS, place + y - 1)) > rank; y--) setI32(OUT_MEMBERS, place + y, i32At(OUT_MEMBERS, place + y - 1));
      setI32(OUT_MEMBERS, place + y, member);
    }
    // The first of its headlines nearest its centre, in time order.
    let typical = i32At(OUT_MEMBERS, place);
    if (count > 1) {
      let closest = toCentre(typical, g);
      for (let x = 1; x < count; x++) {
        const member = i32At(OUT_MEMBERS, place + x);
        const s = toCentre(member, g);
        if (s > closest) {
          typical = member;
          closest = s;
        }
      }
    }
    setI32(OUT_TYPICAL, g, typical);
    place += count;
  }
  return groups;
}
