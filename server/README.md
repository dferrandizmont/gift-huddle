# Gift Huddle sync server

Cloudflare Worker (TypeScript) with SQLite Durable Objects. `/v1/*` is retired (410);
`/v2/` implements the server contract of ADR 0004. The server transports encrypted
documents and signed declarations; it never decrypts or merges them. Renewal appends additionally verify Ed25519 to protect log availability.

## Layout

| File | Role |
|---|---|
| `src/index.ts` | Router, parameter validation, bearer parsing, per-IP limit for invitation routes |
| `src/v2-router.ts`, `src/v2-contract.ts` | Independent v2 routes, streaming body limits, shape and size validation |
| `src/list-v2-object.ts` | `ListV2Object`, EU: one object per v2 list (atomic version, credential hashes and revocation, common/registry/packages/slots, invitations, hibernating sockets, 400-day alarm) |
| `src/invite-v2-object.ts` | EU atomic global invitation reservation (client or server id → syncId), erased on cancellation or after 24 h |
| `src/recovery-contract.ts` | ADR 0007 canonical capsule/header validation, capability domain separation and receipt fingerprints |
| `src/recovery-store.ts` | Separate chunked capsule blobs, bounded lifetime metadata, terminal reservations and durable recovery quotas |
| `src/recovery-locator-object.ts` | EU recoveryId → list discovery; fenced reservations and authoritative alarm reconciliation, without ciphertext or capability hashes |
| `src/pin-guard.ts` | Persisted PIN guard state machine, called under the list lock; no in-memory secrets or counters |
| `src/limiter-v2-object.ts` | EU synchronous SQLite IP counters |
| `src/ip.ts` | Client key: the IPv4 address, or the /56 of an IPv6 address (expanded to 8 groups first) |
| `src/limits.ts` | Every limit of the ADR |
| `test/` | Vitest tests that run inside the Workers runtime |

There is no `hono`: the router is a few `if`s, so the dependency list is only dev tools.

The one-time post-deployment sweep for old retention metadata is documented in
[`maintenance/README.md`](maintenance/README.md). It uses existing EU Durable
Object RPCs through a separate unrouted operator Worker; it adds no sync API route.

## Run it locally

```sh
cd server
pnpm install
pnpm exec wrangler dev --local --port 8787   # http://127.0.0.1:8787
pnpm test       # workerd, no external network
pnpm typecheck  # tsc --noEmit
```

Retirement smoke test (does not create any object):

```sh
curl -i localhost:8787/v1/lists/old
# 410 {"error":"gone"}
```

`wrangler dev` prints one line per request (method and path) to your own terminal. That is local only; the deployed Worker has `observability` off.
Stop it with Ctrl+C. If you started it from a script, find the PID of `workerd.exe` and of the `node` process running `wrangler` and stop those two.

## How it would be deployed (do not run without the maintainer's approval)

Nothing here deploys by itself, and no secret is needed: the Worker has no variables or tokens.

1. `pnpm exec wrangler login` (a Cloudflare account on the free plan).
2. A deployment applies the unchanged historical `v1`, `v2` and `v3-recovery` migrations, then **`v4-delete-v1`**, whose `deleted_classes = ["ListObject", "InviteObject", "LimiterObject"]` permanently deletes every v1 object and its stored data. Only the four v2 classes remain bound/exported. V2 namespaces and data are preserved. `RENEWAL_ENABLED` stays `false`. This repository change/dry run does not itself erase production data: that happens when this migration is deployed.
3. The URL is `https://gift-huddle-sync.<account>.workers.dev`. That value goes into the app as `--dart-define=SYNC_HOST=...` (ADR 0002, `kSyncHost`).
4. The custom-domain route `sync.gifthuddle.app` is configured in `wrangler.toml`; the retired trial hosts are no longer supported. `workers_dev = false` and `preview_urls = false` keep the alternate URLs closed. The exact browser origins are `https://gifthuddle.app` and `https://web.gifthuddle.app`; native clients send no Origin.
5. Domain WAF rules must cover both `/v1/` and `/v2/`, including list PUTs. WAF rules do not apply to `workers.dev`.
6. Changing a class name or removing one needs a new `[[migrations]]` entry with a new tag; never edit `v1`.

## Retired API v1

Product decision (2026-11-15). Every `/v1/*` path and method, including
preflight and WebSocket upgrade requests, returns `410 {"error":"gone"}`
without touching any storage or rate-limit binding. The usual Origin policy
and no-store headers still apply. No fallback to v2 or v1 import service exists.
The former v1 user transfers gifts manually; local file import remains supported
by the app. Never modify the historical migrations to perform this deletion.

## API v2

`S = /v2/lists/{syncId}`, `I = S/invites/{inviteId}`, `J = /v2/invites/{inviteId}`,
`G = S/guards/{deviceId}`.
`syncId` and `inviteId` are canonical, unpadded base64url of 16 random bytes
(22 characters). The phone generates the stable syncId with `SyncIdentityV2.newSyncId`;
the server cannot test randomness. Device and person ids use `[A-Za-z0-9_-]{1,128}`
(`kSyncIdPattern`). An authenticated request sends
`Authorization: Bearer <base64url(serviceCredential)>` (32 random bytes,
`DeviceKeys.serviceCredential`). The Worker hashes it before the RPC; the object
only ever sees and stores `SHA-256(credential)` (`serviceCredentialVerifier`).

| Method and route | Headers / JSON body | Success | Specific failures |
|---|---|---|---|
| `PUT S` (create) | Bearer; `If-Match: "0"`; `{deviceId, common, registry, keyPackages, slots}` | `201 {version:1}`, `ETag: "1"` | `428` no If-Match; `412` other value; `413` over 256 KiB or bounds; `403 forbidden_slot` any slot change (data or `null`) for another device; `403 forbidden_package` a key package not `from` the creator; `400` a duplicated slot resource; `429` 12 v2 lists/hour/IP; on an existing list: `401` unknown or revoked caller, `412` active caller; `410 retired` a deleted or expired syncId, for 400 days (a state row with the old `deleted` flag or missing a field of the current format counts as retired and is wiped to the marker) |
| `GET S` | Bearer; optional `If-None-Match: "N"` | `200 {version, common, registry, keyPackages, slots:[{personId,deviceId,version}], devices:[{deviceId,revoked,role,approvedBy?,commonFormat?}], capacity, minCommonFormat?}` + `ETag` | `304`; `404` deleted |
| `PUT S` (update) | Bearer; `If-Match: "N"`; `{common, registry, keyPackages, slots}` | `200 {version:N+1}` + `ETag` | `428` / `412` (+ current `ETag`); `403 forbidden_slot` any slot change (data or `null`) for another device, the whole delta refused; `403 forbidden_role` a web credential; `403 forbidden_package` a new key package not `from` the caller; `400` a duplicated slot resource; `413 too_many_slots` (64 per list) / `too_many_writer_slots` (32 per writer) / `too_many_writer_packages` (128 entries or 64 KiB per writer, v3 and v4 together); `400 bad_package` a new entry whose `v` is not 3 or 4 / `too_large`; `409 generation_full` (512 record declarations); `429 too_many_records` |
| `PUT S/common` | Either role; `If-Match: "N"`; exactly `{common}` | `200 {version:N+1}` + `ETag`; atomically changes only common and version, notifies sockets | `400` extra fields or invalid base64url; `400 common_format_unknown` / `409 common_format_too_old` (see «Common format»); `413` over 2 MiB decoded; `428` / `412` (+ current `ETag`); `429` shared credential/list write quotas |
| `GET S/slots/{personId}/{deviceId}` | Bearer; `If-Match: "N"` | `200 {version, slotVersion, data}` + `ETag` | `428` / `412`; `404` no such slot |
| `DELETE S` | Bearer; `If-Match: "N"` | `204`; everything is erased, the syncId is retired, sockets closed with `4404` | `428` / `412` |
| `GET S/ws` | `Upgrade: websocket`; `Sec-WebSocket-Protocol: gift-huddle.v2, bearer.<credential>` (or Bearer) | `101`, selects only `gift-huddle.v2`; pushes `{"type":"version","version":N}` after every new version; `ping` gets `pong` | `426` no upgrade; `401`; `404`; `429`; any client message closes `1008`; revoked `4401`; deleted `4404`; 16 sockets per list, the oldest closed `1008` |
| `POST S/capability` | Device or web Bearer; `{commonFormat: 2}`, optionally `renewalProtocol: 1` | `200 {version}` + `ETag`; monotonic: a new format or first explicit renewal announcement bumps the version and notifies; repeats change nothing | `400` other body |
| `POST S/revoke` | Bearer; `{deviceId}`; optional `If-Match: "N"` | `200 {version}` + `ETag`; revoking the final active credential, including a web, retires the whole list | `404` unknown device; with `If-Match`: `412` (+ current `ETag`) when the version is not exactly `N` |
| `POST S/invites` | Device Bearer; `{offer: PairingOffer.toJson(), inviteId?, guestPerson?}` (`offer.host.d` must be the caller's device) | `201 {inviteId, expiresAt}`; identical reservation retries return the same result | `400 bad_offer` / invalid id or person; `409 invite_exists` globally reserved by any different request; `413`; `429` at 10 unapproved open |
| `GET I` | Bearer of the owner | `200 {offer, answer, revealed, approved, canApprove, expiresAt}` (`canApprove`: an approval now fits the daily quota, the live checkpoints and the generation; advisory, B7) | `403` another device; `404` |
| `POST I/reveal` | Bearer of the owner; `{reveal: PairingReveal.toJson()}` | `200 {expiresAt}` | `409 invalid_state` before the answer or a second reveal; `400`; `403`; `404` |
| `POST I/approve` | Device Bearer of the owner; `If-Match: "N"`; `{package, role?, checkpoint?: {common, registry}}` (encrypted, opaque package; default role `device`; `checkpoint`: the two checkpoint hashes, B7) | `200 {version:N+1}` + `ETag`; registers the guest's verifier and immutable role; with `checkpoint`, copies the common and registry of version N for the guest | `400 role_mismatch` unless `answer.guest.k === "web"` iff role is `web`; `400` invalid role; `400 bad_checkpoint`; `409 checkpoint_mismatch` (the hashes are not those of version N); `409 invalid_state` before the reveal or twice; `409 credential_exists`; `409 generation_full` (64 credentials); `429 too_many_approvals` (8 per list in 24 h); `429 too_many_checkpoints` (8 live); `428` / `412`; `413` |
| `DELETE I` | Bearer of the owner | `204` | `403`; `404` |
| `GET J/offer` | none (the id comes from the QR) | `200 {offer, guestPerson, expiresAt}` (`guestPerson: null` when absent) | `404` unknown, expired, cancelled or owner revoked |
| `POST J/answer` | `{answer: PairingAnswer.toJson(), serviceCredentialVerifier}` | `201 {expiresAt}` | `400 person_mismatch` if the guest record's `p` differs from the reserved person; `400` unknown `k` (only optional `"web"`); `409 already_answered`; `409 credential_exists` (device id or verifier already in the list); `401` revoked verifier; `400`; `413` |
| `GET J/result` | Bearer of the guest (the credential behind the submitted verifier) | `202 {status:"pending", reveal}` + `Retry-After: 4` until approved, then `200 {reveal, package, minVersion, syncId}`, repeatable until installation acknowledgement or the invitation expires | `404` wrong or missing credential, acknowledged or gone |
| `GET J/checkpoint` | Bearer of the guest | `200 {common, registry}`: the exact common text and the registry as canonical JSON text copied at approval (B7), repeatable and immutable until the invitation expires, is cancelled or released | `404` wrong credential, not approved, approved without a checkpoint, released, or gone |
| `DELETE J/checkpoint` | Bearer of the guest | `204`: installation acknowledgement erases the entire invitation, encrypted package and checkpoint, and durably releases the global locator (also accepts approvals from older hosts without checkpoints) | `404` as above |
| `PUT G/prepare` | Bearer of that web; `{version, tokenHash, verifier, secret}` | `200`; prepares current version + 1 (initially 1); identical pending content is idempotent | `400` shape/size/encoding; `409 invalid_state` different pending content or wrong version; `403 forbidden_role` |
| `POST G/commit` | Bearer of that web; `{version}` | `200`; pending becomes current, erasing the previous secret; repeating current is idempotent | `409 invalid_state` not current or pending; `404` no guard; `403 forbidden_role` |
| `POST G/cancel` | Bearer of that web; `{version}` | `200 {version}` with the current version (0 if absent); removes only that pending version; absent/different pending is also `200` | `400`; `403 forbidden_role` |
| `POST G/open` | No credential; `{proofs:[{version,guardToken,prueba}]}` (1–2 distinct versions) | `200 {version,b,failedSince,mustRotate}` from a matching current or pending version; resets consecutive failures and delivers/resets failedSince | Uniform `404 not_found` for absent guard, wrong token or retired list; `403 {error:"wrong_pin",left}`; tenth consecutive failure and subsequent attempts: `423 guard_suspended`; `429` + `Retry-After` before 2 s or over 30/min/IP; `400` malformed proofs; `413` body over 2 KiB |
| `POST G/resume` | Active device Bearer from this list; no body required | `200`; clears suspension, consecutive failures and attempt delay; retains failedSince and sets mustRotate; keeps versions and secrets | `404` no guard; `401` credential from another list; `403 forbidden_role` web |

Common to every route: `401` for a missing, unknown or revoked credential (a
revoked Bearer is also `401` on the public invitation routes); `404` unknown or
deleted list; `400` bad shapes; `413` sizes and counts; `429` + `Retry-After` for
quotas; `415` without `application/json`; `404`/`405` for routes and methods.
The revoked-Bearer guarantee on public invitations applies only while the id
still routes to the list that revoked that credential (see reservation reuse below).
After retirement, the new common PUT and authenticated guard routes return
`410 retired`; guard open retains its uniform `404`. Older read routes retain
their v2 `404` behavior.

### Renewal command log (phase 3, batch 4, fourth round)

`R = S/renewal` belongs to the source generation and shares its CAS and lock.
The append-only signed log is authoritative. The active control is a bounded
projection containing `head`, `height`, `logBytes`, scalar phase fields and
command **hash references**, including the participant-indexed receipt maps.
No historical identity or revocation proof collection lives in that row.

| Request | Authentication / precondition | Result |
|---|---|---|
| `GET R` | Active mobile/web Bearer; optional If-None-Match | `200 {version, renewal}` and strong ETag; null only on an unreserved source; 304 when unchanged |
| `GET R/log/{operationId}/{head}/{after}` | Active mobile/web Bearer | Pinned public log page; zero-based height cursor; immutable prefix ending at the requested head; 404 for unknown head/cursor |
| `PUT R` | Bearer and strong If-Match equal to signed sourceVersion | Atomically append one command, update projection and increment source version once; exact current-revision retry is idempotent |

Page JSON is exactly `{sourceSyncId, operationId, head, height, after, next,
commands}`. `height` is the pinned tip's height. `after` is the number of commands
already obtained. `next` is after + returned count, or null exactly at height.
Pages carry at most 256 commands / 256 KiB of command JSON. Empty nonterminal
pages, repeated cursors and mixed tips are invalid. The client bounds a download
at 512 pages, 24,576 commands and 24 MiB. Each command is stored in its own
`renewal_command(operation,height,hash,data)` row, outside the control budget.
Old operation rows remain until the source is retired; abort does not prune them.
DELETE/expiry erases the log with the other source data.

Every signed command has exactly:

```text
{v:1, action, operationId, sourceSyncId, targetSyncId, revision,
 sourceVersion, signerDeviceId, prev, signature, ...actionFields}
```

`prev` is REQUIRED: null for the operation's first reserve, otherwise the
canonical hash of its immediate predecessor. Hash = unpadded base64url(SHA-256(
UTF-8 canonical JSON of the **entire command, including signature**)). Object
keys sort recursively; array order is preserved; numbers are safe integers;
there are no optional signed aliases. Ed25519 signs UTF-8
`gift-huddle-renewal-control-v2`, NUL, then canonical JSON without `signature`.
The Worker verifies each command's Ed25519 signature BEFORE append against the
credential's immutable signingKey. It captures the creator's unique registry key
on list creation and requires the guest's previously stored answer key on approval.
Older credentials without a pin return 409 renewal_key_binding_required until an
explicit authenticated migration supplies an immutable binding; a mutable registry
record is never used to choose or pin a renewal verifier. New registrations with
missing/ambiguous creator keys or missing guest keys return 400 with the same code.
Invalid signatures return 403 renewal_bad_signature without append. Phones still
independently verify trust.
All signed numbers are safe integers; Dart also rejects double commonFormat:2.0.

The Worker rejects `reserve` with `409 renewal_disabled` unless
`RENEWAL_ENABLED` is exactly `"true"`. It defaults to `"false"`; an absent setting
also closes the gate. Rejection precedes destination probes and source storage
effects. Keep it disabled until engine, reconnection and web integration are ready.
Even when enabled, every active service credential (including webs) must have an
immutable signing key (`409 renewal_key_binding_required`) and explicitly announce
`POST S/capability {commonFormat:2,renewalProtocol:1}` (`409 renewal_capability_required`
otherwise). Common-format support or a newly paired pre.29 key alone is insufficient.
Legacy bindings require an authenticated, verified migration or fresh pairing;
publishing a registry record never migrates them. The destination creator's immutable
key must also match `newSigningKey`, in addition to its public registry record.

This changes the signature domain; the old snapshot/historyHead format is not
accepted as log evidence. The previous format was never deployed: batch 4 is absent from local main
(fc8df2d), and the renewal engine is disabled. No legacy reader/writer/converter
remains. 409 renewal_upgrade_required only rejects unsupported development rows;
development stores must be recreated for this schema. If that deployment
precondition changes, a reviewed explicit migration is required before enabling
renewal; neither a reset nor a fabricated chain is a migration.
Ids, keys, signatures and private salted commitments
retain the bounds of ADR 0006. No secrets, clear manifests or gift hashes enter
the log. The first command binds sourceSyncId, operationId and starting source CAS.

| action | Extra signed fields | Transition |
|---|---|---|
| reserve | participants, newDeviceId, newSigningKey, targetCommitment, inventoryCommitment | Revision 1; every live service participant must be included |
| replace | reserve fields + previousTargetSyncId | Revision + 1, fresh destination/identity; keep acknowledged recovery branches |
| recover | same fields as replace | Revoked reservation creator required; reset active branch quota, append to the SAME log; no snapshot/archive operation |
| revise | participants, inventoryCommitment | Revision + 1, same target/reservation, fresh readiness and receipts; revoked creator requires replacement |
| ready | destinationVersion | Creator or previously transferred mobile attests full destination publication |
| ack | newDeviceId, newSigningKey, receipt, destinationVersion | Participant's immutable current-revision receipt; pairing alone is insufficient |
| exclude | participantDeviceId, loss:true, receipt | One explicit loss; mobile caller transferred, target revoked or individually inactive for 72 hours; never exclude a fresh ack |
| prepare | pendingResources:0, coverageCommitment | All participants resolved; establish signed content barrier at sourceVersion + 1 |
| confirm | snapshotVersion, pendingResources:0, coverageCommitment | Bind exact prepared source snapshot after final absorption/publication |
| abort | none | Current mobile authority; only without transfers, acknowledged branches, recovery or barrier; signed terminal tombstone |
| revoke | participantDeviceId | Current mobile revokes another live service credential, removes its own exclusion and invalidates the plan, atomically with append; no transfer or ack granted |
| resume | none | Excluded participant withdraws its exclusion and invalidates close; fresh revise/receipts required |
| capability | commonFormat:2 | Signed service capability change; at most one upgrade per credential |

Web credentials can read pages and sign their own ack/resume/capability; plan,
close and revocation commands require mobile authority. During an active renewal,
ordinary POST revoke/capability returns 409 renewal_signed_revoke_required /
renewal_signed_capability_required. The engine uses signed PUT R instead and also
persists the corresponding registry revocation and publishes it when possible.
The signed log event itself is sufficient evidence while the source registry is
frozen by a barrier; replay does not depend on a second source write. The service
credential role is never cryptographic source trust.

An authenticated excluded participant's request fences service close when its
confirmation is absent/stale. This increments source CAS once and is a conservative
service safeguard; it does not fabricate a signed transition. The returning
participant appends resume, or another mobile signs a fresh plan. Each credential
may resume once per operation, including across replacement/recovery. A separate
durable marker limits the activity fence itself to once per participant/operation,
even if it never signs resume. Revision clears pending fences without resetting
those markers. An effective signed revocation also withdraws the revoker's own
exclusion, allowing revalidation after its ordinary resume was already used.
prepare/confirm and DELETE stay blocked while an activity fence is pending. An excluded caller cannot revise
away its own exclusion. Fresh, still-current confirmation retains existing M4 rules.

The Worker accepts only the current prev and CAS. reserve/replace/recover additionally
require an already-created minimal destination with the committed live mobile
creator and signing key (409 renewal_destination_missing). The router probes it
before taking the source lock. No acceptance proves inventory conservation.

Clients fetch from their persisted verified height, check every prev/hash and
signature and enforce source/operation/revision/CAS. A verified in-memory previous
retains deterministic state and hash/identity/target/budget indices, applying only
the suffix while the relevant registry and trust inputs are unchanged. Forward
extensions share immutable command prefixes without copying the log. Forking an
older consumed cache reconstructs it safely. Trust changes recheck the prefix,
including linkage, roles, collisions and revocations; matching verified keys allow
prefix signatures to be reused. New suffix signatures are always verified.
Persisted JSON indices are never trusted. The Worker uses indexed lookups and atomic
per-signer usage rows, resolving only the bounded active projection per append.
Replay runs against current signed source trust. Without previous clients replay
from genesis.
Every projected field must equal replay, including all hash references. Historical
signatures remain evidence after revocation; only current authority permits new
actions. A previously verified/persisted abort remains a historical tombstone even
if its signer is later revoked, and permits starting another operation; newly
presented aborts require current authority. Apply CURRENT revocations to ALL identity statements, including mappings
in the active epoch and prior destinations. Veto old-target ids AND signing keys
across the complete target registry, including unvouched aliases; same-target
identities need explicit signed revocation. Recheck on pairing, publication and close.

A barrier is a state transition: prepare creates it; revocation/revise retain it;
replace/recover may extinguish the CURRENT barrier only without any still-live
historical transfer. A later ack cannot resurrect an already extinct barrier.
Branches (max 8 active acknowledged targets) are recovery references, never trust.

**Freshness requires a mobile anchor.** `RenewalControl.fromLog` requires a
`RenewalLogAnchor` independently persisted/received from a trusted mobile and
rejects heads that do not extend it. `previous` also supplies the source version
floor. A new observer can reject missing/reordered commands or an inconsistent
head, but no hash chain can detect a self-consistent old prefix supplied with its
old authentic head without an independent anchor. A Worker head cannot bootstrap
that guarantee. An older anchor proves continuity from that anchor, not unseen
advances; propagate the newest mobile observations during reconnection.
B7 currently does NOT sign renewal operation/head/height or the CAS floor. Engine
and pairing must extend the authenticated approval with source, operation, head,
height, observed CAS floor and pairing context; a destination checkpoint alone
cannot anchor the source renewal log.

Ordinary growth stops at 512 commands / 512 KiB (`409 renewal_log_full`).
No more speculative replace is accepted. An invalidated plan may still revise.
Each signer initially has 64 commands / 64 KiB of rescue. Every effective revoke
refills survivors with 40 commands / 40 KiB, through all 31 possible revocations.
A solo close with 32 participants uses at most 37 commands including resume,
revision, ready, own ack, 31 exclusions, prepare and confirm. Revoke also removes
the signer's own exclusion without granting a transfer or acknowledgement.
revoke, recover and terminal abort are exempt. The conservative reserve bound is
512 + 32*64 + (31+...+1)*40 + 2*32 + 1 = 22,465 commands, and 22,920 KiB
(less than 22.4 MiB), including 65 exempt rows of up to 8 KiB.
Global limits are 24,576 commands / 24 MiB, with at most 512 pages per operation.
The active control is 256 KiB; individual commands are 8 KiB; operations admit
32 participants including local and web identities, with 8 active branches.
Admission must include everyone before renewal starts; never truncate the plan.
New credentials (including the creator) require a signing key at registration.
Legacy credentials lacking an immutable binding return `renewal_key_binding_required`
until explicit authenticated migration; mutable registry records cannot bind them.
An activity fence is durable once per participant and operation, independent of
signed resume, and cannot be rearmed by revision plus repeated authenticated GETs.
Verified Dart controls retain replay state and indices in memory, apply only the
suffix under unchanged trust, and recheck the prefix when trust changes.
Exhaustion never licenses pruning evidence.
As with CAS contention, an uncooperative live signer can consume its own rescue
allowance; this is not a promise of unlimited retries or progress by that signer.

Normal content/registration quotas cannot block the log. Reservation cancels only
unfinished invitations, preserves approved results/checkpoints and blocks new
invitations/approvals. The barrier freezes PUT S/common and PUT S (also for web),
while reads/slots remain available. DELETE requires a currently migrated mobile,
a resolved current plan, current authority, confirmation and exact latest ETag.
A later mutation requires a new confirmation. No timeout cancels a reservation.

Before DELETE or journal reduction the engine MUST persist the complete signed
log, anchor, source registry/trust links and current signed revocations in the
destination context, transmit/verify them on reconnection, and enforce permanent
vetoes after source retirement. A reduced journal digest is insufficient. These
engine and pairing integrations, including restart + deleted source + another
reconnected mobile, remain pending. No engine/presentation is activated here.

### Roles and PIN guards

Roles are immutable service permissions, independent of signed registry trust.
Existing state rows without a credential role remain live and read as `device`;
the creator is always a device. Missing `role` is an explicitly supported old
format, not a missing mandatory field that triggers retirement. `approvedBy` stays
optional. Record `k`, when present in an offer, answer or registry, must be `"web"`.

Web credentials use an explicit allowlist on authenticated list routes: GET S,
GET S/renewal and PUT S/renewal for their own transfer acknowledgement,
GET slots, WebSocket, PUT S/common, POST S/capability (ADR 0005, B5), POST S/revoke for their own deviceId, and
prepare/commit/cancel of their own guard. Every other authenticated list route is
`403 forbidden_role`, including full PUT (any slot change, even its own name), DELETE, invitations,
all I routes, resume and other devices' guards. New routes start closed. Public J
routes retain their pairing rules, including delivery of the web's own result
after approval; knowing an invitation id grants no list management permission.

Guards use their own SQLite table in the list object and the same concurrency
lock. Each web has current/pending secrets and persisted failures, failedSince,
mustRotate, a rotation barrier, nextAttemptAt and suspension. All hashes and secrets are canonical unpadded base64url of 32 bytes.
Only hashes of guardToken and prueba are stored; `secret` is b. Open compares
hashes in constant time, counts one call as one attempt even with two proofs, and
never spends an attempt for token misses or throttling. Preparing, cancelling and
idempotent commits do not reset failures. Promoting a new guard version resets
failures, failedSince, suspension and the attempt delay so the old capability's
attempts cannot suspend the new one. Prepare rejects reuse of the current
version's tokenHash with `409 invalid_state`. A device can resume a guard but cannot prepare
or replace its secrets. Guard operations have no family write charge; authenticated
ones still share the credential's request cap. The unauthenticated open route has
its own persisted 30/min/IP quota in addition to IP_LIMITER and a streaming 2 KiB
body limit. Revocation deletes the corresponding guard in the credential
transaction; deletion and inactivity retirement drop the entire guard table.
Open validates proofs for live, absent and retired lists through the same path.
For each valid proof it always hashes both inputs and compares two fixed-size
version slots, using dummy values for missing slots or guards; uniform 404s do
not write guard state or spend attempts.

`failedSince` reports failures since the preceding successful open, survives resume,
and resets when delivered; resume sets `mustRotate`. An open with failures or
mustRotate persists the rotation barrier: authenticated web operations return
`409 guard_rotation_required` until a new version commits (idempotent commit of the
old version does not lift it); open retains its attempt limits for crash recovery,
and cancel only cleans pending state without lifting the barrier.
WebSocket upgrades from a web credential with this barrier return `401 unauthorized` until rotation commits.
The client rotates with the just-entered PIN and fresh salt, guardToken and b,
re-encrypting vault, queue and marks before opening the session; failure keeps it
locked for retry, and the old token returns `404` after commit.

The sealed browser vault contains a monotonic counter and a canonical SHA-256 hash
of the complete encrypted entry map and marks, updated in their transaction and
checked on reads; mismatch or an older vault without this binding is an integrity error. This detects partial rollback
and in-session stale boxes; detecting a full-store rollback after restart needs
an external anchor. A failed PIN change cancels and deletes its local pending set
only when cancel confirms the old version is still current, otherwise it locks
and preserves the recoverable set.
If a PIN change or its current-PIN rotation closes the vault, the gate also locks the session, stops its engine and returns to unlock (retaining suspension or disconnection errors).

Client invitation ids reserve globally in InviteV2Object under its lock, bound to
syncId, owner deviceId, canonical offer digest and guestPerson. A live reservation
is never overwritten. Retrying returns its original expiry, 24 h from creation;
cancelling, revoking the owner/guest or deleting the list releases it. An expired
reservation can be reused even if its alarm has not run. Server-generated random
ids use the same reservation. Old locators remain readable and reserved until
their existing expiry.
After release, only a routing stub (syncId and the original expiry) may remain
until the 24 h alarm: it never reserves the id or blocks reuse, and preserves the
existing `401` for revoked Bearers on public invitation routes. Owner, offer
digest and guestPerson are erased from that stub.
This `401` lasts only until the original expiry or reuse of the id. Reuse replaces
the locator: public requests go to the new list, whose public offer can return
`200` even with a Bearer revoked in the old list. That credential still grants no
access to either list's authenticated resources.

Cancellation, revocation and retirement record pending releases durably in the
same SQLite transaction as the local mutation. RPC errors return `500` for
explicit cancellation/revocation/deletion; recovery runs on later requests and a
retry alarm, including after reconstruction of the object. A release is removed
from the queue only after acknowledgement. Each new reservation has a random
internal identity, so a delayed release cannot affect a later reservation even
with the same syncId and expiry (old reservations retain tuple-based matching).
Retirement immediately denies access and erases content, keeping only a retiring
marker and pending releases until cleanup succeeds; then only the bare retired
marker remains. The invite-row UPSERT refreshes both the data and SQL expiry when
an expired id is reused before cleanup.
While a release of an `inviteId` is pending in this list, that id cannot be
recreated there (`409 invite_exists`), so a late release never frees a recreated
invitation; other lists cannot take it either until the release is confirmed. The
drain skips failing releases without blocking the rest and drops those whose
reservation has already expired (it expires by itself). The queue is capped at 10
(`MAX_OPEN_INVITES`): at the cap, creating or cancelling an invitation returns
`429` with `Retry-After` until it drains. A retired list keeps its retiring marker
and queue only until the releases are confirmed or expire; then only `{retired:true}`
and its 400-day deletion deadline remain.

### Atomic snapshot

- `common` is the opaque common envelope (base64url, 2 MiB decoded at most).
- `registry` is `DeviceRegistry.toJson()`; only its three arrays and its size are
  checked, never a signature.
- `keyPackages` is an array of encrypted `KeyBundle.toJson()` objects.
- `slots` is a **delta** of `{personId, deviceId, data}`: `data` is the base64url
  text of a sealed slot (an element of `SlotSet.toJson()`), `null` removes it, `[]`
  keeps every slot. The slot header (magic `GHS`, format 2) must name the same
  person and writer as the resource, have policy flags 0 or 1 and both revisions
  below 2^53, and the slot must have the exact size of its header plus 131,164
  bytes (nonce, 128 KiB of ciphertext, tag and signature), measured from the text
  length (`400` otherwise). That is what `SealedSlot.parse` checks, so a slot that
  no phone could parse never gets stored. The server reads only the header, never
  the signature or the ciphertext.
- **Slot ownership (ADR 0005, 7, B2).** For every entry of the delta, with data or
  with `data: null`, the caller must be a device credential (`role: device`) and
  `deviceId` must be its own. Nobody removes another writer's slot: not of an active
  writer, a revoked one, an orphan with no credential, a deleted person or an old
  epoch (the server knows neither persons nor epochs, so all of them are just another
  writer's resource). The whole delta is checked before anything is written: one
  foreign entry refuses the request (`403 forbidden_slot`) with no partial effect,
  and a web credential is `403 forbidden_role`. A resource listed twice in one delta
  is `400 bad_request`. Replacing one's own slot is a single row upsert inside the
  PUT transaction, never a delete followed by a write. The same rules apply on
  create (`If-Match: "0"`) and on update. Abandoned slots keep their place in the cap
  of 64 until their writer removes them or the family renews (`capacity.slots`).
- **Per-writer cap.** One writer holds at most 32 slots (`413 too_many_writer_slots`),
  one per protected person, so a single credential cannot fill the list's 64 on its
  own (32 rather than 16: with two or three phones, 16 would cap the protected people,
  and renewing does not change that). A writer already above
  it (an older server) may still replace and remove, never add. At 64 a PUT that
  adds a slot is `413 too_many_slots`; replacing one's own still works.
- **Key package ownership (ADR 0005, B3).** An entry of `keyPackages` that is not
  already stored (compared as exact JSON) must carry `from` equal to the caller's
  `deviceId` and come from a device credential; otherwise the whole request is
  `403 forbidden_package` (`403 forbidden_role` for a web). A list with the same entry twice is `400 duplicate_package`, so copies of a stored entry cannot skip these checks. Stored entries forwarded
  unchanged are kept, because older apps upload the whole list, and dropping any
  entry is allowed. A new entry must have `v` 3 or 4 (`400 bad_package`). One writer holds at most 128 entries and 64 KiB (the sum of each entry's JSON), v3 and v4 together: a quarter of the list, so it takes four credentials to fill it
  (`V2_MAX_PACKAGES_PER_WRITER`, `V2_MAX_PACKAGE_BYTES_PER_WRITER`, `413 too_many_writer_packages`) unless it already
  had more, so one credential cannot fill the 512 and block a key rotation. The
  same rules apply on create and on update.
- **Common format (ADR 0005, B4).** The common is an `RG` envelope whose third byte
  is its format: 1 (the family key of ADR 0004) or 2 (signed, sealed with an epoch
  candidate). Each list keeps a minimum (`minCommonFormat`, absent: 1) that only goes
  up. A format later than the server knows (`RG` + 3 or more) is `400
  common_format_unknown` on create, `PUT S` and `PUT S/common`, whatever the
  minimum, so one credential cannot make every phone stop and ask to update. Below
  the minimum is `409 common_format_too_old` (an old client cannot degrade the
  family), and with minimum 2 text that is not an `RG` envelope is `400`. With
  minimum 1, as before, other text is accepted: a phone that has made the cut treats
  it as forged and replaces it; one that has not fails to open it, as before.
  - `POST S/capability {commonFormat: 2}`: a device or web credential (ADR 0005, B5:
    the web reads and signs the common) announces it reads and writes format 2. Monotonic; the snapshot shows it in `devices[].commonFormat`.
    It is service data, not signed trust: the phones decide the cut-over (every
    active member of their registry announced) and a lying server can only delay it
    or break availability.
  - `PUT S` (update) with `minCommonFormat: 2` raises the minimum in the same
    transaction that stores a format-2 common: only from a device credential
    (`403 forbidden_role` for a web), only when **every** live credential of any role,
    webs included, has announced it (`409 common_format_unannounced` otherwise: the
    phones check their registry, but only honest ones do), and the common must
    already be of that format. A lower value never lowers it.
  - Create (`If-Match: "0"`) may carry `minCommonFormat: 2`: a generation born in
    format 2 (renewal); its creator counts as announced.
  - The minimum is part of the state row. Any safe integer from 1 is a valid stored
    value (the upper bound applies only to what arrives through the API); one above
    what this server knows (a rollback of the Worker) refuses common writes with
    `409 common_format_unsupported` without retiring the list. Anything else is
    malformed and retires the list like any other malformed field.
- Approval refuses (`409 credential_exists`) a guest id that already has slot rows,
  so leftover rows never become a new credential's own.
- A PUT replaces `common`, `registry` and `keyPackages` and applies the slot delta in
  one SQLite transaction with one new version. Two writers with the same ETag: one
  wins, the other gets `412`.
- Reading: `GET S`, then `GET S/slots/...` with `If-Match` set to that version for
  each slot whose manifest `version` changed since the last sync (an unchanged slot
  keeps the version that last wrote it). A `412` means the snapshot moved: drop the
  partial read and start again. Only after every piece has the same version does the
  phone reconcile: registry first, then packages, then slots (ADR 0004, 7 rest and 13).
- `devices` lists the service credentials the server accepts, and the revoked ones.
  The server does not decide trust; a phone that finds an active device that its
  registry does not support can revoke it.
- `capacity` is `{credentials:{used,warn,max}, records:{used,warn,max}, slots:{used,warn,max}, renew}`: credentials
  ever registered in this generation (revoked included; warn 48, max 64), distinct
  record declarations it has seen (warn 384, max 512) and stored slots (abandoned
  ones included; warn 48, max 64). `renew` is true from any warning on; the app then offers to renew (see «Generations» below).
- Only exact strong validators are accepted: no `*`, weak ETags or lists (`412`).

### Pairing and revocation

The flow is `pairing_v2.dart`. The host posts the immutable offer (its record and
the nonce commitment). The guest reads it **before** choosing its record, then posts
exactly one answer (its record and its vouch for the host) with the SHA-256 of its
new service credential. Only then may the host reveal the nonce; the guest sees it
in the `202` of `result`, checks the commitment and both phones show the six-digit
code. After a person confirms it, the host publishes the guest's record and its own
vouch with a conditional PUT and approves with the returned ETag and an encrypted
package (family key and the slot revisions it knows). Approval registers the guest's
verifier and bumps the version (`minVersion`); the guest must read a snapshot at
least that new and check those revisions before trusting slots. The server only
checks bounded shapes; it never verifies signatures, codes or commitments.

Revocation, PUT, DELETE, approval and every invitation step run under the same lock
of the list object, so they are totally ordered. Revoking needs no If-Match: it drops
the target's credential (its hash stays only as a rejection tombstone, so it cannot
register again under another id), bumps the version, closes its sockets with `4401`
and deletes the invitations it owns or answered. From then on the credential is
refused on GET, PUT (registry included), DELETE, slots, WebSocket and invitations.
A write ordered before the revocation stays. A credential the revoked device approved
earlier stays too, visible in `devices`. The signed revocation, the new epoch and the
key rotation are published later by the phones.

Secret-gift slots are shared ciphertext per (person, writer), encrypted with the
person's surprise key. Writer ownership governs mutations, not readership: every
authorized phone with that key can read and merge the slot. Revocation therefore
retains the writer's slots to avoid deleting other phones' gifts, while denying
all further service access to the revoked credential. The Worker cannot infer a
sole reader from the opaque key packages or the signed registry. Slots still go
with list deletion or inactivity expiry.

`If-Match` on `POST S/revoke` is optional (B2). Without it the revocation is
unconditional, as before: explicit ones («Quitar un móvil», leaving the family, a web
revoking itself, the registry's own revocations) and older phones keep working. With
it, the version must be exactly the current one or the answer is `412` with the
current `ETag` and nothing changes. Phones send it for **conditional** revocations,
the ones decided from a snapshot (an active credential the registry did not back in
the verified `GET`): after a `412` they read, verify and decide again, so a vouch
published between their `GET` and their `POST` is never cut. An already revoked
target with a matching `If-Match` is still `200` with the same version.

### Pairing checkpoint (ADR 0005, B7)

A guest must install exactly the state its host approved, never "whatever the next
GET says". When the host approves with `checkpoint: {common, registry}`, the list
object, under the same lock and the same `If-Match`, copies its current common and
registry into `checkpoint` rows of that invitation and checks the two hashes: each
is base64url(SHA-256(`"gift-huddle-pairing-checkpoint-<part>-v1"` ‖ 0x00 ‖ text)),
where the text is the common's stored base64url and the registry's canonical JSON
(sorted keys, `JSON.stringify`). A mismatch is `409 checkpoint_mismatch` and
nothing is registered. The guest downloads `GET J/checkpoint` and checks both hashes
against the host's **signed** approval: the server only checks coherence and keeps
the copy; the phones check security. A server that withholds the checkpoint leaves
the pairing pending; it can never make the guest install another base.

Each copy lives as long as its invitation (24 h) and goes with it: `DELETE I`, the
owner's revocation, expiry (the alarm) and retirement, and the guest releases it
once installed (`DELETE J/checkpoint`), deleting the invitation and encrypted package too. At most 8 live checkpoints per list, as many
as approvals in 24 h (`429 too_many_checkpoints`), each at most one common (2 MiB)
and one registry. The registry text is written pair by pair in sorted key order
(`canonicalJson`), never through an object, so integer-like keys keep the app's order.

Deploy the Worker first (it still accepts approvals without a checkpoint); phones and
the web go together afterwards, since an old phone and a new one no longer pair.
An approval with a checkpoint costs two SHA-256 over at most one common and one
registry plus one copy: a few milliseconds of CPU.

### Deletion, expiry and retired syncIds

A confirmed DELETE (exact ETag) erases everything at once, in one transaction:
common envelope, registry, packages, slots, PIN guards, invitations, credentials, revocation
tombstones, device ids and record hashes. It closes the sockets with `4404` and
replaces the cleanup alarm once all queued invitation releases are acknowledged. While
cleanup is pending, the retiring marker denies access and a retry alarm remains.
After cleanup, the object keeps only a **retirement marker**: its single state
row becomes `{"retired":true}`, with no credentials, device ids, hashes or
content (the object is addressed by the syncId itself). A separate `retiredUntil`
storage value and DO alarm erase the marker 400 days after retirement starts.
Cleanup retries and rejected requests never extend this deadline. Until then,
`PUT S` with `If-Match: "0"` on that syncId is `410 retired`; common PUT and
authenticated guards also answer `410`. Open and the older read routes answer
`404`, as for an unknown list. A new list takes a new random syncId.

The inactivity deadline is separate: a list without access for 400
days is retired the same way, by its alarm or by the first request that finds it
expired. Its retirement marker then has its own 400-day retention period.
After marker expiry the object is empty and the old syncId could be created
again with `If-Match: "0"`; updates naming an old version still fail. Clients
continue to generate fresh random syncIds. Pre-upgrade bare markers have no
retirement date or alarm: on their first wake they acquire a 400-day deadline.
No schema replacement or Durable Object migration is needed.

New apps creating a list solely to invite send optional `inviteCopy: true` in
the creation PUT. The server persists a fixed creation + 24 h deadline and arms
its alarm in that request, even if no invitation is subsequently published.
Reads, writes and new invitations never extend it. Approval of a mobile or web,
or publication of a recovery capsule, clears the deadline in the same transaction
as that operation. The copy then follows ordinary inactivity retention, even
if that credential or recovery code is later removed. The app writes its local
cleanup marker before upload, so restart can also delete the copy and rotate
the syncId. Persistent sync/recovery creation omits this flag. Pre.29–pre.31
clients also omit it and retain their previous 400-day inactivity semantics;
their abandoned invitation copies cannot safely be distinguished from permanent
single-phone sync copies. Already stored copies are not reclassified.

Invitation reservations hold the syncId, owner id, offer digest, guestPerson and
expiry and internal reservation identity; successful cancellation releases the id and strips the locator to its
temporary routing stub; the 24 h alarm erases it. The list also
refuses the exchange as soon as it expires, its owner is revoked or the list retires.

### Daily quotas and generations

Record declarations (`registry.records[]` entries) are hashed as serialized and the
hashes kept, including those later removed: bringing one back is free, a new or
re-serialized one costs a token. Two sliding 24 h windows apply to every PUT, after
creation (the first registry is bounded by its own 64 records): **8 per credential**
and **16 per list**, shared by every credential, so extra credentials of one person
do not multiply the budget. **8 credentials per list** may be registered (approved)
in any 24 h. Over a window the answer is `429 too_many_records` or
`429 too_many_approvals` with `Retry-After` set to when the oldest stamp that is in
the way leaves the window (a PUT with more than 8 new declarations never fits: split
it). The windows are timestamps inside the one state row, pruned on every use (at
most 8 per credential, 16 and 8 per list), so they cost no extra rows.

A **generation** is one syncId. It may register 64 credentials ever (revoked
included) and see 512 distinct record declarations ever. At either cap the answer is
`409 generation_full`, permanent for that syncId. The GET `capacity` warns from 48
credentials, 384 declarations or 48 stored slots (B2: other writers' slots are never
removed, so abandoned ones only go away with renewal), so the app offers to **renew** before that: a new
syncId, family key, keys and registry, with fresh counters, and only the confirmed
phones paired again in person. The old list is deleted (and so retired) only after
the transfer is safe. ADR 0004, «Cupos, generaciones y renovación», has the flow and
the app's own thresholds.

### V2 bounds and storage cost

| Bound | Value |
|---|---|
| Slots | 64 per list, counting stored ones after the delta, checked before any record hash or write; each at most 131,584 bytes decoded (175,446 base64url characters): header with the longest ids, nonce, 128 KiB, tag and signature |
| Registry | 64 records, 256 vouches and 64 revocations (counted before measuring), and 256 KiB of JSON: full caps weigh about 110 KB with 22-character ids and about 231 KB with 128-character ids |
| Key packages | 512 entries, 256 KiB of JSON |
| Bodies | Read before the credential is checked, counted while streaming: PUT and common PUT 5 MiB (common itself at most 2 MiB decoded); create (`If-Match: "0"`) 400 KiB on the wire and 256 KiB of JSON in the object; invitations 128 KiB (offer and answer 16 KiB, reveal 1 KiB, package 64 KiB); revoke 1 KiB; every guard route 2 KiB |
| Per credential | 120 requests and 30 mutations per minute, kept in the object's `rate` table so a restart keeps the window (mutations saved on every hit; reads every 8 hits and when full, a restored read counter adds the 7 it may lack); 8 new record declarations in any 24 h after creation |
| Per list | 60 mutations per minute, saved like the credential mutations (revocation is exempt, so another writer cannot block it); 30 public requests per minute and invitation; 16 new record declarations and 8 new credentials in any 24 h; 10 unapproved invitations; 16 sockets |
| Per generation (syncId) | 512 distinct record declarations and 64 credentials ever, revoked included (`409 generation_full`); renewal offered from 384 and 48 |
| Per IP | 120 v2 invitation requests per minute (`INVITE_IP_LIMITER` rate limit binding: no object and no row, so it costs nothing before the invitation is known; several families behind one NAT can pair at once); a separate 30 guard open requests per minute; 12 new v2 lists per hour (a phone alone deletes the list of a cancelled invitation and makes a new one); the coarse 200 requests per minute of `IP_LIMITER` in front of everything |

The quotas bound ADR 0004 finding 4 without reading signatures.

Storage (one SQLite object per list): one state row (version, last access,
credentials, tombstones, record hashes, quota stamps), the common envelope in rows of 1,000,000
characters, one row each for registry and packages, one row per slot and one per
invitation and one per web guard. Rows are rewritten only when their content changes. Request counters
live in memory and in a small `rate` table (`WITHOUT ROWID`, one row per live counter, dropped
with the list): mutation counters are written on every mutation, read counters every 8th
read, so a quiet GET writes nothing (except the hourly last-access touch and its
alarm). A normal PUT that changes the common document and one slot writes about 3 to
4 rows; replacing all 64 slots writes 64. A full list holds about 15 MB (common
2.8 MB, slots 11.2 MB as text, registry and packages). The free plan's 5 GB and
100,000 rows written per day are per account, and its 10 ms of CPU per request cannot
parse a body near the maximum: phones should send only the slots that changed (their
own, plus removals). Quota stamps ride in the state row the PUT or approval rewrites
anyway, so they add no rows. Retiring a list drops its content tables and rewrites
the state row in one transaction, with pending release rows until remote cleanup
finishes; afterwards the marker and deadline remain until the 400-day expiry alarm.
Nothing here meters or logs usage; check the account totals before
launch.

### V2 compatibility and v1 retirement

V2 keeps its independent namespaces and wire contract for installed pre.29–pre.31
clients. Every v2 object access selects `.jurisdiction("eu")` before `idFromName`.
Local workerd does not implement jurisdictions, so `test/runtime.ts` installs a
test-only EU adapter. Production never falls back to an unrestricted namespace.

V1 is retired by the 2026-11-15 product decision. Its API always returns 410 and
`v4-delete-v1` deletes its three classes and all their data at deployment. Apps
may still import old local files; there is no server migration bridge remaining.

## Personal recovery v2 (ADR 0007)

The normative contract is [ADR 0007](../docs/adr/0007-recuperacion-con-codigo.md).
This Worker implements storage and service authorization only; recovery setup,
Argon2/AES, installation and complete restoration belong to the app batches.
The Worker never receives words, entropy, private keys or decrypted payloads.

`S = /v2/lists/{sid}`, `R = S/recoveries/{rid}`, `P = /v2/recoveries/{rid}`.
All new responses are JSON when they have a body, with `Cache-Control: no-store,
no-transform`. Capsule ETags are independent of ordinary snapshot versions.

| Method / route | Authorization / precondition | Result |
|---|---|---|
| `GET S/recoveries` | Active mobile Bearer | `200 {v:2,recoveries:[{deviceId,recoveryId,revision,state}]}`, max four active rows; no ETag, verifier or blob |
| `PUT R` | Owner mobile Bearer, `If-Match: "0"` and `X-Recovery-Operation` for creation, `"N"` for replacement | `{v:2,deviceId,readVerifier,capsule}` → `201` / `200 {v:2,recoveryId,revision}` + ETag |
| `DELETE R` | Any active mobile in the list, `If-Match: "N"` | `204`; original principal/CAS replay is repeatable after reopening |
| `GET P` | `X-Recovery-Cap`, no Bearer needed | `200 {v:2,recoveryId,revision,capsule}` + ETag; candidates may be downloaded for verification |
| `POST P/claim` | Capability and current owner Bearer, `If-Match: "N"` | `{v:2,operationId,newCredentialVerifier,capsule}` → `200 {v:2,recoveryId,revision,operationId,deviceId}` + ETag |
| `POST R/rotation` | Owner mobile Bearer, old capsule CAS | `{v:2,operationId,newRecoveryId,readVerifier,capsule}` → `201`, candidate revision 1; old code remains active |
| `POST R/rotation/{op}/commit` | Owner mobile Bearer, old capsule CAS, exact `{v:2}` | `200`, atomically activates candidate and retires old code; exact commit receipt is repeatable |

Unknown/retired resources, wrong capabilities and revoked/web owners share `404
not_found` without ETag. Syntax and streaming size checks precede discovery. A
candidate with the correct capability is GET `200`, claim `409 recovery_not_active`;
the wrong capability is `404` for both. With an active resource and valid capability,
claim first checks its last receipt: matching old verifier/op and exact body/CAS
returns the original response, altered bytes/CAS give `409 recovery_operation_conflict`.
Otherwise a retired claim verifier is `403 credential_replaced`, an unknown Bearer
is `401`, and CAS gives `428`/`412`. Later revocation/removal overrides receipts.

Claim replaces capsule, revision, credential, permanent retired-verifier entry,
quota and receipt in one SQLite transaction. It also deletes invitations owned by
or answered by that mobile, including approved results/checkpoints and reservations.
Public keys, persona, registry and ordinary encrypted documents are unchanged;
the ordinary list version advances to notify other clients. All authorization
paths reject a retired verifier, including guard, renewal and public invitation
routes. A proposed credential cannot reuse registered, denied, retired or reserved
verifiers. Deleting a code does not rehabilitate any credential.

Socket attachments bind `deviceId` and `credentialVerifier`. Authorization is
rechecked before every version/pong and on receipt, including after hibernation.
Text pings share a durable limit of 12/minute per device across sockets; excess
or any other client message closes with `1008`. Pings inspect stored state and
do not run locator maintenance. Attachments without a current credential binding
close with `1008` so the next HTTP handshake determines their status; `4410` is
reserved for a verifier recorded as retired by claim.
Claim closes old sockets with `4410 credential_replaced` before responding; the
send gate also covers a crash between commit and explicit close. Legacy attachments
without this binding close. A later revocation takes precedence (`revoked`).

Discovery uses `RECOVERIES_V2.jurisdiction("eu")`, named by canonical 32-byte rid.
Locators store only list id, reservation token, link state and dates. Creation and
rotation first commit a list intention, reserve that token globally, commit the
blob in the list, then confirm discovery. Identical retries repair interrupted
phases. A known global conflict discards the unassigned intention and refunds its
provisional quota; a successfully reserved but abandoned intention consumes its
historical id until list retirement and locator expiry. Reserved reads always query the authoritative list: no blob
means `404`; committed blobs work even if confirmation was lost. A 24-hour alarm
consults the list, confirms existing blobs or acknowledges durable cancellation
before retirement. An unavailable list retains the reservation and retries in 24
hours. A retired locator retains only state, its alarm and a fixed retirement
deadline for 400 days, refusing reserve/confirm and
returning no discovery result. Its DO alarm then erases all storage. Repeated
retire/confirm/discovery calls do not extend the deadline. Old undated retired
locators acquire it on first wake. Unknown reads create no locator rows or alarms. Cleanup RPCs persist in a
list queue across crashes; stale discovery never bypasses current authorization.

Capsules use exact GHR02 magic and canonical header, exact Argon2 parameters,
1 MiB total binary / 1024-byte header bounds and strictly increasing safe revisions.
PUT/claim/prepare stream at most 1,400,832 bytes; commit is at most 4096 bytes;
GET/DELETE reject any body byte. There is one active code per mobile, at most four
per list (4 MiB), and one temporary 1 MiB candidate per list, expiring after 24 hours.
PUT or claim advancing the old CAS cancels that candidate. Prepare replays after
commit return its `200` receipt; cancellation/expiry return their terminal `409`.

Recovery quotas are independent and durable: public GET/claim 30 per IP/minute
before discovery, six mutations per list/minute and six ordinary writes per device
and 24 per list per UTC day (creation, replacement and prepare). Claims have an
exclusive daily reserve of two per device and eight per list. Budgets follow device
identity across credential replacements. DELETE does not spend the daily budget.
Exact replays skip mutation/day quotas, while ordinary traffic limits still apply.
Generation history is capped at 32 assigned ids per device and 256 per list, 512 receipts (4096 bytes each),
256 retired claim verifiers and 4 MiB metadata. Before mutation, two receipt slots
and 8 KiB metadata are reserved per id for initial/terminal results, plus a reusable
claim receipt per live code; retired hashes reserve 256 bytes each. Exhaustion is
`409 recovery_history_full`; terminal DELETE/revocation use reserved space. Never
prune tombstones or hashes to admit new writes. List retirement erases all recovery
blobs/history/verifiers after 400 days; public recovery GET does not refresh activity.

Locator reservation failures return `503 recovery_unavailable` with `Retry-After: 60`;
the durable intention and its quota charge survive for an exact retry. Recovery
headers are syntax-checked before streaming a body, independently of discovery.

Acceptance coverage is in `test/recovery.test.ts`, with invitation and ordinary
protocol regressions in `test/v2.test.ts`. Run both with:

```sh
pnpm vitest run test/recovery.test.ts test/v2.test.ts
pnpm exec tsc --noEmit
```

## Shared request limits

All live routes use the approximate `IP_LIMITER` binding (200 requests/minute
per client). V2 invitation routes additionally use `INVITE_IP_LIMITER` (120/minute
per client) and exact list-object counters (30/minute per invitation).
`LimiterV2Object` enforces 12 new lists/hour per client; initial uploads are
limited to 256 KiB. Clients are IPv4 addresses or IPv6 /56 groups. Unknown
invitations create no persistent rows. Retired v1 requests use none of these bindings.

## Privacy

- V1 storage is deleted by `v4-delete-v1`. V2 stores, per list: the SHA-256 of each service credential and of each revoked one (a rejection tombstone), device ids, the random syncId, the opaque common ciphertext, the **unencrypted signed registry** (public keys, person of each device, who vouches for whom, revocations), encrypted key packages, sealed fixed-size slots (their header shows person, writer, epoch, revision, policy and key id in clear), the version that wrote each slot, hashes of record declarations, the times of the new declarations and approvals of the last 24 h (quota stamps), and temporary pairing declarations (offer, answer, reveal, encrypted package) for at most 24 h. Per-device `lastRequest` is rounded up to an hour, including legacy exact values when the list next records activity. Renewal uses this upper bound, so its 72-hour absence requirement can be delayed by less than one hour but never shortened; renewal remains disabled in production. List-level `lastAccess` is rounded up to the hour on creation, writes, recovery operations and touches, including legacy exact timestamps on authenticated activity. After DELETE, revocation of the final active credential (phone or web), inactivity expiry or an invitation-only copy's fixed 24-hour deadline, content and credentials are erased; pending locator releases retry durably. The remaining `{"retired":true}` marker and separate deadline expire 400 days after retirement begins. Recovery locator retirement markers contain only `state`, `alarmAt` and `retiredUntil`: no `sid`, `reservationId` or `reservedAt`. They also expire 400 days after retirement; legacy markers are minimized when read. Old undated markers gain an alarm on first wake. New apps label invitation-only copies at creation; older clients and existing copies keep ordinary inactivity retention. Shared secret-gift slots survive writer revocation for the remaining authorized readers, until list deletion/expiry. That is metadata, never gift text, family keys, private device keys or surprise keys. The client IP (IPv4 or IPv6 /56) is used only as a rate-limiter key; v2 limiter rows expire with their window. Every v2 object (lists, invitation locators, recovery locators, limiters) is created in the EU jurisdiction; Cloudflare still terminates the request at its nearest edge, so this is not a claim that every network step stays in the EU.
- The v2 `rate` table keeps, per live counter, only a key (`r:`/`w:` and a device id, `list`, or `i:` and an invitation id), the window start and a count; expired rows are dropped as others are written, and the table goes with the list.
- No `console.*` calls exist; errors are generic (`{"error":"internal"}`) and nothing about bodies, `Authorization` or `X-Recovery-Cap` headers is recorded. Workers Logs (`observability`) is disabled in `wrangler.toml`. Do not turn on `wrangler tail` or Logpush for this Worker: request URLs contain list, invitation and recovery ids, and `X-Recovery-Cap` is a secret read capability.
- PIN guards store per web and version only SHA-256(guardToken), SHA-256(prueba) and b, plus version/pending version, failures, nextAttemptAt and suspension in SQLite. No PIN, raw proof, raw guard token, browser vault, salt, a, A or vault key is stored or logged. Invitation reservations also hold owner id, offer digest, guestPerson and expiry for at most 24 h. Guards disappear on revocation, DELETE and inactivity retirement.
- `ALLOWED_ORIGIN` is an exact comma-separated allowlist: `https://gifthuddle.app,https://web.gifthuddle.app`, never `null` or foreign origins; native requests without Origin remain valid. Admission and response headers use the same list, echo only the admitted origin and send `Vary: Origin`, including guard/open routes and upgrades. Preflight uses the route method map and an explicit header allowlist (If-Match added for v2), without touching quotas or objects. It never enables cookies. A paired browser has a restricted web credential; CORS grants no authentication or surprise keys.
- Responses carry `Cache-Control: no-store`, ETag where applicable, and `X-Content-Type-Options: nosniff`. V2 WebSocket forwarding constructs a fresh header allowlist with only Upgrade, the computed verifier and optional fixed protocol; Authorization, Cookie, bearer protocols and arbitrary sensitive headers never reach its object.

## Free plan figures that matter here

From the Cloudflare documentation (check them again before launch, they change):

- Workers: 100,000 requests per day and 10 ms of CPU per request. A 2 MiB envelope is the worst case for CPU; real lists are a few KB.
- Durable Objects: 100,000 requests per day (HTTP, RPC calls, alarms; WebSocket messages count 1 per 20). Sync costs 1 Worker request + 1 DO request, an invitation step 2 to 4. 13,000 GB-s per day of duration.
- SQLite storage: 5 GB per account, 100,000 rows written and 5 million rows read per day. Deletes and each `setAlarm()` count as rows written. A `PUT` writes about 3 rows.
- A row, string or blob is at most 2 MB, so the envelope text is split into rows of 1,000,000 characters.
- At most 100 Durable Object classes per account (this uses 4).
- Hibernating WebSockets cost no duration while idle. V2 wakes the object to revalidate the credential before `pong`.

Over the quota the Worker returns errors; the paid plan (5 USD per month) lifts them.

## Known limits

- Creating lists is capped at 12 per hour per IPv4 address or IPv6 /56, with at most 256 KiB each at first upload. A determined attacker with many addresses can still create lists: each one is a Durable Object with a SQLite database, a row with a 256 KiB envelope at most, and a 400-day alarm. They count against the free plan's 5 GB and 100,000 daily row writes. Watch the dashboard once the app is public.
- A first upload larger than 256 KiB is refused with `413`: the client must upload a small first version and grow it with a normal update.
- The first person to `join` an invitation takes its single slot. The 6-digit verification code is what stops an interloper from being approved; a stranger with the link can only make the owner reject and create another invitation.
- V2 list and recovery locator retirement markers expire after 400 days. While they exist they prevent identifier reuse; after erasure a fresh create/reservation may reuse the identifier. Pre-upgrade undated markers can only acquire an alarm when their object next wakes.
- V2 keeps the result repeatable for the guest until installation acknowledgement, cancellation, revocation or the fixed 24-hour expiry. A lost package response can be retried before installation acknowledgement. Acknowledgement deletes the invitation and its package immediately; failed locator cleanup retries durably. Mobile apps persist their acknowledgement and retry it on foreground sync. Installed older clients retain their existing best-effort acknowledgement/expiry fallback.


## Mobile recovery removal and dialog integration

`RecoveryApplication.removalStopsRemoteSync()` is an advisory async query for the
removal confirmation dialog: true means the server currently has no other active
credential, counting both phones and webs. Show a warning that removing the code
also deletes the encrypted server copy and returns to "Only on this phone".
A failed/offline query must not imply that deletion succeeded. `retireCode()`
rechecks the server, removes the capsule, then conditionally deletes the list
if nobody else has access. A durable pending flag retries interrupted removal;
a concurrent new credential is preserved. With another credential, only the
code is removed and synchronization remains enabled. No screen/ARB text changes
are included in this batch.

Both this operation and "Stop syncing" select a new local generation with
`remoteSyncEnabled` cleared. "Enable" alone cannot publish it. Common gifts,
secret scopes and overflow stay local, using the generation journal where
recovery already manages storage. Pairing a phone/web or creating a new recovery
code can explicitly activate synchronization again.
