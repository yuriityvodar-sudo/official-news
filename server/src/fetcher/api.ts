// JSON APIs, mapped with the paths and `{path}` templates in a source's config.
import { parseDate } from "./dates";
import { cleanText, decodeEntities, fillTemplate, getPath } from "./text";
import { type FoundItem, type SourceConfig, configRegex, dateSpec } from "./types";

export function parseApi(json: unknown, baseUrl: string, config: SourceConfig, now = new Date()): FoundItem[] {
  const list = getPath(json, config.items ?? "");
  if (!Array.isArray(list)) return [];
  const spec = dateSpec(config);
  const dateFields = [spec.field ?? []].flat();

  return list.flatMap((entry): FoundItem[] => {
    const item = config.itemRoot ? getPath(entry, config.itemRoot) : entry;
    if (!item || typeof item !== "object") return [];

    for (const [path, pattern] of Object.entries(config.keep ?? {})) {
      if (!configRegex(pattern).test(String(getPath(item, path) ?? ""))) return [];
    }

    const title = cleanText(decodeEntities(fillTemplate(config.title ?? "title", item)));
    const link = fillTemplate(config.link ?? "url", item);
    if (!title || !link) return [];
    let url: string;
    try {
      url = new URL(link, baseUrl).toString();
    } catch {
      return [];
    }
    if (config.key) url += `#${encodeURIComponent(fillTemplate(config.key, item))}`;

    let date = null;
    for (const field of dateFields) {
      date = parseDate(fillTemplate(field, item), spec, now);
      if (date) break;
    }

    const text = config.text ? cleanText(decodeEntities(fillTemplate(config.text, item))) : "";
    return [
      {
        url,
        title,
        publishedAt: date?.publishedAt ?? null,
        dateOnly: date?.dateOnly ?? false,
        text: text || null,
        imageUrl: null,
        category: null,
      },
    ];
  });
}
