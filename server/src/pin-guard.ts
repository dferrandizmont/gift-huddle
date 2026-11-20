import { decodeB64Url, encodeB64Url, sha256, timingSafeEqual } from "./encoding";
import { err, NOT_FOUND, type ApiResult } from "./http";
import { V2_GUARD_ATTEMPT_MS, V2_GUARD_FAILURES } from "./limits";
import { key32, object, type V2Route } from "./v2-contract";

type Secret = { version: number; tokenHash: string; verifier: string; secret: string };
type Guard = { current?: Secret; pending?: Secret; failures: number; failedSince?: number; mustRotate?: boolean; rotationRequired?: boolean; nextAttemptAt: number; suspended: boolean };
const versionNumber = (v: unknown): v is number => Number.isSafeInteger(v) && (v as number) > 0 && (v as number) < Number.MAX_SAFE_INTEGER;
const exact = (b: Record<string, unknown>, keys: string[]) => Object.keys(b).length === keys.length && keys.every((k) => k in b);
const equalHash = (a: string, b: string) => timingSafeEqual(decodeB64Url(a, 32)!, decodeB64Url(b, 32)!);
const hash = async (s: string) => encodeB64Url(await sha256(decodeB64Url(s, 32)!));
const ok = (): ApiResult => ({ status: 200 });
// Two fixed-size slots are always compared, including absent/retired guards.
const DUMMY: Secret = { version: 0, tokenHash: encodeB64Url(new Uint8Array(32)), verifier: encodeB64Url(new Uint8Array(32)), secret: "" };

/** No in-memory state. Called only under the owning list's concurrency lock. */
export class PinGuard {
  constructor(private sql: SqlStorage) {}

  private exists(): boolean {
    return this.sql.exec("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'guard'").toArray().length > 0;
  }

  private read(device: string): Guard | null {
    if (!this.exists()) return null;
    const row = this.sql.exec<{ data: string }>("SELECT data FROM guard WHERE device = ?", device).toArray()[0];
    return row ? JSON.parse(row.data) as Guard : null;
  }

  private save(device: string, g: Guard): void {
    this.sql.exec("CREATE TABLE IF NOT EXISTS guard (device TEXT PRIMARY KEY, data TEXT NOT NULL)");
    this.sql.exec("INSERT INTO guard (device, data) VALUES (?, ?) ON CONFLICT(device) DO UPDATE SET data = excluded.data", device, JSON.stringify(g));
  }

  delete(device: string): void {
    if (this.exists()) this.sql.exec("DELETE FROM guard WHERE device = ?", device);
  }

  requiresRotation(device: string): boolean {
    return this.read(device)?.rotationRequired === true;
  }

  async handle(device: string, action: V2Route["action"], b: Record<string, unknown>, live = true, beforeWrite?: () => Promise<void>): Promise<ApiResult> {
    const g = live ? this.read(device) : null;
    if (action === "open") return this.open(device, g, b, beforeWrite);
    return this.mutate(device, action, b);
  }

  /** Synchronous authenticated mutations share the list's storage reservation. */
  mutate(device: string, action: V2Route["action"], b: Record<string, unknown>): ApiResult {
    const g = this.read(device);
    if (action === "resume") {
      if (!g) return NOT_FOUND;
      g.suspended = false;
      g.failedSince ??= g.failures;
      g.failures = 0;
      g.mustRotate = true;
      g.nextAttemptAt = 0;
      this.save(device, g);
      return ok();
    }
    if (!versionNumber(b.version)) return err(400, "bad_request");
    if (action === "prepare") {
      if (!exact(b, ["version", "tokenHash", "verifier", "secret"]) || !key32(b.tokenHash) || !key32(b.verifier) || !key32(b.secret)) return err(400, "bad_request");
      const next: Secret = { version: b.version, tokenHash: b.tokenHash, verifier: b.verifier, secret: b.secret };
      const state: Guard = g ?? { failures: 0, nextAttemptAt: 0, suspended: false };
      if (b.version !== (state.current?.version ?? 0) + 1) return err(409, "invalid_state");
      if (state.current && equalHash(state.current.tokenHash, next.tokenHash)) return err(409, "invalid_state");
      if (state.pending) {
        return state.pending.version === next.version && equalHash(state.pending.tokenHash, next.tokenHash) && equalHash(state.pending.verifier, next.verifier) && equalHash(state.pending.secret, next.secret)
          ? ok() : err(409, "invalid_state");
      }
      state.pending = next;
      this.save(device, state);
      return ok();
    }
    if (!exact(b, ["version"])) return err(400, "bad_request");
    if (action === "cancel") {
      if (g?.pending?.version === b.version) {
        delete g.pending;
        this.save(device, g);
      }
      return { status: 200, body: { version: g?.current?.version ?? 0 } };
    }
    if (!g) return NOT_FOUND;
    if (g.current?.version === b.version) return ok();
    if (g.pending?.version !== b.version) return err(409, "invalid_state");
    g.current = g.pending;
    delete g.pending;
    g.failures = 0;
    g.failedSince = 0;
    g.suspended = false;
    g.nextAttemptAt = 0;
    g.mustRotate = false;
    g.rotationRequired = false;
    this.save(device, g);
    return ok();
  }

  private async open(device: string, g: Guard | null, b: Record<string, unknown>, beforeWrite?: () => Promise<void>): Promise<ApiResult> {
    if (!exact(b, ["proofs"]) || !Array.isArray(b.proofs) || b.proofs.length < 1 || b.proofs.length > 2) return err(400, "bad_request");
    const seen = new Set<number>();
    for (const p of b.proofs) {
      if (!object(p) || !exact(p, ["version", "guardToken", "prueba"]) || !versionNumber(p.version) || !key32(p.guardToken) || !key32(p.prueba) || seen.has(p.version)) return err(400, "bad_request");
      seen.add(p.version);
    }
    const proofs = b.proofs as { version: number; guardToken: string; prueba: string }[];
    const versions = [g?.current ?? DUMMY, g?.pending ?? DUMMY];
    let hasToken = false;
    let match: Secret | undefined;
    for (const p of proofs) {
      const tokenHash = await hash(p.guardToken);
      const verifier = await hash(p.prueba);
      for (const s of versions) {
        const tokenMatches = equalHash(s.tokenHash, tokenHash);
        const proofMatches = equalHash(s.verifier, verifier);
        if (s.version === p.version && tokenMatches) {
          hasToken = true;
          if (proofMatches) match = s;
        }
      }
    }
    // Tokens are capabilities: an unknown one reveals and changes nothing.
    if (!g || !hasToken) return NOT_FOUND;
    if (g.suspended) return err(423, "guard_suspended");
    const now = Date.now();
    if (now < g.nextAttemptAt) return err(429, "rate_limited", { "Retry-After": String(Math.max(1, Math.ceil((g.nextAttemptAt - now) / 1000))) });
    await beforeWrite?.();
    g.nextAttemptAt = now + V2_GUARD_ATTEMPT_MS;
    if (match) {
      const failedSince = g.failedSince ?? g.failures;
      g.failures = 0;
      g.failedSince = 0;
      g.mustRotate ||= failedSince > 0;
      g.rotationRequired ||= g.mustRotate === true;
      this.save(device, g);
      return { status: 200, body: { version: match.version, b: match.secret, failedSince, mustRotate: g.mustRotate === true } };
    }
    g.failedSince = (g.failedSince ?? g.failures) + 1;
    g.failures++;
    g.suspended = g.failures >= V2_GUARD_FAILURES;
    this.save(device, g);
    return g.suspended ? err(423, "guard_suspended") : { status: 403, body: { error: "wrong_pin", left: V2_GUARD_FAILURES - g.failures } };
  }
}
