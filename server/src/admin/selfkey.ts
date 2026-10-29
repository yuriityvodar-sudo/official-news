// The admin page's own Google key (#60, Yurii 29 Oct: "so that I just need to
// click a button"). The Worker makes an RSA key pair itself; the private key
// stays in its own storage (the ADMIN_KV namespace, which only this Worker
// binds) and is never shown, sent or downloaded. Google trusts it once the
// matching public certificate, which is safe to show, is uploaded to the
// analytics-reader service account ("Upload existing key"). So no secret ever
// passes through a person, a chat or a file.
//
// Google takes an X.509 certificate (RSA 2048, PEM). WebCrypto has no
// certificate builder, so this writes the few DER structures a self-signed
// certificate needs by hand.

const bytes = (...parts: (Uint8Array | number[])[]) => {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let i = 0;
  for (const p of parts) {
    out.set(p, i);
    i += p.length;
  }
  return out;
};

/** A DER element: tag, length (short or long form), content. */
function der(tag: number, content: Uint8Array): Uint8Array {
  const n = content.length;
  if (n < 0x80) return bytes([tag, n], content);
  const len: number[] = [];
  for (let v = n; v > 0; v >>= 8) len.unshift(v & 0xff);
  return bytes([tag, 0x80 | len.length, ...len], content);
}

const seq = (...items: Uint8Array[]) => der(0x30, bytes(...items));
const set = (...items: Uint8Array[]) => der(0x31, bytes(...items));
const NULL = new Uint8Array([0x05, 0x00]);

function oid(dotted: string): Uint8Array {
  const [a, b, ...rest] = dotted.split(".").map(Number);
  const body = [40 * a + b];
  for (const n of rest) {
    const groups = [n & 0x7f];
    for (let v = n >> 7; v > 0; v >>= 7) groups.unshift(0x80 | (v & 0x7f));
    body.push(...groups);
  }
  return der(0x06, new Uint8Array(body));
}

/** A positive INTEGER from big-endian bytes (a leading zero when the top bit is set). */
const integer = (value: Uint8Array) => der(0x02, value[0] & 0x80 ? bytes([0], value) : value);
const utf8 = (text: string) => der(0x0c, new TextEncoder().encode(text));

/** UTCTime, "YYMMDDHHMMSSZ" (valid until 2049). */
function utcTime(date: Date): Uint8Array {
  const p = (n: number) => String(n).padStart(2, "0");
  const s = `${p(date.getUTCFullYear() % 100)}${p(date.getUTCMonth() + 1)}${p(date.getUTCDate())}${p(date.getUTCHours())}${p(date.getUTCMinutes())}${p(date.getUTCSeconds())}Z`;
  return der(0x17, new TextEncoder().encode(s));
}

const SHA256_RSA = seq(oid("1.2.840.113549.1.1.11"), NULL);
const name = (cn: string) => seq(set(seq(oid("2.5.4.3"), utf8(cn))));

const pem = (label: string, der: Uint8Array) => {
  let binary = "";
  for (const b of der) binary += String.fromCharCode(b);
  const body = btoa(binary).replace(/(.{64})/g, "$1\n").replace(/\n$/, "");
  return `-----BEGIN ${label}-----\n${body}\n-----END ${label}-----\n`;
};

/** The pieces this Worker keeps: the private key (PKCS#8 PEM, never shown) and the public certificate (shown for the upload). */
export interface SelfKey {
  privateKeyPem: string;
  certificatePem: string;
  createdAt: string;
}

/** A new RSA 2048 key pair and its self-signed certificate, valid for `years` from `now`. */
export async function makeSelfKey(commonName: string, now = new Date(), years = 10): Promise<SelfKey> {
  const pair = (await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  )) as CryptoKeyPair;
  const spki = new Uint8Array((await crypto.subtle.exportKey("spki", pair.publicKey)) as ArrayBuffer);
  const serial = crypto.getRandomValues(new Uint8Array(16));
  serial[0] &= 0x7f;
  const until = new Date(now);
  until.setUTCFullYear(until.getUTCFullYear() + years);
  const tbs = seq(
    der(0xa0, integer(new Uint8Array([2]))), // version 3
    integer(serial),
    SHA256_RSA,
    name(commonName),
    seq(utcTime(now), utcTime(until)),
    name(commonName),
    spki,
  );
  const signature = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", pair.privateKey, tbs));
  const certificate = seq(tbs, SHA256_RSA, der(0x03, bytes([0], signature)));
  const pkcs8 = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
  return { privateKeyPem: pem("PRIVATE KEY", pkcs8), certificatePem: pem("CERTIFICATE", certificate), createdAt: now.toISOString() };
}
