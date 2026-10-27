/**
 * A test App Store: a root, an intermediate and a signing leaf of its own,
 * made with WebCrypto, shaped like Apple's (P-384 root and intermediate, a
 * P-256 leaf, Apple's marks in the extensions), and JWS signed with the leaf
 * as the App Store signs transactions and notifications. `rootSha256` is the
 * root to trust in place of Apple's.
 */
const enc = (tag: number, ...parts: Uint8Array[]): Uint8Array => {
  const content = concat(...parts);
  const n = content.length;
  const length = n < 128 ? [n] : n < 256 ? [0x81, n] : [0x82, n >> 8, n & 255];
  return concat(Uint8Array.of(tag, ...length), content);
};

function concat(...parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((sum, p) => sum + p.length, 0));
  let at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return out;
}

const seq = (...parts: Uint8Array[]) => enc(0x30, ...parts);
const int = (bytes: Uint8Array) => {
  let value = bytes;
  while (value.length > 1 && value[0] === 0 && !(value[1] & 0x80)) value = value.subarray(1);
  return enc(0x02, value[0] & 0x80 ? concat(Uint8Array.of(0), value) : value);
};
function oid(text: string): Uint8Array {
  const [a, b, ...rest] = text.split(".").map(Number);
  const bytes = [a * 40 + b];
  for (const arc of rest) {
    const groups = [arc & 0x7f];
    for (let v = Math.floor(arc / 128); v > 0; v = Math.floor(v / 128)) groups.unshift((v & 0x7f) | 0x80);
    bytes.push(...groups);
  }
  return enc(0x06, Uint8Array.from(bytes));
}
const utcTime = (date: Date) => enc(0x17, new TextEncoder().encode(`${date.toISOString().slice(2, 19).replace(/[-T:]/g, "")}Z`));
const name = (cn: string) => seq(enc(0x31, seq(oid("2.5.4.3"), enc(0x0c, new TextEncoder().encode(cn)))));

export const LEAF_MARK = "1.2.840.113635.100.6.11.1";
export const INTERMEDIATE_MARK = "1.2.840.113635.100.6.2.1";

const ecdsa = (namedCurve: string) =>
  crypto.subtle.generateKey({ name: "ECDSA", namedCurve }, true, ["sign", "verify"]) as Promise<CryptoKeyPair>;

async function certificate(subject: string, key: CryptoKeyPair, issuer: string, issuerKey: CryptoKey, marks: string[], serial: number) {
  const algorithm = seq(oid("1.2.840.10045.4.3.3"));
  const extensions = enc(0xa3, seq(...marks.map((mark) => seq(oid(mark), enc(0x04, Uint8Array.of(0x05, 0x00))))));
  const tbs = seq(
    enc(0xa0, int(Uint8Array.of(2))),
    int(Uint8Array.of(serial)),
    algorithm,
    name(issuer),
    seq(utcTime(new Date("2020-01-01T00:00:00Z")), utcTime(new Date("2040-01-01T00:00:00Z"))),
    name(subject),
    new Uint8Array((await crypto.subtle.exportKey("spki", key.publicKey)) as ArrayBuffer),
    extensions,
  );
  const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-384" }, issuerKey, tbs));
  const half = raw.length / 2;
  return seq(tbs, algorithm, enc(0x03, Uint8Array.of(0), seq(int(raw.subarray(0, half)), int(raw.subarray(half)))));
}

const base64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));
const base64url = (bytes: Uint8Array) => base64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

export interface TestAppStore {
  rootSha256: string;
  sign(payload: object): Promise<string>;
}

/** A test App Store; `leafMarks` lets a test leave Apple's mark out of the leaf. */
export async function testAppStore(leafMarks: string[] = [LEAF_MARK]): Promise<TestAppStore> {
  const rootKey = await ecdsa("P-384");
  const intermediateKey = await ecdsa("P-384");
  const leafKey = await ecdsa("P-256");
  const root = await certificate("Test Root", rootKey, "Test Root", rootKey.privateKey, [], 1);
  const intermediate = await certificate("Test WWDR", intermediateKey, "Test Root", rootKey.privateKey, [INTERMEDIATE_MARK], 2);
  const leaf = await certificate("Test Signing", leafKey, "Test WWDR", intermediateKey.privateKey, leafMarks, 3);
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", root));
  const header = base64url(new TextEncoder().encode(JSON.stringify({ alg: "ES256", x5c: [leaf, intermediate, root].map(base64) })));
  return {
    rootSha256: [...digest].map((b) => b.toString(16).padStart(2, "0")).join(""),
    async sign(payload) {
      const body = base64url(new TextEncoder().encode(JSON.stringify(payload)));
      const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, leafKey.privateKey, new TextEncoder().encode(`${header}.${body}`));
      return `${header}.${body}.${base64url(new Uint8Array(signature))}`;
    },
  };
}
