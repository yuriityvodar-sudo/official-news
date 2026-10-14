// Small text helpers shared by the feed, page and API readers.

const NAMED_ENTITIES: Record<string, string> = {
  amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", ndash: "–", mdash: "—", hellip: "…",
  lsquo: "‘", rsquo: "’", ldquo: "“", rdquo: "”", laquo: "«", raquo: "»", bull: "•", middot: "·",
  copy: "©", reg: "®", deg: "°", euro: "€", pound: "£", sect: "§", para: "¶", shy: "",
  aacute: "á", Aacute: "Á", agrave: "à", Agrave: "À", acirc: "â", Acirc: "Â", atilde: "ã", Atilde: "Ã", auml: "ä", Auml: "Ä", aring: "å",
  eacute: "é", Eacute: "É", egrave: "è", Egrave: "È", ecirc: "ê", Ecirc: "Ê", euml: "ë", Euml: "Ë",
  iacute: "í", Iacute: "Í", igrave: "ì", Igrave: "Ì", icirc: "î", Icirc: "Î", iuml: "ï", Iuml: "Ï",
  oacute: "ó", Oacute: "Ó", ograve: "ò", Ograve: "Ò", ocirc: "ô", Ocirc: "Ô", otilde: "õ", Otilde: "Õ", ouml: "ö", Ouml: "Ö",
  uacute: "ú", Uacute: "Ú", ugrave: "ù", Ugrave: "Ù", ucirc: "û", Ucirc: "Û", uuml: "ü", Uuml: "Ü",
  ccedil: "ç", Ccedil: "Ç", ntilde: "ñ", Ntilde: "Ñ", szlig: "ß", oelig: "œ", OElig: "Œ", aelig: "æ", AElig: "Æ",
  iexcl: "¡", iquest: "¿", ordm: "º", ordf: "ª",
};

/** Decodes HTML/XML character references (`&amp;`, `&#233;`, `&#xE9;`); unknown names stay as they are. */
export function decodeEntities(text: string): string {
  return text.replace(/&(#x[0-9a-f]+|#\d+|[a-z][a-z0-9]*);/gi, (match, ref: string) => {
    if (ref[0] === "#") {
      const code = ref[1] === "x" || ref[1] === "X" ? parseInt(ref.slice(2), 16) : parseInt(ref.slice(1), 10);
      return Number.isFinite(code) && code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : match;
    }
    return NAMED_ENTITIES[ref] ?? match;
  });
}

function stripTags(html: string): string {
  return html
    .replace(/<(script|style|noscript)\b[\s\S]*?<\/\1>/gi, " ")
    .replace(/<(br|\/p|\/div|\/li|\/h[1-6]|\/tr)\b[^>]*>/gi, "\n")
    .replace(/<[^>]+>/g, " ");
}

/** Turns an HTML fragment into plain text: drops scripts, styles and tags, decodes entities, tidies spaces. */
export function htmlToText(html: string): string {
  let text = decodeEntities(stripTags(html));
  // Many feeds escape their HTML (`&lt;p&gt;`), so tags only appear after decoding.
  if (/<\/?[a-z][^>]*>/i.test(text)) text = decodeEntities(stripTags(text));
  return cleanText(text);
}

/** Collapses runs of spaces, keeps single line breaks between paragraphs. */
export function cleanText(text: string): string {
  return text
    .replace(/[ \t\f\v ]+/g, " ")
    .replace(/ *\n[ \n]*/g, "\n")
    .trim();
}

/** Bytes to text: UTF-8 unless the source says ISO-8859-1 (which maps byte for byte to Unicode). */
export function decodeBody(bytes: ArrayBuffer, charset: string | null): string {
  if (charset && /^(iso-8859-1|latin-?1)$/i.test(charset)) {
    const view = new Uint8Array(bytes);
    let out = "";
    for (let i = 0; i < view.length; i += 8192) {
      out += String.fromCharCode(...view.subarray(i, i + 8192));
    }
    return out;
  }
  return new TextDecoder().decode(bytes);
}

/** Times are stored as `YYYY-MM-DDTHH:MM:SSZ` (docs/contract.md). */
export function toStoredTime(date: Date): string {
  return `${date.toISOString().slice(0, 19)}Z`;
}

const CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

/** A ULID: sorts by creation time, like the seed ids. */
export function ulid(now = Date.now()): string {
  let time = "";
  let t = now;
  for (let i = 0; i < 10; i++) {
    time = CROCKFORD[t % 32] + time;
    t = Math.floor(t / 32);
  }
  const random = crypto.getRandomValues(new Uint8Array(16));
  let rest = "";
  for (let i = 0; i < 16; i++) rest += CROCKFORD[random[i] % 32];
  return time + rest;
}

/** Reads `a.b.c` from an object; a string met on the way that holds JSON is parsed and followed. */
export function getPath(value: unknown, path: string): unknown {
  if (!path) return value;
  let current: unknown = value;
  for (const key of path.split(".")) {
    if (typeof current === "string" && /^\s*[[{]/.test(current)) {
      try {
        current = JSON.parse(current);
      } catch {
        return undefined;
      }
    }
    if (current === null || typeof current !== "object") return undefined;
    current = (current as Record<string, unknown>)[key];
  }
  return current;
}

/** Fills `{path}` placeholders from an object; a template without placeholders is a single path. */
export function fillTemplate(template: string, value: unknown): string {
  if (!template.includes("{")) {
    const v = getPath(value, template);
    return v === null || v === undefined ? "" : String(v);
  }
  return template.replace(/\{([^}]+)\}/g, (_, path: string) => {
    const v = getPath(value, path.trim());
    return v === null || v === undefined ? "" : String(v);
  });
}
