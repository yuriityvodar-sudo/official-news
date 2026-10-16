// HTML built from template literals (#88). Every value is escaped unless it is
// already Html, every attribute is quoted, and links from the data pass through
// safeHttps, so text from a source site or the AI can never become markup.

/** Markup that is already safe: made only by `html`, `raw` and `t()` (texts.ts). */
export class Html {
  constructor(readonly value: string) {}
  toString(): string {
    return this.value;
  }
}

/** Marks a constant written in this repo as markup. Never pass it text from the database or the request. */
export const raw = (value: string) => new Html(value);

const ENTITIES: Record<string, string> = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };

/** Text for element content and quoted attributes. */
export const esc = (value: string) => value.replace(/[&<>"']/g, (c) => ENTITIES[c]);

export type Value = string | number | Html | null | undefined | false | readonly Value[];

function render(value: Value): string {
  if (value === null || value === undefined || value === false) return "";
  if (value instanceof Html) return value.value;
  if (Array.isArray(value)) return value.map(render).join("");
  return esc(String(value));
}

/** `html`<p>${text}</p>``: strings and numbers are escaped, Html is kept, arrays are joined, null and false are left out. */
export function html(strings: TemplateStringsArray, ...values: Value[]): Html {
  let out = strings[0];
  for (let i = 0; i < values.length; i++) out += render(values[i]) + strings[i + 1];
  return new Html(out);
}

/**
 * A link from the data (the official page, a licence) as an https URL without
 * its `#fragment` (the fetcher adds one to tell stages of one bill apart, as
 * the app strips it), or null: never `javascript:`, `data:` or plain http.
 */
export function safeHttps(url: string | null | undefined): string | null {
  if (!url) return null;
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== "https:" || !parsed.hostname) return null;
    parsed.hash = "";
    return parsed.toString();
  } catch {
    return null;
  }
}

/** The site's name for a link: "gov.pl". */
export const siteName = (url: string) => new URL(url).hostname.replace(/^www\./, "");
