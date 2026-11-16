# Web device foundations (batch 1)

These modules do not activate web UI or alter the sync engine. ADR 0003 remains
the protocol authority. All storage writes, PIN changes and acknowledgements
must go through one `VaultService`, under one session Web Lock.

## Public API

Paths below are relative to `app/lib/features/web_device/`.

| Module | Entry points |
| --- | --- |
| `data/vault_crypto.dart` | `VaultHeader.fromJson(Map<String,Object?>)`, `validate()`, `toJson()`; `VaultCrypto.validPin(String)`, `deriveA(String,VaultHeader) -> Future<SecretKey>`, `derive(String,VaultHeader) -> Future<VaultDerivation>`, `key(VaultDerivation,List<int>) -> Future<SecretKey>`, `seal(Object?,SecretKey,VaultHeader,String kind,[String id]) -> Future<Map<String,Object?>>`, `open(Map<String,Object?>,SecretKey,VaultHeader,String kind,[String id]) -> Future<Object?>` |
| `data/vault_store.dart` | `openVaultStore({String name}) -> Future<VaultStore>`, `requestVaultPersistence() -> Future<bool>`; `VaultStore.read() -> Future<VaultState>`, `transaction(VaultState Function(VaultState)) -> Future<void>`, `writePending(VaultSet)`, `promotePending()`, `deletePending()`, `clear()`; `MemoryVaultStore` for VM tests |
| `data/guard_client.dart` | `GuardClient({Uri base, GuardHttp send})`; `prepare(VaultHeader,List<int> credential,{String tokenHash,String verifier,List<int> b})`, `commit(VaultHeader,List<int>)`, `cancel(VaultHeader,List<int>)`, `resume(VaultHeader,List<int> mobileCredential) -> Future<void>`; `open(VaultHeader,List<GuardProof>) -> Future<GuardOpened>` |
| `application/vault_service.dart` | `VaultService({VaultStore store,GuardClient guard,VaultCrypto? crypto,Future<bool> Function() persist,Future<void> Function(OpenVault)? revokeSelf})`; `enroll({String pin,String syncId,String deviceId,VaultJson data}) -> Future<void>`, `unlock(String) -> Future<OpenVault>`, `changePin(String)`, `saveData(VaultJson)`, `forget({bool localOnly=false}) -> Future<void>`, `lock() -> void`, `serial<T>(Future<T> Function()) -> Future<T>`; `opened`, `status`, `persistenceGranted` |
| `application/pending_queue.dart` | `PendingQueue(VaultService)`; `add(FamilyDoc delta) -> Future<String>`, `entries() -> Future<List<PendingEntry>>`, `ack(String id,{Object confirmation}) -> Future<void>`, `setAside(String id) -> Future<void>`, `blockedPeople({Set<String> remember}) -> Future<Set<String>>` |
| `application/web_session_controller.dart` | `WebSessionController` receives platform, clock, cover/cancel/lock/dispose/create hooks and `Future<void> Function(String) unlockVault`; `unlock(String,{bool useHere=false}) -> Future<void>`, `activity()`, `lock({WebSessionState next})`, `disconnect()`, `accept(int generation) -> bool`, `guardCallback<T>(void Function(T)) -> void Function(T)`, `dispose() -> Future<void>` |
| `application/web_session_platform.dart` | `createSessionPlatform({String name}) -> SessionPlatform`; `SessionPlatform.hidden`, `lifecycle`, `takeoverRequests`, `acquire({bool wait}) -> Future<SessionLease?>`, `requestTakeover()`, `dispose()`; `SessionLease.release() -> Future<void>` |
| `data/web_device_keys_store.dart` | `WebDeviceKeysStore(VaultService) extends DeviceKeysStore`; `read()` reads seeds from opened vault; all writes and all surprise-key operations throw |

`GuardHttp` has the same named `body` and `headers` arguments as
`WebSyncTransport.send`. Pass `(method, uri, {body, headers = const {}}) =>
transport.send(method, uri, body: body, headers: headers)`. That transport's Fetch
uses `credentials: omit`, no redirects and cancellation via `close()`. `open`
never supplies an Authorization header. Errors are typed `GuardException` with
`failure`, optional `left`, and optional `retryAfter`. `disconnected` includes
401, 410 and 404 on open; 403 wrong PIN and 423 never delete storage.

`VaultJson data` contains `credential` (unpadded base64url), `deviceKeys`
(`DeviceKeys.toJson()`), `familyKey`, pinned public `roots` and remote `snapshot`.
The latter three are owned by batch 4. Never pass a locally merged document,
surprise keys, or KDF/guard secrets into data. Queue entries and blocked marks
are encrypted separately. AAD fields are `format`, `syncId`, `deviceId`,
`guardVersion`, `kind`, and `id` (empty for vault/marks; opaque id for queue).
The canonical encoding is imported from `core/sync/device_keys.dart`, where it
actually lives in this revision; no core files were modified.

`VaultSet` holds the clear header, encrypted box, encrypted entries and encrypted
marks. `VaultState` holds current and pending sets. `transaction` updates the
whole state synchronously inside a single IDB transaction and resolves only on
`oncomplete`. Callers must not perform asynchronous work inside its callback.
Queue acknowledgement stores its confirmation in encrypted marks in the same
transaction that removes the entry. Entries whose action is set aside remain
encrypted and are still returned with `setAside == true`.

For a revoked registry view or socket 4401/4404, call both the controller's
`disconnect()` and `VaultService.disconnect()`; neither deletes ciphertext.
All callbacks from socket/HTTP/crypto must capture the session generation and
use `accept` / `guardCallback` before publishing effects. The session hooks must
cover the UI synchronously, cancel transport/work, invalidate the vault, then
dispose its actual Riverpod ProviderContainer. No existing providers are changed.
The web implementation fails closed if Web Locks/IndexedDB are unavailable.

## Integration dependencies for batches 3–5

- Batch 3 implements `/v2/lists/{syncId}/guards/{deviceId}` prepare/commit/cancel/
  open/resume in the Worker and self-revocation that also deletes the guard.
  `test/web_device/fake_guard_server.dart` is the serialized reference state
  machine, including uniform 404, cooldown, suspended state, role checks,
  idempotent commit/cancel and conflicting prepare. Its test clock is injectable.
- Batch 4 supplies coherent remote snapshots and authenticated pinned roots,
  one delta per user action (including indirect writes), the publication rule,
  and the candidate. It must await `blockedPeople(remember: ...)` before PUT,
  exclude set-aside entries, persist a real server confirmation through `ack`,
  and use `saveData` for remote snapshot/roots. WebSocket reconnect/backoff stays
  with the existing sync controller; `socketV2` has the existing V2Socket type
  and maps 4401/4404 exactly like native.
- Batch 5 creates the session ProviderContainer, overrides
  `deviceKeysStoreProvider` with `WebDeviceKeysStore`, connects lifecycle and
  content covering, displays persistence denial, PIN errors/retry timing,
  suspension/disconnection, other-tab state and retained set-aside changes.
  `forget(localOnly: true)` explicitly erases a locked computer without remote
  revocation; normal forget awaits the injected revocation hook. Disconnected
  computers can erase retained ciphertext without an open identity.

No service logs secrets. The fixed public interoperability vector is in
`0003-vector-caja.json`: its primary ASCII vector is generated independently
with Node crypto PBKDF2/HKDF/AES-GCM; `nfc` preserves the decomposed-accent PIN
and its expected A from the original Python vector. Web uses the browser's
`String.prototype.normalize('NFC')` through conditional JS interop. The VM
explicitly rejects any non-ASCII PIN, including already composed Unicode.
The browser probe checks the `nfc` derivation against A; VM tests verify the
full ASCII vector. State-machine interruption tests use a fast derivation.

The minimal `VaultStorageTransaction` boundary is shared by the IndexedDB
adapter and VM fault tests. Successful put requests never complete the public
future; only transaction completion reports durability, and abort rejects it.
Browser adapter tests inject LockManager and WebSocket doubles into the real
JS interop adapters, including forbidden lock options and listener cleanup.
`forget` checks its generation after revocation, inside the deleting
transaction and before changing state, and rejects if the stored identity
changed. Hidden-tab deadlines also cover unlocking and queued lock acquisition.

Release build, real browser/Worker integration and the required independent
security review belong to the maintainer's verification before merge.

## Verification in this worktree

From `app/`, through the project's test runner:

- `flutter analyze --no-pub lib/features/web_device lib/features/sync/data/web_sync_transport.dart lib/web_probe/main_probe.dart test/web_device`
  — `No issues found!`.
- `flutter test --no-pub test/web_device/vault_crypto_test.dart test/web_device/vault_service_test.dart test/web_device/guard_client_test.dart test/web_device/web_session_controller_test.dart test/web_device/vault_transaction_test.dart test/web_device/device_keys_mobile_regression_test.dart`
  — `00:02 +52: All tests passed!`.
- `flutter test --no-pub --platform chrome test/web_device/browser_adapters_test.dart`
  — `00:00 +8: All tests passed!` (see the Windows harness workaround below).
- `git diff --check` — clean. No dependency or lockfile changes.

Runs set process-local `FLUTTER_SUPPRESS_ANALYTICS=true` and
`DASH__SUPPRESS_ANALYTICS=true`, including Dart native-asset subprocesses.
Flutter 3.47.7's Windows web test harness converts URI paths to backslashes:
the CanvasKit handler returns 404 and the wrapper's test selector does not
match the generated map. The first browser run stalled at loading; after
bootstrap recovery it exposed two mistakes in the test doubles (an absent
optional boolean and a JS function treated as a matcher), now corrected.
The successful Chrome run used CDP on the runner's disposable browser to serve
CanvasKit directly from the local SDK cache and replace the selector with its
POSIX path in the transient HTML wrapper. No compiled test/application code
or SDK files were changed; no external downloads were used. The runner closed
its Chrome instances (main PIDs 79700 and 88364), and the inline CDP helpers
exited. No helper scripts were left in the worktree. No release build was run,
as instructed; no emulator or persistent service was started.
