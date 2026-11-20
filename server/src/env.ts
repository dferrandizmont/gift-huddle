import type { StorageLedgerObject } from "./storage-ledger-object";
import type { ListV2Object } from "./list-v2-object";
import type { InviteV2Object } from "./invite-v2-object";
import type { LimiterV2Object } from "./limiter-v2-object";
import type { CreationBudgetObject } from "./creation-budget-object";
import type { RecoveryLocatorObject } from "./recovery-locator-object";

export interface Env {
  /** Local workerd only; never set in the deployed configuration. */
  LOCAL_DEV?: string;
  RECOVERIES_V2: DurableObjectNamespace<RecoveryLocatorObject>;
  /** Fail closed unless explicitly enabled after renewal engine integration. */
  RENEWAL_ENABLED?: string;
  LIMITER_V2: DurableObjectNamespace<LimiterV2Object>;
  CREATION_BUDGET: DurableObjectNamespace<CreationBudgetObject>;
  STORAGE_LEDGER: DurableObjectNamespace<StorageLedgerObject>;
  CREATE_IP_LIMITER: RateLimit;
  LISTS_V2: DurableObjectNamespace<ListV2Object>;
  INVITES_V2: DurableObjectNamespace<InviteV2Object>;
  IP_LIMITER: RateLimit;
  INVITE_IP_LIMITER: RateLimit;
  INVITE_IP48_LIMITER: RateLimit;
  GUARD_IP_LIMITER: RateLimit;
  GUARD_IP48_LIMITER: RateLimit;
  RECOVERY_IP_LIMITER: RateLimit;
  RECOVERY_IP48_LIMITER: RateLimit;
  ALLOWED_ORIGIN: string;
}

declare global {
  namespace Cloudflare {
    interface GlobalProps {
      mainModule: typeof import("./index");
    }
    interface Env {
      LOCAL_DEV?: string;
      RECOVERIES_V2: DurableObjectNamespace<RecoveryLocatorObject>;
      RENEWAL_ENABLED?: string;
      LIMITER_V2: DurableObjectNamespace<LimiterV2Object>;
      CREATION_BUDGET: DurableObjectNamespace<CreationBudgetObject>;
      STORAGE_LEDGER: DurableObjectNamespace<StorageLedgerObject>;
      CREATE_IP_LIMITER: RateLimit;
      LISTS_V2: DurableObjectNamespace<ListV2Object>;
      INVITES_V2: DurableObjectNamespace<InviteV2Object>;
      IP_LIMITER: RateLimit;
      INVITE_IP_LIMITER: RateLimit;
      INVITE_IP48_LIMITER: RateLimit;
      GUARD_IP_LIMITER: RateLimit;
      GUARD_IP48_LIMITER: RateLimit;
      RECOVERY_IP_LIMITER: RateLimit;
      RECOVERY_IP48_LIMITER: RateLimit;
      ALLOWED_ORIGIN: string;
    }
  }
}
