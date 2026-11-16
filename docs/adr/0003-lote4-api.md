# Web engine and pairing integration (batch 4)

ADR 0003 is authoritative. This batch activates the existing web gate without
adding screens or ARB text. Mobile storage/sync defaults remain unchanged;
`sync_controller.dart`, sharing/device screens, the Worker and core registry
were not modified.

## Transport and mobile host

Paths are relative to `app/lib/`.

| API | Contract |
| --- | --- |
| `SyncV2Transport.putCommon(V2Auth, {required int version, required Uint8List common})` | Exactly `{common}`, strong global `If-Match`; validates the returned version. No registry, packages or slots. |
| `createInvite(V2Auth, Map offer, {String? inviteId, String? guestPerson})` | Web reserves its QR id and the mobile's selected person. Existing mobile callers retain their defaults. |
| `getOffer(String inviteId, {bool allowNotYet = false})` | Returns `V2InviteOffer.guestPerson`. With `allowNotYet`, a pre-offer 404 throws `V2OfferNotYetException`; otherwise it throws `InviteGoneException`. |
| `approveInvite(..., {required int version, required Map package, String role = 'device'})` | Web host uses `role: 'web'`. The signed v3 approval and its `minVersion` are verified by both guest types. |
| `V2Device.role` | `device` for old rows without a role; unknown roles are protocol failures. |
| `WebPairingQr.parse(String, {String origin = kWebPairingOrigin})` | Accepts only HTTPS at that exact origin, `/w`, no query/userinfo, two canonical 16-byte base64url fields. |
| `PairingV2Host.start(..., {WebPairingQr? web, String? guestPerson})` | Binds `expectWeb`, id, person and fingerprint before receiving the answer; approves with the appropriate role. |
| `pairingV2HostProvider.notifier.startWeb(String qr, {required String guestPerson, String origin = kWebPairingOrigin})` | Call **after choosing a live person**. The existing migration-consent step still applies. |
| `PairingV2HostState.needsNewWebQr` | `invite_exists`: request another QR in the browser; do not retry the reserved id. |
| `pairingV2HostProvider.notifier.resumeWebUnlock(String deviceId, {GuardClient? guard})` | Mobile credential, same-list web record, `POST G/resume`. Uses the configured transport by default; injectable guard for tests. |

`forbidden_role` remains `V2ForbiddenException(code)`, `invite_exists` is
`V2InviteConflictException(code)`, and `role_mismatch`/`person_mismatch` are
`V2PairingMismatchException(code)`. These are distinct from network retry and
revoked-credential failures.

## Browser engine, candidate and storage

`features/web_device/application/web_sync_engine.dart`:

- `WebSyncEngine({transport, vault, queue, onChanged, onDisconnected, onError})`.
- `sync()`, `start()` (socket plus catch-up), `requestSync()` (retry/backoff),
  `stop()` (invalidates awaited callbacks and cancels timers/socket).
- `candidate`, `view`, `version`, `status: WebSyncStatus`, `hasRoots`,
  `setAsideCount`.
- `save(FamilyDoc before, FamilyDoc after)`: one durable user-action delta;
  `webDelta` preserves only changed fields with their HLCs. `giftPeople`
  remembers the original/proposed recipients even after a remote move/delete.
- `webEntryAllowed(snapshotOrCandidate, PendingEntry, blockedPeople)` is the
  single publication predicate. It checks original, proposed and merged gift
  recipients and excludes the entire action. It runs on enqueue, coherent
  snapshots, before PUT and after 412 reconstruction. Policy records of any
  value, tombstones, manifest slots and historical encrypted marks all block.

The only publishing route is `putCommon`. There are no slot reads/decryption,
registry writes, package writes or pruning. A coherent GET is verified from
pinned mobile roots; a revoked root is replaced only by another pinned mobile
still active in that view. The next roots are active mobiles from the selected
view. Authenticated local registry history/conflict memory is kept with the
remote snapshot; network JSON is never loaded as authenticated local state.
Valid `family` packages addressed to this web can update its family key.

`VaultService.saveData` stores encrypted remote envelopes/manifests and roots,
never a candidate containing queued changes. Blocked marks are durable before
publication. Successful PUT plus a subsequent coherent GET at or above the
accepted version precede encrypted queue acknowledgement. Unconfirmed/no-root
webs cannot publish. Registry revocation, 401/410/404-list and socket
4401/4404 disconnect without erasing ciphertext.

`features/web_device/data/web_family_store.dart` adapts the existing
`FamilyController`. `saveDoc` creates one action, indirect writes included;
`savedDoc` returns the candidate rather than an excluded proposal. Ordinary
files/secrets are denied. `latestStoredStamp` also includes set-aside queue
actions, so reopening does not reset their HLC history. The small native-store
hooks are no-ops/defaults on mobile. `reloadStoredCandidate()` updates UI in
the controller's edit queue without generating another action or losing undo
visibility.

`WebOperationException(operation)` rejects family replacement/leaving,
imports, key export/copies, invitations, mobile management and choosing a
different person's identity. `WebSyncController` overrides the existing
controller provider; it never starts the mobile engine.

## Guest, gate and application startup

`WebPairingGuest.create({transport, now?, random?})` generates fresh keys and
QR data in memory. `poll()` distinguishes pre-offer 404, verifies the offer,
answers as `web` with `guestPerson`, verifies reveal/code and signed approval.
`pollDelay` is random 5–8 seconds. The gate honors Retry-After as a lower bound
and stops after ten minutes; after approval the user can take time to choose
a PIN. `confirmCode()` is mandatory. `personName` becomes available only after
decrypting common. `enroll(VaultService, String pin)` stores the credential,
DeviceKeys seeds, family key, host anchor, remote snapshot and person.

`WebGateController` implements `WebGateActions`, exposes `view`, `session`,
`engine`, `guest`, `persistenceDenied`, and adds `confirmCode()`, `rejectCode()`,
`checkPairing()` and `close()`. It publishes new `WebGateUnlock` instances for
each PIN failure/rate limit, and suspension, other-tab, disconnect, cover and
open states. Enrollment, unlock, changes/acks/PIN rotation and erasure all use
the session's exclusive Web Lock. Reconnect first requests the existing erase
confirmation: retained ciphertext is erased only by `eraseComputer()`.

The existing `WebGate` accepts optional `onConfirmCode`/`onRejectCode`
callbacks, reusing the existing localized match/no-match labels. The
disconnected view has `confirmErase` to reuse its existing confirmation pane.
No new screen or translation is introduced.

Web `main` mounts `WebBootstrap` before creating mobile providers. It clears
the `/w` fragment before routing. On unlock it creates the actual session
`ProviderContainer`, overrides `DeviceKeysStore` with `WebDeviceKeysStore`,
uses `WebFamilyStore`/`WebSyncController`, and disables the normal transports.
The app root's `webSession` option delegates covering/lock to the outer gate.
Locking disposes this actual container and closes its transport; another
unlock creates a new one. All plaintext family providers live in that session.

`features/web_device/application/web_device_providers.dart` supplies:

- `webGateActionsProvider`: settings actions, including change PIN/lock/forget.
- `webSyncEngineProvider`: the active restricted engine.
- `webDeviceStateProvider`: reactive `status`, `hasRoots`, `setAsideChanges`
  and `persistenceDenied` for notices.

Build-time `WEB_APP_ORIGIN` overrides the QR origin; default is
`https://web.gifthuddle.app`. The sync origin keeps `SYNC_API_ORIGIN`.

## Batch 5b UI work

- Mobile: entry/screen for “Connect the web”, choose person before `startWeb`,
  request a fresh browser QR on `needsNewWebQr`, compare/confirm, web rows and
  `resumeWebUnlock` action in each web's sheet.
- Web: mount existing `WebSettingsSection` with `webGateActionsProvider` and
  persistence state; hide share/backup/recovery/invite/mobile management,
  protection controls and changing “Me” to another record.
- Show set-aside action counts and pending confirmation. With roots, ask a
  mobile to re-vouch; without roots, in-person re-pairing is needed. Retained
  actions never move automatically to another identity/generation.
- Existing gate panes already receive the real actions and states. Desktop
  browser/real mobile end-to-end validation, browser matrix and independent
  security review remain maintainer verification before release/merge.

## Files and verification

New application modules: `web_sync_engine.dart`, `web_pairing_guest.dart`,
`web_gate_controller.dart`, `web_sync_controller.dart`,
`web_device_providers.dart`, and `data/web_family_store.dart` under
`features/web_device/`. Integration files: `main.dart`, `app/app.dart`,
`app/web_bootstrap.dart` and the three `app/web_location*.dart` adapters.
Existing files changed: family controller/store, v2 pairing flow/controller,
v2 transport, pending queue, web session controller and the existing gate/model.
Documentation: this contract and `CHANGELOG.md`.

Tests added: `test/sync/transport_web_v2_test.dart`,
`test/web_device/web_sync_engine_test.dart`, `web_pairing_test.dart`,
`web_gate_controller_test.dart`, plus `web_engine_support.dart`.
`test/helpers/fake_worker_v2.dart` now models common-only writes, roles,
global invitation reservations/person binding and the existing fake guard.

All commands ran from `app/` through the project's test runner, with
analytics disabled in the child processes. No network or new dependency was
needed; the initially absent package configuration was restored with
`flutter pub get --offline`. The first analysis attempt hit a telemetry-file
sandbox error; suppressing analytics resolved it. Subsequent compile/lint/test
failures found during implementation were corrected before the final checks.

- Targeted mobile family/storage/delete/self-person tests plus the new
  engine/gate tests: `00:04 +83: All tests passed!`.
- Final combined run, **once**:
  `flutter test --no-pub test/sync test/web_device`:
  **`00:38 +852: All tests passed!`**. This includes existing mobile pairing,
  registry, engine, view and storage regression tests; browser-only tests
  are outside this VM run.
- Focused `flutter analyze --no-pub` on the changed production modules and
  helper/new test files: **`No issues found! (ran in 10.5s)`**.
- `git diff --check`: clean. No dependency/lockfile changes, commits, services,
  emulators or background helpers; no persistent process/PID left running.

No release build, real desktop browser/Worker round trip or independent
security review was performed in this batch. These remain the maintainer's
verification; this worktree has no deployment or external-service changes.
