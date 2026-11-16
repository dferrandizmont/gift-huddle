import { DurableObject } from "cloudflare:workers";
import type { Env } from "./env";

type Reservation = { syncId: string; owner: string; offerHash: string; guestPerson: string | null; expiresAt: number; reservationId?: string };
/** Released routing stubs preserve the revoked-Bearer 401 until expiry or reuse,
 * but carry no reservation, owner, offer hash or person and never block reuse. */
type Locator = Pick<Reservation, "syncId" | "expiresAt" | "reservationId"> & Partial<Pick<Reservation, "owner" | "offerHash" | "guestPerson">> & { released?: boolean };

/** Global reservation; the list owns the exchange and checks revocation. */
export class InviteV2Object extends DurableObject<Env> {
  async reserve(r: Reservation): Promise<{ ok: boolean; expiresAt: number; reservationId?: string }> {
    return this.ctx.blockConcurrencyWhile(async () => {
      const old = await this.ctx.storage.get<Locator>("locator");
      if (old && !old.released && old.expiresAt > Date.now()) {
        return { ok: old.syncId === r.syncId && old.owner === r.owner && old.offerHash === r.offerHash && old.guestPerson === r.guestPerson, expiresAt: old.expiresAt, reservationId: old.reservationId };
      }
      await this.ctx.storage.put("locator", r);
      await this.ctx.storage.setAlarm(r.expiresAt);
      return { ok: true, expiresAt: r.expiresAt, reservationId: r.reservationId };
    });
  }
  /** A delayed cleanup cannot erase a newer reservation of the same id. */
  async release(syncId: string, expiresAt: number, reservationId?: string): Promise<void> {
    await this.ctx.blockConcurrencyWhile(async () => {
      const r = await this.ctx.storage.get<Locator>("locator");
      if (r?.syncId === syncId && r.expiresAt === expiresAt && r.reservationId === reservationId) {
        await this.ctx.storage.put("locator", { syncId, expiresAt, released: true });
        await this.ctx.storage.setAlarm(expiresAt);
      }
    });
  }
  async locate(): Promise<string | null> {
    const r = await this.ctx.storage.get<Locator>("locator");
    return r && r.expiresAt > Date.now() ? r.syncId : null;
  }
  override async alarm(): Promise<void> {
    await this.ctx.blockConcurrencyWhile(async () => {
      const r = await this.ctx.storage.get<Locator>("locator");
      if (r && r.expiresAt > Date.now()) await this.ctx.storage.setAlarm(r.expiresAt);
      else await this.ctx.storage.deleteAll();
    });
  }
}
