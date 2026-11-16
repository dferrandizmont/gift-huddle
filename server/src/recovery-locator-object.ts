import { DurableObject } from "cloudflare:workers";
import type { Env } from "./env";
import { LIST_TTL_MS, RECOVERY_RESERVATION_MS } from "./limits";

type Locator = { sid: string; reservationId: string; state: "reserved" | "linked"; reservedAt: number; alarmAt: number } | { state: "retired"; alarmAt: number; retiredUntil?: number };

/** Discovery only. In particular, an unknown GET creates neither a row nor an alarm. */
export class RecoveryLocatorObject extends DurableObject<Env> {
  /** One-off operator RPC: reuse the retirement upgrade without list reconciliation. */
  async applyRetention(): Promise<void> {
    await this.ctx.blockConcurrencyWhile(async () => { await this.read(); });
  }

  /** Called under the object lock; also upgrades old, undated retirement rows. */
  private async read(): Promise<Locator | undefined> {
    let row = await this.ctx.storage.get<Locator>("locator");
    if (row?.state === "retired") {
      const legacy = row.retiredUntil === undefined || Object.keys(row).some((key) => !["state", "alarmAt", "retiredUntil"].includes(key));
      const retiredUntil = row.retiredUntil ?? Date.now() + LIST_TTL_MS;
      // Rebuild even legacy rows: no list id, reservation token or creation time.
      const minimal = { state: "retired", alarmAt: retiredUntil, retiredUntil } as const;
      if (legacy || row.alarmAt !== retiredUntil) await this.ctx.storage.put("locator", minimal);
      row = minimal;
      if (Date.now() >= retiredUntil) {
        await this.ctx.storage.deleteAll();
        await this.ctx.storage.deleteAlarm();
        return undefined;
      }
      if (await this.ctx.storage.getAlarm() !== retiredUntil) await this.ctx.storage.setAlarm(retiredUntil);
    }
    return row;
  }

  async locate(): Promise<string | null> {
    return this.ctx.blockConcurrencyWhile(async () => {
      const row = await this.read();
      return row && row.state !== "retired" ? row.sid : null;
    });
  }

  async reserve(sid: string, reservationId: string): Promise<boolean> {
    return this.ctx.blockConcurrencyWhile(async () => {
      const row = await this.read();
      if (row) return row.state !== "retired" && row.sid === sid && row.reservationId === reservationId;
      const alarmAt = Date.now() + RECOVERY_RESERVATION_MS;
      await this.ctx.storage.put("locator", { sid, reservationId, state: "reserved", reservedAt: Date.now(), alarmAt } satisfies Locator);
      await this.ctx.storage.setAlarm(alarmAt);
      return true;
    });
  }

  async confirm(sid: string, reservationId: string): Promise<boolean> {
    return this.ctx.blockConcurrencyWhile(async () => {
      const row = await this.read();
      if (!row || row.state === "retired" || row.sid !== sid || row.reservationId !== reservationId) return false;
      await this.ctx.storage.put("locator", { ...row, state: "linked" });
      return true;
    });
  }

  async retire(sid: string, reservationId: string): Promise<void> {
    await this.ctx.blockConcurrencyWhile(async () => {
      const row = await this.read();
      if (row?.state === "retired") return;
      if (row && (row.sid !== sid || row.reservationId !== reservationId)) return;
      const retiredUntil = Date.now() + LIST_TTL_MS;
      await this.ctx.storage.put("locator", { state: "retired", alarmAt: retiredUntil, retiredUntil } satisfies Locator);
      await this.ctx.storage.setAlarm(retiredUntil);
    });
  }

  override async alarm(): Promise<void> {
    const row = await this.ctx.blockConcurrencyWhile(() => this.read());
    if (!row || row.state === "retired") return;
    // Never hold the locator lock while calling a list: list -> reserve is the
    // other direction. The token check below fences a delayed alarm result.
    try {
      const ns = this.env.LISTS_V2.jurisdiction("eu");
      const state = await ns.get(ns.idFromName(row.sid)).recoveryReconcile(row.reservationId);
      if (state === "linked") await this.confirm(row.sid, row.reservationId);
      else if (state === "retired") await this.retire(row.sid, row.reservationId);
    } catch {
      // An unavailable list cannot authorize releasing a reservation.
    }
    await this.ctx.blockConcurrencyWhile(async () => {
      const current = await this.ctx.storage.get<Locator>("locator");
      if (current && current.state !== "retired") {
        current.alarmAt = Date.now() + RECOVERY_RESERVATION_MS;
        await this.ctx.storage.put("locator", current);
        await this.ctx.storage.setAlarm(current.alarmAt);
      }
    });
  }
}
