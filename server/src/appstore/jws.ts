import { children, readDer, readOid, readTime, type Der } from "./der";

/**
 * Apple Root CA - G3, by the SHA-256 of its certificate
 * (apple.com/certificateauthority, valid until 2039). Every App Store signed
 * transaction and notification chains up to it.
 */
export const APPLE_ROOT_G3_SHA256 = "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";

/**
 * The marks Apple puts in the certificates that sign App Store data: the
 * leaf's, and the Worldwide Developer Relations intermediate's. Checking them
 * keeps out a developer's own certificate, which Apple signs through the same
 * intermediates.
 */
const LEAF_OID = "1.2.840.113635.100.6.11.1";
const INTERMEDIATE_OID = "1.2.840.113635.100.6.2.1";

const CURVES: Record<string, { name: string; size: number }> = {
  "1.2.840.10045.3.1.7": { name: "P-256", size: 32 },
  "1.3.132.0.34": { name: "P-384", size: 48 },
  "1.3.132.0.35": { name: "P-521", size: 66 },
};
const HASHES: Record<string, string> = {
  "1.2.840.10045.4.3.2": "SHA-256",
  "1.2.840.10045.4.3.3": "SHA-384",
  "1.2.840.10045.4.3.4": "SHA-512",
};

/** A signed payload that is not Apple's, or not readable. */
export class JwsError extends Error {}

export interface VerifyOptions {
  /** The trusted root by its SHA-256: Apple's, unless a test brings its own. */
  rootSha256?: string;
}

interface Certificate {
  tbs: Der;
  hash: string;
  signature: Uint8Array;
  spki: Der;
  curve: { name: string; size: number };
  notBefore: Date;
  notAfter: Date;
  extensions: Set<string>;
}

function parseCertificate(der: Uint8Array): Certificate {
  const [tbs, algorithm, signature] = children(readDer(der).element);
  const fields = children(tbs);
  // [0] version, serial, signature algorithm, issuer, validity, subject, key, then the optional parts.
  const at = fields[0].tag === 0xa0 ? 1 : 0;
  const [notBefore, notAfter] = children(fields[at + 3]).map(readTime);
  const spki = fields[at + 5];
  const curve = CURVES[readOid(children(children(spki)[0])[1])];
  const hash = HASHES[readOid(children(algorithm)[0])];
  if (!curve || !hash || signature.tag !== 0x03) throw new JwsError("unsupported certificate");
  const extensions = new Set<string>();
  const explicit = fields.slice(at + 6).find((field) => field.tag === 0xa3);
  if (explicit) for (const extension of children(children(explicit)[0])) extensions.add(readOid(children(extension)[0]));
  return { tbs, hash, signature: signature.content.subarray(1), spki, curve, notBefore, notAfter, extensions };
}

/** A DER ECDSA signature (SEQUENCE of r and s) as WebCrypto wants it: r and s, each `size` bytes. */
function rawSignature(der: Uint8Array, size: number): Uint8Array {
  const out = new Uint8Array(size * 2);
  children(readDer(der).element).forEach((integer, i) => {
    let value = integer.content;
    while (value.length > size && value[0] === 0) value = value.subarray(1);
    if (value.length > size) throw new JwsError("bad signature");
    out.set(value, i * size + size - value.length);
  });
  return out;
}

const publicKey = (certificate: Certificate) =>
  crypto.subtle.importKey("spki", certificate.spki.raw, { name: "ECDSA", namedCurve: certificate.curve.name }, false, ["verify"]);

async function signedBy(certificate: Certificate, issuer: Certificate): Promise<boolean> {
  return crypto.subtle.verify(
    { name: "ECDSA", hash: certificate.hash },
    await publicKey(issuer),
    rawSignature(certificate.signature, issuer.curve.size),
    certificate.tbs.raw,
  );
}

function fromBase64(text: string): Uint8Array {
  const plain = text.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(plain + "=".repeat((4 - (plain.length % 4)) % 4));
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}

const hex = (bytes: ArrayBuffer) => [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");

/**
 * Checks a JWS signed by the App Store, with no Apple key and nothing asked
 * of Apple, as Apple's own libraries do offline: ES256, three certificates in
 * `x5c` whose root is Apple Root CA - G3, Apple's marks on the leaf and the
 * intermediate, each certificate signed by the next and valid when the payload
 * was signed, and the payload signed by the leaf. Returns the payload; throws a
 * JwsError otherwise.
 */
export async function verifyAppleJws<T>(jws: string, options: VerifyOptions = {}): Promise<T> {
  try {
    const parts = jws.split(".");
    if (parts.length !== 3) throw new JwsError("not a JWS");
    const text = (part: string) => new TextDecoder().decode(fromBase64(part));
    const header = JSON.parse(text(parts[0])) as { alg?: string; x5c?: unknown };
    if (header.alg !== "ES256" || !Array.isArray(header.x5c) || header.x5c.length !== 3) throw new JwsError("not an App Store JWS");
    const chain = header.x5c.map((cert) => fromBase64(String(cert)));
    if (hex(await crypto.subtle.digest("SHA-256", chain[2])) !== (options.rootSha256 ?? APPLE_ROOT_G3_SHA256)) {
      throw new JwsError("not Apple's root");
    }
    const [leaf, intermediate, root] = chain.map(parseCertificate);
    if (!leaf.extensions.has(LEAF_OID) || !intermediate.extensions.has(INTERMEDIATE_OID)) throw new JwsError("not an App Store certificate");
    const payload = JSON.parse(text(parts[1])) as T & { signedDate?: number };
    const signedAt = typeof payload.signedDate === "number" ? new Date(payload.signedDate) : new Date();
    if ([leaf, intermediate, root].some((c) => signedAt < c.notBefore || signedAt > c.notAfter)) throw new JwsError("certificate not valid");
    if (!(await signedBy(intermediate, root)) || !(await signedBy(leaf, intermediate))) throw new JwsError("broken chain");
    const signature = fromBase64(parts[2]);
    if (leaf.curve.name !== "P-256" || signature.length !== 64) throw new JwsError("bad signature");
    const signed = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
    if (!(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, await publicKey(leaf), signature, signed))) {
      throw new JwsError("bad signature");
    }
    return payload;
  } catch (error) {
    throw error instanceof JwsError ? error : new JwsError(error instanceof Error ? error.message : String(error));
  }
}
