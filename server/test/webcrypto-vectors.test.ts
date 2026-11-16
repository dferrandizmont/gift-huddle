// ADR 0005, B5 (B4 of the B1 security review): the common-key vectors written by
// the Dart code (`docs/adr/0005-vector-clave-comun.json`, KeyBundle v4 and the
// signed common envelope) reproduced with WebCrypto only, independently of the
// Dart `cryptography` package the web build compiles. workerd's WebCrypto is
// V8 + BoringSSL, as in Chrome. Also the X25519 low-order points of
// `docs/adr/0005-vector-x25519.json`: WebCrypto must reject the same ones
// (all-zero secret) and agree on the others (high bit masked, RFC 7748).
import { describe, expect, it } from "vitest";
import common from "../../docs/adr/0005-vector-clave-comun.json";
import lowOrder from "../../docs/adr/0005-vector-x25519.json";

const subtle = crypto.subtle;
const utf8 = (s: string) => new TextEncoder().encode(s);
const b64 = (s: string) => {
  const t = s.replace(/-/g, "+").replace(/_/g, "/");
  const bin = atob(t + "=".repeat((4 - (t.length % 4)) % 4));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
};
const toB64 = (b: Uint8Array) => btoa(String.fromCharCode(...b)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const hex = (s: string) => Uint8Array.from(s.match(/../g) ?? [], (h) => parseInt(h, 16));
const toHex = (b: ArrayBuffer | Uint8Array) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");
const cat = (...parts: Uint8Array[]) => {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) { out.set(p, at); at += p.length; }
  return out;
};
const sha256Hex = async (b: Uint8Array) => toHex(await subtle.digest("SHA-256", b));
/** Canonical JSON: sorted keys, compact (what Dart's canonicalHeaderBytes writes). */
const canonical = (v: unknown): string =>
  Array.isArray(v) ? `[${v.map(canonical).join(",")}]`
    : v !== null && typeof v === "object" ? `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${canonical((v as Record<string, unknown>)[k])}`).join(",")}}`
      : JSON.stringify(v);

const X25519_PKCS8 = hex("302e020100300506032b656e04220420");
const ED25519_PKCS8 = hex("302e020100300506032b657004220420");
const x25519Private = (seed: Uint8Array) => subtle.importKey("pkcs8", cat(X25519_PKCS8, seed), { name: "X25519" }, true, ["deriveBits"]);
const x25519Public = (raw: Uint8Array) => subtle.importKey("raw", raw, { name: "X25519" }, true, []);
const ed25519Private = (seed: Uint8Array) => subtle.importKey("pkcs8", cat(ED25519_PKCS8, seed), { name: "Ed25519" }, true, ["sign"]);
const ed25519Public = (raw: Uint8Array) => subtle.importKey("raw", raw, { name: "Ed25519" }, true, ["verify"]);
/** The public key of a private one (through its JWK `x`). */
const publicOf = async (key: CryptoKey) => b64(((await subtle.exportKey("jwk", key)) as JsonWebKey).x!);
const agree = async (mine: CryptoKey, theirs: Uint8Array) =>
  new Uint8Array(await subtle.deriveBits({ name: "X25519", public: await x25519Public(theirs) } as unknown as SubtleCryptoDeriveKeyAlgorithm, mine, 256));
const hkdf = async (secret: Uint8Array, salt: Uint8Array, info: Uint8Array) =>
  new Uint8Array(await subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt, info }, await subtle.importKey("raw", secret, "HKDF", false, ["deriveBits"]), 256));
const aes = (raw: Uint8Array, use: "encrypt" | "decrypt") => subtle.importKey("raw", raw, "AES-GCM", false, [use]);
const sign = async (seed: Uint8Array, message: Uint8Array) => new Uint8Array(await subtle.sign("Ed25519", await ed25519Private(seed), message));
const verify = async (pub: Uint8Array, signature: Uint8Array, message: Uint8Array) => subtle.verify("Ed25519", await ed25519Public(pub), signature, message);
const inflateRaw = async (b: Uint8Array) =>
  new Uint8Array(await new Response(new Blob([b]).stream().pipeThrough(new DecompressionStream("deflate-raw"))).arrayBuffer());

type Device = { agreementSeed: string; signingSeed: string; agreementPublic: string; signingPublic: string; recordDigest: string };
const devices = common.devices as Record<string, Device>;
const aritz = devices["aritz-phone"]!;
const leo = devices["leo-phone"]!;
const candidate = common.candidate.json;
const bundle = common.keyBundleV4.json;
/** Fields of the candidate that the kid and the creator's signature cover. */
const publicFields = { a: candidate.a, c: candidate.c, cr: candidate.cr, ctx: candidate.ctx, e: candidate.e, l: candidate.l, s: candidate.s, sid: candidate.sid, v: candidate.v };

describe("B5: Dart vectors reproduced with WebCrypto", () => {
  it("device keys from their seeds", async () => {
    for (const d of Object.values(devices)) {
      expect(toB64(await publicOf(await x25519Private(b64(d.agreementSeed))))).toBe(d.agreementPublic);
      expect(toB64(await publicOf(await ed25519Private(b64(d.signingSeed))))).toBe(d.signingPublic);
    }
  });

  it("epoch context, kid and the creator's signature", async () => {
    const e = common.epoch;
    expect(canonical(e.descriptor)).toBe(e.canonical);
    expect(await sha256Hex(cat(utf8(e.domain), new Uint8Array([0]), utf8(e.canonical)))).toBe(e.context);
    expect(candidate.ctx).toBe(e.context);
    const kid = await sha256Hex(cat(utf8(common.candidate.kidDomain), new Uint8Array([0]), utf8(canonical(publicFields)), new Uint8Array([0]), b64(candidate.k)));
    expect(kid).toBe(candidate.kid);
    const statement = cat(utf8(common.candidate.creatorDomain), new Uint8Array([0]), utf8(canonical({ ...publicFields, kid })));
    expect(await verify(b64(aritz.signingPublic), b64(candidate.cs), statement)).toBe(true);
    // Ed25519 is deterministic: WebCrypto writes the same signature.
    expect(toB64(await sign(b64(aritz.signingSeed), statement))).toBe(candidate.cs);
    const tampered = statement.slice();
    tampered[tampered.length - 2]! ^= 1;
    expect(await verify(b64(aritz.signingPublic), b64(candidate.cs), tampered)).toBe(false);
  });

  it("KeyBundle v4: Leo opens it, and the sender's side gives the same bytes", async () => {
    const domain = utf8(common.keyBundleV4.domain);
    const header = canonical({ a: bundle.a, c: bundle.c, cr: bundle.cr, cs: bundle.cs, ctx: bundle.ctx, e: bundle.e, fr: bundle.fr, from: bundle.from, kid: bundle.kid, l: bundle.l, s: bundle.s, sid: bundle.sid, to: bundle.to, tr: bundle.tr, v: bundle.v });
    const epk = b64(bundle.epk);
    const leoPublic = b64(leo.agreementPublic);
    const aad = cat(domain, new Uint8Array([0]), utf8(header), epk, leoPublic);
    const nonce = b64(bundle.n);
    const ct = b64(bundle.ct);
    // The sender's Ed25519 signature over AAD ‖ nonce ‖ ciphertext ‖ tag.
    expect(await verify(b64(aritz.signingPublic), b64(bundle.sig), cat(aad, nonce, ct))).toBe(true);
    expect(toB64(await sign(b64(aritz.signingSeed), cat(aad, nonce, ct)))).toBe(bundle.sig);
    // Recipient: X25519(Leo, epk) → HKDF(salt = epk ‖ pubLeo, info = domain).
    const shared = await agree(await x25519Private(b64(leo.agreementSeed)), epk);
    const wrap = await hkdf(shared, cat(epk, leoPublic), domain);
    const secret = new Uint8Array(await subtle.decrypt({ name: "AES-GCM", iv: nonce, additionalData: aad }, await aes(wrap, "decrypt"), ct));
    expect(toB64(secret)).toBe(candidate.k);
    // Sender: the ephemeral seed gives epk and the same shared secret.
    const ephemeral = await x25519Private(b64(common.keyBundleV4.ephemeralSeed));
    expect(toB64(await publicOf(ephemeral))).toBe(bundle.epk);
    expect(toHex(await agree(ephemeral, leoPublic))).toBe(toHex(shared));
    const sealed = new Uint8Array(await subtle.encrypt({ name: "AES-GCM", iv: nonce, additionalData: aad }, await aes(wrap, "encrypt"), secret));
    expect(toB64(sealed)).toBe(bundle.ct);
    // Any change to the AAD (here, the recipient's record) fails the GCM.
    const other = cat(domain, new Uint8Array([0]), utf8(header.replace(bundle.tr, aritz.recordDigest)), epk, leoPublic);
    await expect(subtle.decrypt({ name: "AES-GCM", iv: nonce, additionalData: other }, await aes(wrap, "decrypt"), ct)).rejects.toThrow();
  });

  it("signed common envelope: verified, opened and resealed byte for byte", async () => {
    const env = common.commonEnvelope;
    const bytes = b64(env.envelope);
    expect([...bytes.slice(0, 3)]).toEqual([0x52, 0x47, 0x02]);
    const headerLength = (bytes[3]! << 8) | bytes[4]!;
    const aadEnd = 5 + headerLength;
    expect(new TextDecoder().decode(bytes.slice(5, aadEnd))).toBe(env.header);
    const header = JSON.parse(env.header) as Record<string, unknown>;
    expect(canonical(header)).toBe(env.header);
    expect(header.kid).toBe(candidate.kid);
    expect(header.w).toBe("aritz-phone");
    expect(header.wr).toBe(aritz.recordDigest);
    const nonce = bytes.slice(aadEnd, aadEnd + 12);
    expect(toB64(nonce)).toBe(env.nonce);
    const signature = bytes.slice(bytes.length - 64);
    const signed = cat(utf8(env.signatureDomain), new Uint8Array([0]), bytes.slice(0, bytes.length - 64));
    expect(await verify(b64(aritz.signingPublic), signature, signed)).toBe(true);
    expect(toB64(await sign(b64(aritz.signingSeed), signed))).toBe(toB64(signature));
    const key = await hkdf(b64(candidate.k), new Uint8Array(0), cat(utf8(env.signatureDomain), new Uint8Array([0]), utf8(candidate.kid)));
    const aad = bytes.slice(0, aadEnd);
    const sealed = bytes.slice(aadEnd + 12, bytes.length - 64);
    const body = new Uint8Array(await subtle.decrypt({ name: "AES-GCM", iv: nonce, additionalData: aad }, await aes(key, "decrypt"), sealed));
    const doc = JSON.parse(new TextDecoder().decode(await inflateRaw(body)));
    expect(doc).toEqual(JSON.parse(env.documentJson));
    const again = new Uint8Array(await subtle.encrypt({ name: "AES-GCM", iv: nonce, additionalData: aad }, await aes(key, "encrypt"), body));
    expect(toB64(again)).toBe(toB64(sealed));
    // The raw secret (without HKDF) does not open it (B7 of the security review).
    await expect(subtle.decrypt({ name: "AES-GCM", iv: nonce, additionalData: aad }, await aes(b64(candidate.k), "decrypt"), sealed)).rejects.toThrow();
  });

  it("X25519 low-order points: WebCrypto rejects exactly the ones Dart rejects and agrees on the rest", async () => {
    const mine = await x25519Private(hex(lowOrder.agreementSeed));
    expect(toHex(await publicOf(mine))).toBe(lowOrder.agreementPublic);
    expect(toHex(await agree(mine, hex(lowOrder.control.public)))).toBe(lowOrder.control.secret);
    expect(lowOrder.points).toHaveLength(12);
    for (const p of lowOrder.points as { public: string; secret: string | null }[]) {
      if (p.secret === null) {
        await expect(agree(mine, hex(p.public)), p.public).rejects.toThrow();
      } else {
        expect(toHex(await agree(mine, hex(p.public))), p.public).toBe(p.secret);
      }
    }
  });
});
