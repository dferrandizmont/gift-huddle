# Operator maintenance

Storage occupancy and selective purge use this same private session and are
documented in [the server README](../README.md#operator-storage-occupancy-and-selective-purge).

## Shared maintenance rules

Every route, including `GET /storage-occupancy` and `POST /apply-retention`,
requires the exact `Host: 127.0.0.1:8791` and rejects any `Origin` header.
Run the CLI against the configured loopback address and port.

Selective purge requires at least 30 days of inactivity. Windows starting
before the 2026-11-20 UTC release cutoff, including `1970-01-01`, require
`--include-legacy` at preview and again at apply. The flag allows lists
without a recorded creation timestamp to be considered. The CLI previews
by default and requires `--apply` to retire any reviewed candidates.
Lists with any recovery record that has yet to be retired are excluded.
Each plan shows `storedBytes`, `hasRecovery` (always `false`), and
`pendingInvites` (the count of unexpired invitations awaiting approval).
The list rechecks these fields and recovery eligibility under its lock before
retirement. Generate a fresh preview for plans made before these fields were
added.

The 30-day minimum can retire a family's server-side list when they use one
mobile and open the app only on special dates. Their local data is not deleted,
but that server list is removed and sync ends. Prefer purge windows of 120 days
or more unless storage occupancy is above 50% and a shorter window is needed.

`wrangler dev --remote` may rewrite the `Host` header sent to the maintenance
Worker. If the exact loopback `Host` check then returns 403, document the issue;
do not relax the host control.

## One-time retention sweep

Run **once after deploying the sync Worker with `applyRetention()`**. Nothing
here has been run against production. No application route, cron, new Durable
Object namespace or migration is added. Do not publish a maintenance route.

`wrangler.toml` binds only existing classes in `gift-huddle-sync`.
The sweep's two namespaces are selected with `.jurisdiction("eu")` before `idFromString`;
these are **Durable Object IDs from the API**, not sync IDs/recovery IDs and not
names to pass to `idFromName`. Wrong namespace/jurisdiction IDs are rejected by
the platform. The maintenance HTTP handler belongs only to this separate
unrouted Worker, used through the operator's authenticated remote dev session.
It is not an HTTP method on either Durable Object or on the sync service.

## Effect and limits

- Old undated list retirement markers receive a fixed deadline of wake time +
  400 days. Dated markers keep their deadline, even if the alarm was missing.
  Expired markers are erased; lists are never revived.
- Retired recovery locators are rebuilt with only state and retention deadlines.
  Old undated ones get the same 400 days; dated ones keep their deadline.
- Old revoked writers that still have encrypted secret-gift blocks receive a
  fixed 30-day grace from this wake. Existing graces are never extended.
- Live list alarms use their existing retention deadlines. This call does not
  refresh activity, count requests, alter credentials, change live content or
  versions, or notify clients. It does not drain live lists' release queues.
  A list already expired/malformed follows exactly the usual first-wake
  retirement, including erasure and durable release reconciliation.
- Current objects retain their data and deadlines; empty objects stay empty.
  Repeating any call after a timeout is safe. Normal alarms perform the later
  deletion. New objects created after the inventory already use current rules.

## Maintainer's exact procedure

Use a trusted terminal. Keep the inventory outside this checkout and shared
folders; it contains object identifiers, never credentials or ciphertext. Use a
private directory/Windows ACL (POSIX output mode is 0600). Do not paste tokens
into commands, files, terminal output or tickets.

1. Deploy the reviewed `gift-huddle-sync` version through the normal authorized
   release procedure. Confirm the account and the **existing namespace IDs** for
   `ListV2Object` and `RecoveryLocatorObject` in that script. Do not use a preview,
   v1 or another account's namespace. No maintenance deploy is needed.
2. The maintainer supplies `CLOUDFLARE_API_TOKEN` in the process environment through
   their usual secure mechanism. Listing needs account-scoped Workers Scripts
   read access. From `server/`, run (substitute the three non-secret IDs and a
   private absolute output path):

   ```sh
   node scripts/list-do-objects.mjs ACCOUNT_ID LISTS_NAMESPACE_ID RECOVERIES_NAMESPACE_ID /private/path/retention-objects.json
   ```

   This uses only paginated `GET /accounts/:account/workers/durable_objects/namespaces/:ns/objects`
   with `limit=1000` and `result_info.cursors.after` (also accepts the legacy
   `result_info.cursor`). It includes objects without stored data, deduplicates
   IDs and detects a repeating cursor. There are no automatic retries. Both
   listings must finish before output is created; an existing file is never
   overwritten. On failure, fix API access/network first and choose a new output
   path if a file was partially written by the filesystem. No sweep has started.
3. Review the inventory's account, script, EU jurisdiction, namespace IDs and
   counts. Preserve this file unchanged until the sweep finishes. Enumeration
   is read-only. It is not a transactional snapshot; run in a quiet window.
4. Authenticate Wrangler for the same account using the maintainer's normal secure
   mechanism (a read-only listing token alone cannot create a remote dev
   session). From `server/`, start this separate Worker:

   ```sh
   pnpm exec wrangler dev --config maintenance/wrangler.toml --remote --ip 127.0.0.1 --port 8791
   ```

   No token is a Worker variable or request body. Keep Wrangler's authenticated
   preview/session credentials private. `workers_dev=false`,
   `preview_urls=false`, empty routes and no scheduled trigger prevent a
   published maintenance endpoint. Do not add routes or deploy a dev proxy.
5. In another terminal, from `server/`, invoke the loopback listener:

   ```sh
   node maintenance/run-retention.mjs /private/path/retention-objects.json
   ```

   The entire inventory is validated before the first request. Each request
   contains at most 20 IDs. RPCs run sequentially with 250 ms between groups of
   five; the local invoker waits one second between requests. Counts/offsets
   alone are printed, never IDs or remote exceptions. Other paths/methods,
   non-JSON requests, oversized bodies and invalid batches are rejected. There
   is no CORS handler. The invoker only contacts `127.0.0.1:8791`.
6. If a batch fails, execution stops immediately without automatic retries.
   Fix the problem and reuse the **same unchanged inventory**, passing the
   reported zero-based start offset:

   ```sh
   node maintenance/run-retention.mjs /private/path/retention-objects.json START_OFFSET
   ```

   Offset order is every list ID in inventory order followed by every locator
   ID. If the response was lost, the offset points to the start of the uncertain
   batch, so some calls repeat without extending any deadline. Offset 0 also
   safely repeats the entire sweep. Do not regenerate/reorder the inventory
   when resuming. Record the final `Completed N/N` count in the release record
   (an empty inventory needs no RPC). This records RPC completion, not that all
   30/400-day alarms have already fired.
7. Stop the dev session with Ctrl+C, remove the token from the terminal's
   environment using the maintainer's secure mechanism, and delete the private
   inventory when the completion record has been retained. Leave no background
   dev process. Nothing needs disabling in the production sync Worker.

## Wrangler compatibility and verification

The repository pins **Wrangler 4.159.0**. Its external DO bindings support
`script_name`; native DO RPC is available at compatibility date 2026-10-01.
`test/retention.test.ts` calls the actual maintenance Worker in a separate
workerd isolate with bindings to the application's classes and exercises both
RPCs by enumerated ID. It also tests legacy/no-alarm rows, deadlines,
minimization, idempotence, current/empty objects, batch validation, pauses and
partial failure. Workerd's lack of EU jurisdiction storage is adapted only in
test code; production never falls back to an unrestricted namespace.

This verifies cross-script RPC locally, **not a live Cloudflare remote dev
session**. Plain `wrangler dev --local` does not operate on production objects;
in this pinned version the DO binding schema does not accept `remote=true`.
Do not silently replace `--remote` with local mode or add that flag to bindings.
If Cloudflare rejects external RPC in remote preview, stop. The safest fallback
is an explicitly authorized temporary deployment of this same **unrouted**
maintenance Worker, invoked by a separate operator dev Worker through a private
service binding. External DO RPC then runs in the normal deployed runtime; the
sync service and DOs still gain no HTTP route. That fallback needs separate
review/configuration and has not been deployed or exercised here. Do not fall
back to a public admin endpoint or expose DO storage.

Local checks, always through the shared queue:

```sh
pnpm vitest run test/retention.test.ts
node --test scripts/maintenance.spec.mjs
pnpm typecheck
```
