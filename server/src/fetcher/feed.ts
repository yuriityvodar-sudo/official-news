// RSS 2.0, RSS 1.0 (RDF) and Atom feeds. Read with regular expressions, which
// costs far less CPU than a full XML parser and is enough for flat feed items.
import { parseDate } from "./dates";
import { decodeEntities, htmlToText } from "./text";
import { type FoundItem, type SourceConfig, dateSpec } from "./types";

function unwrap(raw: string): string {
  const cdata = raw.match(/^\s*<!\[CDATA\[([\s\S]*?)\]\]>\s*$/);
  return cdata ? cdata[1] : raw.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1");
}

/** The raw content of the first `<name>` element (any namespace prefix given in `name`). */
function element(xml: string, name: string): string | null {
  const escaped = name.replace(/[.:]/g, "\\$&");
  const m = xml.match(new RegExp(`<${escaped}(?:\\s[^>]*)?>([\\s\\S]*?)</${escaped}>`, "i"));
  return m ? unwrap(m[1]) : null;
}

function attribute(tag: string, name: string): string | null {
  const m = tag.match(new RegExp(`\\s${name}\\s*=\\s*("([^"]*)"|'([^']*)')`, "i"));
  return m ? decodeEntities(m[2] ?? m[3] ?? "") : null;
}

function plain(xml: string, name: string): string | null {
  const raw = element(xml, name);
  return raw === null ? null : htmlToText(raw);
}

function atomLink(entry: string): string | null {
  const links = entry.match(/<link\b[^>]*\/?>/gi) ?? [];
  for (const tag of links) {
    const rel = attribute(tag, "rel");
    if (!rel || rel === "alternate") {
      const href = attribute(tag, "href");
      if (href) return href;
    }
  }
  return null;
}

function image(entry: string): string | null {
  for (const tag of entry.match(/<(?:media:content|media:thumbnail|enclosure)\b[^>]*>/gi) ?? []) {
    const type = attribute(tag, "type");
    const medium = attribute(tag, "medium");
    const url = attribute(tag, "url");
    if (url && (!type || type.startsWith("image/")) && (!medium || medium === "image")) return url;
  }
  return null;
}

export function parseFeed(xml: string, baseUrl: string, config: SourceConfig, now = new Date()): FoundItem[] {
  const blocks = xml.match(/<(item|entry)\b[^>]*>[\s\S]*?<\/\1>/gi) ?? [];
  const spec = dateSpec(config);
  const dateFields = spec.field ? [spec.field].flat() : ["pubDate", "dc:date", "published", "updated"];

  return blocks.flatMap((block): FoundItem[] => {
    const titleField = typeof config.title === "string" ? config.title : "title";
    const title = plain(block, titleField) ?? plain(block, "title") ?? "";
    const link = plain(block, "link") || atomLink(block) || plain(block, "guid") || "";
    if (!title || !link) return [];

    let url: string;
    try {
      url = new URL(link, baseUrl).toString();
    } catch {
      return [];
    }

    let date = null;
    for (const field of dateFields) {
      date = parseDate(plain(block, field), spec, now);
      if (date) break;
    }

    const content = element(block, "content:encoded") ?? element(block, "description") ?? element(block, "summary") ?? element(block, "content");
    const category = plain(block, "category") ?? attribute(block.match(/<category\b[^>]*>/i)?.[0] ?? "", "term");

    return [
      {
        url,
        title,
        publishedAt: date?.publishedAt ?? null,
        dateOnly: date?.dateOnly ?? false,
        text: content ? htmlToText(content) || null : null,
        imageUrl: image(block),
        category,
      },
    ];
  });
}
