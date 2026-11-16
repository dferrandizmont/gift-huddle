// Shared storage limits and the v2 server contract.

/** Same as `kMaxEnvelopeBytes` in the app (decoded envelope). */
export const MAX_ENVELOPE_BYTES = 2 * 1024 * 1024;
/** Same bound the app applies to the base64url text (`kMaxEnvelopeBytes * 4 ~/ 3 + 4`). */
export const MAX_ENVELOPE_CHARS = Math.floor((MAX_ENVELOPE_BYTES * 4) / 3) + 4;

export const WINDOW_MS = 60_000;
/** Authenticated PUT attempts per minute and list. */
export const MAX_WRITES_PER_WINDOW = 60;

export const INVITE_TTL_MS = 24 * 60 * 60 * 1000;
/** Invitations alive at the same time for one list. */
export const MAX_OPEN_INVITES = 10;

export const LIST_TTL_MS = 400 * 24 * 60 * 60 * 1000;
/** Grace for surviving phones to merge a revoked writer's secret snapshots. */
export const V2_REVOKED_SLOTS_GRACE_MS = 30 * 24 * 60 * 60 * 1000;
/** `lastAccess` is rewritten at most this often (it costs a row write). */
export const TOUCH_INTERVAL_MS = 60 * 60 * 1000;

/** SQLite-backed Durable Objects cap a row at 2 MB; the envelope is split in smaller rows. */
export const CHUNK_CHARS = 1_000_000;
/** Simultaneous WebSockets per list; the oldest one is closed beyond this. */
export const MAX_SOCKETS = 16;

/** First upload (version 1) of a list: later versions can grow up to the envelope limit. */
export const MAX_FIRST_UPLOAD_BYTES = 256 * 1024;
export const NEW_LIST_WINDOW_MS = 60 * 60 * 1000;

// v2 (ADR 0004): independent resources, updated under one list version.

/** Ids of devices and people: `kSyncIdPattern` in the app (`device_keys.dart`). */
export const V2_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;
/**
 * A sealed slot (`protected_envelope.dart`) is fixed-size binary: header
 * (33 + 3 length bytes + three ids of up to 128) + nonce 12 + 128 KiB + tag 16 +
 * signature 64 = 131,584 bytes with the longest ids.
 */
export const V2_MAX_SLOT_BYTES = 131_584;
/** Unpadded base64url text of the largest slot. */
export const V2_MAX_SLOT_CHARS = Math.ceil((V2_MAX_SLOT_BYTES * 4) / 3);
/** `kMaxSlotsPerList`: one slot per (protected person, writer device). */
export const V2_MAX_SLOTS = 64;
/** From here GET `capacity.renew` is true: other writers' slots are never removed (B2). */
export const V2_WARN_SLOTS = 48;
/** Slots one writer may hold, so a single credential cannot exhaust V2_MAX_SLOTS (B2). */
export const V2_MAX_SLOTS_PER_WRITER = 32;
/** `kMaxRegistryRecords`, `kMaxRegistryVouches`, `kMaxRegistryRevocations`. */
export const V2_MAX_RECORDS = 64;
export const V2_MAX_VOUCHES = 256;
export const V2_MAX_REVOCATIONS = 64;
/**
 * Registry JSON bytes. Full caps with 22-character ids are about 110 KB; with
 * 128-character ids (the longest the app accepts) about 231 KB. Counts are the
 * real limit; this only bounds what a full registry can weigh.
 */
export const V2_MAX_REGISTRY_BYTES = 256 * 1024;
export const V2_MAX_PACKAGES = 512;
export const V2_MAX_PACKAGES_BYTES = 256 * 1024;
/**
 * Key packages (v3 and v4 together) one writer (`from`) may have in a snapshot
 * (ADR 0005, B3): a quarter of [V2_MAX_PACKAGES], so it takes at least four
 * credentials to fill the list and block a rotation. A writer already above it
 * may still keep or drop its own. The app trims its oldest v3 first.
 */
export const V2_MAX_PACKAGES_PER_WRITER = 128;
/** The same quarter of [V2_MAX_PACKAGES_BYTES], per writer (sum of its entries' JSON). */
export const V2_MAX_PACKAGE_BYTES_PER_WRITER = 64 * 1024;
/**
 * Own slots one PUT may carry and still fit [V2_MAX_BODY_BYTES] with everything
 * else at its cap. A phone writes only its own slots (one per protected person it
 * may seal) and the app sends at most this many per PUT, the rest in the next round.
 */
export const V2_MAX_SLOTS_PER_PUT = 10;
/**
 * Whole PUT body, read by the router before any credential is checked (finding 10).
 * Worst real case: the largest common envelope (MAX_ENVELOPE_CHARS, 2.67 MiB),
 * registry and packages at their caps (256 KiB each), 10 own slots of 175,446
 * characters (1.67 MiB) and the JSON around them: about 4.85 MiB. 5 MiB covers it
 * with margin; the old bound (every slot of the list at its largest, 14 MiB) let
 * a stranger make the Worker buffer that much per request.
 */
export const V2_MAX_BODY_BYTES = 5 * 1024 * 1024;
/**
 * `PUT` with `If-Match: "0"` (create): the object refuses more than
 * MAX_FIRST_UPLOAD_BYTES of JSON, so the router stops reading at 400 KiB.
 */
export const V2_MAX_CREATE_BODY_BYTES = 400 * 1024;
export const V2_MAX_INVITE_BODY_BYTES = 128 * 1024;
export const V2_MAX_REVOKE_BODY_BYTES = 1024;
/** PIN guards have a separate small body and attempt budget (ADR 0003). */
export const V2_MAX_GUARD_BODY_BYTES = 2 * 1024;
export const V2_GUARD_OPENS_PER_IP = 30;
export const V2_GUARD_ATTEMPT_MS = 2000;
export const V2_GUARD_FAILURES = 10;
/** `PairingOffer` / `PairingAnswer` JSON (one record and one vouch each). */
export const V2_MAX_DECLARATION_BYTES = 16 * 1024;
export const V2_MAX_REVEAL_BYTES = 1024;
/** Encrypted pairing package delivered to the guest. */
export const V2_MAX_PACKAGE_BYTES = 64 * 1024;
/**
 * Pairing checkpoints (ADR 0005, B7): an immutable copy of the approved common
 * and registry per approved invitation, kept until it expires or is cancelled.
 * At most this many live at once in a list (as many as approvals in 24 h, so
 * it never blocks a pairing the daily quota allows; the guest also releases
 * its copy once installed); each is at most one common
 * (MAX_ENVELOPE_BYTES) and one registry (V2_MAX_REGISTRY_BYTES).
 */
export const V2_MAX_CHECKPOINTS = 8;
/**
 * Requests per minute and credential. Counted in memory and written to the list's
 * SQLite every V2_RATE_PERSIST_EVERY hits (and when full), so a restarted object
 * keeps its windows (finding 16) at a bounded cost: at most max/8 + 1 row writes
 * per window and counter, and at most 7 uncounted hits per restart.
 */
export const V2_CREDENTIAL_REQUESTS = 120;
/** Mutations per minute and credential. */
export const V2_CREDENTIAL_WRITES = 30;
export const V2_RATE_PERSIST_EVERY = 8;
/**
 * v2 invitation routes per minute and client (IPv4 or IPv6 /56). One pairing in
 * person costs about 25 a minute (the guest polls every 4 s, the host every 10 s,
 * plus a few writes): 120 lets several phones and families behind one NAT pair at
 * once (finding 16). Each invitation keeps its own 30/min (V2_INVITE_REQUESTS_PER_INVITE),
 * so one invitation cannot spend the shared budget.
 */
export const V2_INVITE_REQUESTS_PER_IP = 120; // = INVITE_IP_LIMITER in wrangler.toml
/** Public requests (offer, answer, result) per minute and invitation, in the list object. */
export const V2_INVITE_REQUESTS_PER_INVITE = 30;
/**
 * New v2 lists per hour and client. Higher than v1's 5: a phone alone deletes the
 * list of a cancelled invitation and creates a fresh one on the next (finding 14),
 * and several phones of a household share the address.
 */
export const V2_NEW_LISTS_PER_HOUR = 12;

// Daily quotas (ADR 0004, "Cupos, generaciones y renovación"): sliding 24 h windows
// kept as timestamps inside the single state row, so they cost no extra rows.
export const V2_QUOTA_WINDOW_MS = 24 * 60 * 60 * 1000;
/** New record declarations one credential may add in any 24 h, after creation. */
export const V2_NEW_RECORDS_PER_CREDENTIAL = 8;
/** New record declarations the whole list may add in any 24 h, shared by every credential. */
export const V2_NEW_RECORDS_PER_LIST = 16;
/** Credentials a list may register (approved invitations) in any 24 h. */
export const V2_NEW_DEVICES_PER_LIST = 8;

// Caps of one generation (one syncId). Renewing makes a new syncId with fresh counters.
/** Service credentials ever registered in a generation, revoked ones included. */
export const V2_MAX_DEVICES = 64;
/** From here GET `capacity.renew` is true, so the app offers to renew before the cap. */
export const V2_WARN_DEVICES = 48;
/** Distinct record declarations a generation may ever see. */
export const V2_MAX_KNOWN_RECORDS = 512;
export const V2_WARN_KNOWN_RECORDS = 384;
export const V2_WS_PROTOCOL = "gift-huddle.v2";

// Renewal control has its own budget, independent of content/registration caps.
export const V2_MAX_RENEWAL_BODY_BYTES = 8 * 1024;
export const V2_MAX_RENEWAL_STATE_BYTES = 256 * 1024;
export const V2_RENEWAL_REQUESTS = 60;
export const V2_RENEWAL_WRITES = 30;
export const V2_MAX_RENEWAL_PARTICIPANTS = 32;
export const V2_MAX_RENEWAL_BRANCHES = 8;
/** Individual authenticated inactivity required before an explicit loss. */
export const V2_RENEWAL_ABSENCE_MS = 72 * 60 * 60 * 1000;

/** Ordinary mutations stop here, leaving a separate finite rescue allowance. */
export const V2_RENEWAL_LOG_COMMANDS = 512;
export const V2_RENEWAL_LOG_BYTES = 512 * 1024;
export const V2_RENEWAL_LOG_PAGE_COMMANDS = 256;
export const V2_RENEWAL_LOG_PAGE_BYTES = 256 * 1024;
/** Emergency ordinary progress is isolated per signer, so one revoked signer
 * cannot spend the survivor's allowance. Revoke/recover/abort have reserved rows. */
export const V2_RENEWAL_RESCUE_COMMANDS_PER_SIGNER = 64;
export const V2_RENEWAL_RESCUE_BYTES_PER_SIGNER = 64 * 1024;
export const V2_RENEWAL_LOG_MAX_COMMANDS = 24576;
export const V2_RENEWAL_LOG_MAX_BYTES = 24 * 1024 * 1024;
export const V2_RENEWAL_LOG_MAX_PAGES = 512;

export const V2_RENEWAL_REFILL_COMMANDS = 40;
export const V2_RENEWAL_REFILL_BYTES = 40 * 1024;
// ADR 0007: independent of snapshot, invitation and renewal budgets.
export const RECOVERY_MAX_BYTES = 1048576;
export const RECOVERY_MAX_HEADER_BYTES = 1024;
export const RECOVERY_MAX_BODY_BYTES = 1400832;
export const RECOVERY_CONTROL_BYTES = 4096;
export const RECOVERY_MAX_ACTIVE = 4;
export const RECOVERY_MAX_ACTIVE_BYTES = 4 * RECOVERY_MAX_BYTES;
export const RECOVERY_MAX_IDS = 256;
export const RECOVERY_MAX_RECEIPTS = 512;
export const RECOVERY_MAX_RETIRED_VERIFIERS = 256;
export const RECOVERY_MAX_HISTORY_BYTES = 4 * 1048576;
export const RECOVERY_MAX_RECEIPT_BYTES = 4096;
export const RECOVERY_REQUESTS_PER_IP = 30;
export const RECOVERY_MUTATIONS_PER_MINUTE = 6;
export const RECOVERY_WRITES_PER_DAY = 24;
export const RECOVERY_WRITES_PER_DEVICE_DAY = 6;
export const RECOVERY_CLAIMS_PER_DAY = 8;
export const RECOVERY_CLAIMS_PER_DEVICE_DAY = 2;
export const RECOVERY_MAX_IDS_PER_DEVICE = 32;
export const RECOVERY_RESERVATION_MS = 24 * 60 * 60 * 1000;
