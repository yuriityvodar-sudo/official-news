// HTML pages: news lists read with the CSS selectors in a source's config, and
// the main text of an item page. HTMLRewriter streams the page natively, so
// big pages cost little CPU. It hands over raw text: entities are decoded here.
import { parseDate } from "./dates";
import { cleanText, decodeEntities, pictureUrl } from "./text";
import { type FoundItem, type SourceConfig, dateSpec } from "./types";

type FieldName = "link" | "title" | "summary" | "image" | "category" | "date";

/** Text or attribute values collected for one list item. */
type RawItem = Partial<Record<FieldName, string>>;

interface Target {
  selector: string;
  attr: string | null;
}

/** `selector@attr`, `@attr` or `selector`. */
function splitSpec(spec: string, defaultAttr: string | null): Target {
  const at = spec.lastIndexOf("@");
  // An "@" inside an attribute selector such as [href^="mailto:x@y"] is not ours.
  if (at >= 0 && !spec.slice(at).includes("]")) {
    return { selector: spec.slice(0, at).trim(), attr: spec.slice(at + 1).trim() };
  }
  return { selector: spec.trim(), attr: defaultAttr };
}

/** The parts of a selector list, split at commas outside brackets, parentheses and quotes. */
function selectorList(selector: string): string[] {
  const parts: string[] = [];
  let depth = 0;
  let quote: string | null = null;
  let start = 0;
  for (let i = 0; i < selector.length; i++) {
    const c = selector[i];
    if (quote) {
      if (c === quote) quote = null;
    } else if (c === '"' || c === "'") {
      quote = c;
    } else if (c === "[" || c === "(") {
      depth++;
    } else if (c === "]" || c === ")") {
      depth--;
    } else if (c === "," && depth === 0) {
      parts.push(selector.slice(start, i).trim());
      start = i + 1;
    }
  }
  parts.push(selector.slice(start).trim());
  return parts.filter(Boolean);
}

/** `item field` for every part of both lists, so ".time, .date" finds both inside the item, never outside it. */
function withinItem(item: string, field: string): string {
  return selectorList(item)
    .flatMap((i) => selectorList(field).map((f) => `${i} ${f}`))
    .join(", ");
}

/** HTML elements that never have an end tag. */
const VOID = new Set(["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"]);

/** Runs `fn` at the element's end tag; elements that cannot have one (br, img) end at once. */
function atEnd(el: Element, fn: () => void): void {
  // Known void elements skip the exception onEndTag throws for them: on a page of
  // 2,400 <br> (an Argentine norm) the exceptions were a large part of the CPU (#71).
  if (VOID.has(el.tagName)) {
    fn();
    return;
  }
  try {
    el.onEndTag(fn);
  } catch {
    fn();
  }
}

const SKIPPED = "script, style, noscript, template, svg";

/** Item pages are handed to the HTML reader in pieces this big, so reading can stop early. */
const PIECE_BYTES = 8192;

function absolute(link: string | undefined, baseUrl: string): string | null {
  if (!link?.trim()) return null;
  try {
    return new URL(decodeEntities(link.trim()), baseUrl).toString();
  } catch {
    return null;
  }
}

export async function parsePage(html: string, baseUrl: string, config: SourceConfig, now = new Date()): Promise<FoundItem[]> {
  if (!config.item) return [];
  const date = dateSpec(config);
  const link = splitSpec(config.link ?? "a", "href");
  const targets: [FieldName, Target][] = [
    ["link", link],
    // Without a title selector, the title is the link's text.
    ["title", config.title ? splitSpec(config.title, null) : { selector: link.selector, attr: null }],
  ];
  if (config.summary) targets.push(["summary", splitSpec(config.summary, null)]);
  if (config.image) targets.push(["image", splitSpec(config.image, "src")]);
  if (config.category) targets.push(["category", splitSpec(config.category, null)]);
  if (date.selector) targets.push(["date", { selector: date.selector, attr: date.attr ?? null }]);

  const items: RawItem[] = [];
  const current = () => items[items.length - 1];
  const itemAttrs: [FieldName, string][] = [];
  const rewriter = new HTMLRewriter();

  // Text inside scripts and styles is never part of a field.
  let skipping = 0;
  rewriter.on(SKIPPED, {
    element(el) {
      skipping++;
      atEnd(el, () => {
        skipping--;
      });
    },
  });

  // Registered before the field handlers, so a new item exists before its fields are read.
  rewriter.on(config.item, {
    element(el) {
      const item: RawItem = {};
      for (const [field, attr] of itemAttrs) {
        const value = el.getAttribute(attr);
        if (value !== null) item[field] = value;
      }
      items.push(item);
    },
  });

  for (const [field, { selector, attr }] of targets) {
    if (!selector) {
      // `@attr`: an attribute of the item element itself.
      if (attr) itemAttrs.push([field, attr]);
      continue;
    }
    let capturing = false;
    rewriter.on(withinItem(config.item, selector), {
      element(el) {
        const item = current();
        if (!item || item[field] !== undefined) return; // the first match wins
        if (attr) {
          const value = el.getAttribute(attr);
          if (value !== null) item[field] = value;
          return;
        }
        item[field] = "";
        capturing = true;
        atEnd(el, () => {
          capturing = false;
        });
      },
      text(chunk) {
        const item = current();
        if (capturing && skipping === 0 && item) item[field] += chunk.text;
      },
    });
  }

  await rewriter.transform(new Response(html)).arrayBuffer();

  return items.flatMap((raw): FoundItem[] => {
    const title = cleanText(decodeEntities(raw.title ?? ""));
    const url = absolute(raw.link, baseUrl);
    if (!url || !title) return [];

    let parsed = null;
    if (date.fromLink) {
      const m = url.match(new RegExp(date.fromLink));
      if (m?.[1]?.length === 8) parsed = parseDate(`${m[1].slice(0, 4)}-${m[1].slice(4, 6)}-${m[1].slice(6, 8)}`, date, now);
    } else if (raw.date !== undefined) {
      parsed = parseDate(cleanText(decodeEntities(raw.date)), date, now);
    }

    const summary = raw.summary ? cleanText(decodeEntities(raw.summary)) : "";
    return [
      {
        url,
        title,
        publishedAt: parsed?.publishedAt ?? null,
        dateOnly: parsed?.dateOnly ?? false,
        text: summary || null,
        imageUrl: pictureUrl(absolute(raw.image, baseUrl), baseUrl),
        category: raw.category ? cleanText(decodeEntities(raw.category)) : null,
      },
    ];
  });
}

/** The main text and preview image of an item page. */
export interface PageContent {
  text: string;
  imageUrl: string | null;
}

/** The first link on a page matching `spec` (`selector@attr`, default `href`), as an absolute URL. */
export async function findLink(html: string, baseUrl: string, spec: string): Promise<string | null> {
  const { selector, attr } = splitSpec(spec, "href");
  let found: string | null = null;
  await new HTMLRewriter()
    .on(selector, {
      element(el) {
        found ??= el.getAttribute(attr ?? "href");
      },
    })
    .transform(new Response(html))
    .arrayBuffer();
  return absolute(found ?? undefined, baseUrl);
}

/**
 * The main text of an item page: `textSelector`, else the first of `main`,
 * `article`, `body` with 200 characters. Reading stops once the text kept is
 * `maxChars` long, since the rest would be cut anyway: the work is bounded by
 * the text, not by the size of the page (#71: an Argentine norm of 198 KB took
 * about 25 ms locally to read whole, its first 20,000 characters about 3).
 */
export async function extractContent(html: string, baseUrl: string, textSelector?: string, maxChars = Infinity): Promise<PageContent> {
  const containers = textSelector ? [textSelector] : ["main", "article", "body"];
  const buffers = containers.map(() => "");
  const depth = containers.map(() => 0);
  const newline = () => {
    for (let i = 0; i < containers.length; i++) if (depth[i] > 0) buffers[i] += "\n";
  };
  let skipping = 0;
  let image: string | null = null;
  // With a single text selector only the elements inside it matter, so the handlers
  // below watch only those (#71, measured locally on a 122 KB Bundesregierung page:
  // about 17 ms with the default containers, under 1 ms with the selector). A
  // selector list ("a, b") works, but keeps the page-wide handlers and their CPU.
  const inside = (selectors: string) =>
    textSelector && !textSelector.includes(",") ? selectors.split(", ").map((s) => `${textSelector} ${s}`).join(", ") : selectors;

  const length = (raw: string) => cleanText(decodeEntities(raw)).length;
  // Raw text has more spaces than clean text, so the clean length is checked when the
  // raw one passes the mark, and the mark moves by what is still missing.
  const nextCheck = containers.map(() => maxChars);
  let enough = false;
  const isEnough = (i: number): boolean => {
    if (buffers[i].length < nextCheck[i]) return false;
    // A container earlier in the list is used when it has 200 characters: then this one
    // no longer matters, and while that one is open it can still get them.
    for (let j = 0; j < i; j++) {
      if (length(buffers[j]) >= 200) {
        nextCheck[i] = Infinity;
        return false;
      }
      if (depth[j] > 0) {
        nextCheck[i] = buffers[i].length + 4096;
        return false;
      }
    }
    const n = length(buffers[i]);
    nextCheck[i] = buffers[i].length + Math.max(maxChars - n, 1024);
    return n >= maxChars;
  };

  const rewriter = new HTMLRewriter()
    .on('meta[property="og:image"], meta[name="twitter:image"]', {
      element(el) {
        // The first usable one: a site root (no photo on the page) lets twitter:image answer.
        image ??= pictureUrl(absolute(el.getAttribute("content") ?? undefined, baseUrl), baseUrl);
      },
    })
    // Picture captions and credits ("Foto: …") are not the article's text.
    .on(inside(`${SKIPPED}, nav, header, footer, aside, figcaption`), {
      element(el) {
        skipping++;
        atEnd(el, () => {
          skipping--;
        });
      },
    })
    // Paragraph breaks, so sentences from different blocks do not run together.
    .on(inside("p, br, li, h1, h2, h3, h4, h5, h6, tr, div, section"), {
      element(el) {
        newline();
        atEnd(el, newline);
      },
    });

  containers.forEach((selector, i) => {
    rewriter.on(selector, {
      element(el) {
        depth[i]++;
        atEnd(el, () => {
          depth[i]--;
        });
      },
      text(chunk) {
        if (skipping === 0 && depth[i] > 0) {
          buffers[i] += chunk.text;
          if (!enough && isEnough(i)) enough = true;
        }
      },
    });
  });

  // The page goes in piece by piece, and no more once there is enough text.
  const bytes = new TextEncoder().encode(html);
  let offset = 0;
  const input = new ReadableStream<Uint8Array>(
    {
      pull(controller) {
        if (enough || offset >= bytes.length) {
          controller.close();
          return;
        }
        controller.enqueue(bytes.subarray(offset, offset + PIECE_BYTES));
        offset += PIECE_BYTES;
      },
    },
    { highWaterMark: 0 },
  );
  await rewriter.transform(new Response(input)).arrayBuffer();

  const texts = buffers.map((b) => cleanText(decodeEntities(b)));
  const text = texts.find((t) => t.length >= 200) ?? texts.reduce((a, b) => (b.length > a.length ? b : a), "");
  return { text, imageUrl: image };
}
