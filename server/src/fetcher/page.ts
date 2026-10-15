// HTML pages: news lists read with the CSS selectors in a source's config, and
// the main text of an item page. HTMLRewriter streams the page natively, so
// big pages cost little CPU. It hands over raw text: entities are decoded here.
import { parseDate } from "./dates";
import { cleanText, decodeEntities } from "./text";
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

/** Runs `fn` at the element's end tag; elements that cannot have one (br, img) end at once. */
function atEnd(el: Element, fn: () => void): void {
  try {
    el.onEndTag(fn);
  } catch {
    fn();
  }
}

const SKIPPED = "script, style, noscript, template, svg";

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
    rewriter.on(`${config.item} ${selector}`, {
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
        imageUrl: absolute(raw.image, baseUrl),
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

export async function extractContent(html: string, baseUrl: string, textSelector?: string): Promise<PageContent> {
  const containers = textSelector ? [textSelector] : ["main", "article", "body"];
  const buffers = containers.map(() => "");
  const depth = containers.map(() => 0);
  const newline = () => {
    for (let i = 0; i < containers.length; i++) if (depth[i] > 0) buffers[i] += "\n";
  };
  let skipping = 0;
  let image: string | null = null;

  const rewriter = new HTMLRewriter()
    .on('meta[property="og:image"], meta[name="twitter:image"]', {
      element(el) {
        image ??= el.getAttribute("content");
      },
    })
    .on(`${SKIPPED}, nav, header, footer, aside`, {
      element(el) {
        skipping++;
        atEnd(el, () => {
          skipping--;
        });
      },
    })
    // Paragraph breaks, so sentences from different blocks do not run together.
    .on("p, br, li, h1, h2, h3, h4, h5, h6, tr, div, section", {
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
        if (skipping === 0 && depth[i] > 0) buffers[i] += chunk.text;
      },
    });
  });

  await rewriter.transform(new Response(html)).arrayBuffer();

  const texts = buffers.map((b) => cleanText(decodeEntities(b)));
  const text = texts.find((t) => t.length >= 200) ?? texts.reduce((a, b) => (b.length > a.length ? b : a), "");
  return { text, imageUrl: absolute(image ?? undefined, baseUrl) };
}
