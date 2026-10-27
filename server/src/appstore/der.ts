/**
 * Just enough DER to read Apple's certificates (#146): an element's tag, its
 * content and its whole bytes, the elements inside a SEQUENCE, OIDs and times.
 * Anything malformed throws.
 */
export interface Der {
  tag: number;
  content: Uint8Array;
  /** The whole element, tag and length included: what a signature covers. */
  raw: Uint8Array;
}

export function readDer(bytes: Uint8Array, offset = 0): { element: Der; next: number } {
  if (offset + 2 > bytes.length) throw new Error("DER: truncated");
  const tag = bytes[offset];
  let length = bytes[offset + 1];
  let header = 2;
  if (length & 0x80) {
    const size = length & 0x7f;
    if (size === 0 || size > 3 || offset + 2 + size > bytes.length) throw new Error("DER: bad length");
    length = 0;
    for (let i = 0; i < size; i++) length = length * 256 + bytes[offset + 2 + i];
    header += size;
  }
  const end = offset + header + length;
  if (end > bytes.length) throw new Error("DER: truncated");
  return { element: { tag, content: bytes.subarray(offset + header, end), raw: bytes.subarray(offset, end) }, next: end };
}

/** The elements inside a constructed element (a SEQUENCE, a SET, an explicit tag). */
export function children(element: Der): Der[] {
  const out: Der[] = [];
  for (let i = 0; i < element.content.length; ) {
    const { element: child, next } = readDer(element.content, i);
    out.push(child);
    i = next;
  }
  return out;
}

export function readOid(element: Der): string {
  if (element.tag !== 0x06 || element.content.length === 0) throw new Error("DER: not an OID");
  const bytes = element.content;
  const arcs = [Math.floor(bytes[0] / 40), bytes[0] % 40];
  let value = 0;
  for (let i = 1; i < bytes.length; i++) {
    value = value * 128 + (bytes[i] & 0x7f);
    if (!(bytes[i] & 0x80)) {
      arcs.push(value);
      value = 0;
    }
  }
  return arcs.join(".");
}

/** A UTCTime (`YYMMDDHHMMSSZ`, years 1950 to 2049) or a GeneralizedTime (`YYYYMMDDHHMMSSZ`). */
export function readTime(element: Der): Date {
  const text = new TextDecoder().decode(element.content);
  const match =
    element.tag === 0x17 ? text.match(/^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/) : element.tag === 0x18 ? text.match(/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/) : null;
  if (!match) throw new Error("DER: not a time");
  let year = Number(match[1]);
  if (element.tag === 0x17) year += year < 50 ? 2000 : 1900;
  return new Date(Date.UTC(year, Number(match[2]) - 1, Number(match[3]), Number(match[4]), Number(match[5]), Number(match[6])));
}
