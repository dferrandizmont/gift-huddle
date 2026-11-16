# Browser probe (ADR 0003, batch 0)

Run commands below from `app/`. No new dependencies are needed. In a sandbox,
set `FLUTTER_SUPPRESS_ANALYTICS=true` for Flutter; use `dart --suppress-analytics`
for formatting. Resolve packages with `flutter pub get --offline`
if this is a fresh worktree. `--no-pub` below keeps validation offline.

```sh
flutter analyze --no-pub lib/web_probe/main_probe.dart
flutter build web --release --no-pub --no-web-resources-cdn --pwa-strategy=none -t lib/web_probe/main_probe.dart -o build/web_probe
flutter build web --release --no-pub --no-web-resources-cdn --pwa-strategy=none
flutter build web --release --no-pub --no-web-resources-cdn --pwa-strategy=none --wasm -t lib/web_probe/main_probe.dart -o build/web_probe_wasm
flutter build web --release --no-pub --no-web-resources-cdn --pwa-strategy=none --wasm -o build/web_wasm
```

The server resolves `--dir` relative to `app/`, regardless of the current directory.
From the repository root:

```sh
node app/tool/serve_web.mjs
node app/tool/serve_web.mjs --dir build/web_probe
node app/tool/serve_web.mjs --dir build/web_probe_wasm
curl -sI http://localhost:8790/w
```

Run only one server on port 8790 at a time. Its startup line prints its PID;
stop that PID after checking. It binds to loopback. It serves existing files
first, then, like Pages without `_redirects` or `404.html`, falls back to `index.html`, and applies matching `_headers`
rules to the requested path. It supports exact paths and `*` patterns, not the
full Pages routing language. All current assets are unversioned filenames,
so the global `no-cache` rule deliberately covers everything.

Open `/w` and `/regalo/x` directly and reload them in Chrome, Edge and Firefox.
Confirm in Network that the bootstrap, main entrypoint, CanvasKit/Skwasm and
font/assets requests start at `/`, with no CDN requests and no service worker.
Use a fresh browser profile or clear a service worker installed by an earlier
build. Inspect Console for CSP and Trusted Types report-only violations too;
HTTP/build checks alone cannot establish browser CSP compatibility.

The external bootstrap sets `entrypointBaseUrl`, `assetBase`, `canvasKitBaseUrl`
and `fontFallbackBaseUrl` explicitly. There is no `<base>` and the enforced CSP
is copied verbatim from ADR §9. Trusted Types is report-only. CanvasKit/Skwasm
unconditionally request a Roboto default unless the font manifest declares it:
`pubspec.yaml` aliases the existing local Inter face under that family name.
Other missing-glyph fallback requests stay on the same origin; this probe
does not bundle Google's entire fallback font catalogue.

Each probe line is mirrored to `console.log` with `PROBE `. No generated key
bytes are logged. Timings include extraction/conversion where applicable;
PBKDF2's native import occurs before its timer, while the package timer includes
its key import. Backend labels use type checks so release minification cannot
obscure whether cryptography selected pure Dart or WebCrypto. These are
diagnostic measurements, not a rigorous microbenchmark.

- IndexedDB writes and reads wait for transaction `oncomplete`, compare all
  65536 bytes and delete their unique disposable database.
- Persistence denial is printed as `FAIL ... granted=false`; it can be a normal
  browser policy decision. Estimate runs independently even after a denial.
- In two tabs, exactly one should report `acquired=true` for the session lock.
  The other reports `acquired=false` (successful contention test). Send hello
  to see hello/ack received on both pages. A channel does not echo to its sender.
- PBKDF2 compares outputs at all three iteration counts. AES-GCM decrypts in
  both directions using fresh nonces and AAD. HKDF compares explicit/empty salt.
  X25519 agrees both ways; Ed25519 rejects an altered message.
- Hide/show a tab, navigate away and Back/Forward; record lifecycle timestamps
  and `persisted`. A held Web Lock or open BroadcastChannel can affect BFCache
  eligibility depending on the browser. The probe holds its lock for the page's
  lifetime as requested; it does not implement the future product lock policy.
- Edit accented text in the field and check that Inter is loaded locally.

No browser automation is part of this batch. Browser results and iteration
selection must be recorded by the maintainer after running this checklist.

## Validation in this worktree (2026-11-13)

Flutter 3.47.7. The four build commands above completed with exit code 0:

```text
No issues found! (ran in 9.5s)
Built build\web_probe
Built build\web
Built build\web_probe_wasm
Built build\web_wasm
```

Raw sizes on disk, including all bundled engine variants (not compressed):

| Output | Total bytes | main.dart.js | canvaskit/ | main.dart.wasm | main.dart.mjs |
| --- | ---: | ---: | ---: | ---: | ---: |
| build/web | 45,429,089 | 4,430,578 | 37,851,412 | — | — |
| build/web_wasm | 49,623,640 | 4,430,578 | 37,851,412 | 4,158,927 | 35,506 |
| build/web_probe | 43,425,765 | 2,431,438 | 37,851,412 | — | — |
| build/web_probe_wasm | 45,500,609 | 2,431,438 | 37,851,412 | 2,040,748 | 33,978 |

Wasm adds 4,194,551 bytes for the app and 2,074,844 for the probe. The generated
build configuration selects Dart Wasm/Skwasm when supported and retains the
Dart2JS/CanvasKit fallback. All builds copy `_headers`; there is no `_redirects` (Pages already falls back to `index.html` for an SPA without `404.html`, and `/* /index.html 200` can be flagged as a loop).

Both the default server and `--dir build/web_probe` were started and checked
with `curl -sI http://localhost:8790/w`: 200, the exact ADR CSP, Trusted Types
report-only and all other configured headers, including `Cache-Control: no-cache`.
`/regalo/x` returned the same SPA HTML; root bootstrap, main JS, CanvasKit JS/Wasm,
font manifest, bundled Inter and version JSON returned 200 with appropriate MIME
types. `/_headers` returned 404. Servers were stopped by their own PIDs:
76644 (probe), 1204 (app). No server was left running.

Notes and limits:

- The requested options exist. `--pwa-strategy=none` is deprecated but works;
  Flutter emits an empty `flutter_service_worker.js` (0 bytes), and the bootstrap
  does not register it. No replacement flag was necessary.
- All four builds warn about a referenced CupertinoIcons family missing from
  the font manifest. The probe and real app both produce this warning. No
  dependency was added to hide it; the focused analyzer is clean.
- The first formatting/analyzer attempts hit a sandbox denial writing Dart's
  telemetry session outside the worktree. Suppressing telemetry fixed it.
  The initial analyzer also invoked automatic pub resolution; subsequent
  preparation used `pub get --offline`, and all final checks used `--no-pub`.
  No `pubspec.lock` change remains.
- No browser was opened: runtime crypto timings, persistence policy, CSP
  execution, local font rendering, multi-tab behavior and BFCache are unverified.
- `git diff --check` passed and all four output directories are ignored.

## Guard: no `unreachable` in the app's wasm (1.0.2)

> The guard is a heuristic aid, not a proof: a simple WAT parser and a count per
> function against a reviewed baseline. The real check stays the Chromium -O4
> probe below and a manual pairing (QR, code, approval, PIN, first sync).

dart2wasm (Flutter 3.47) can compile a `cryptography` call whose dynamic
selector it thinks has no target (`Pbkdf2`, `Hkdf` and `Argon2id` share
`deriveKey`) as `unreachable`: the web 1.0.1 froze when opening the family key
and when saving the PIN. The app no longer calls those (`lib/core/sync/hkdf.dart`,
`lib/features/web_device/data/vault_pbkdf2_web.dart`). Before every web
release, from `app/`:

```sh
sh tool/check_wasm_unreachable.sh            # builds build/web_check and checks it
node tool/check_wasm_unreachable.mjs <main.wat> --all   # every function, for a look
```

It builds like production plus `--no-strip-wasm`, dumps the module with the
SDK's `wasm-opt --print` and checks it without control-flow guesses:

1. It parses the whole dump (balanced parentheses to the end) and requires as
   many parsed functions as `(func` headers, and at least one app function.
2. In every app function it counts each `(unreachable)` that is not right
   after `throw`, `rethrow`, `br`, `br_table`, `return…` or `unreachable`, or
   a call to a reviewed `Never` function (checked to return nothing).
3. It compares those counts with `tool/wasm_unreachable_baseline.json`: a new
   function or a higher count fails. Each entry has a reason. Kinds reviewed
   once (`kind-reviewed:`): after a `try`/`loop`/`block`/`if` whose paths all
   return, branch or throw, the last `br_if` of an exhaustive `switch`, the
   first instruction of a block nothing falls into, a widget build the web
   never creates. Anything else (a plain call, a `drop`, the first
   instruction of a function) gets `REVIEW` and fails until someone writes
   why it is safe, as for `_RevealLayer.build`, the dynamic `toJson` stub and
   `_CapsuleOutput.writeBytes`.

When a legitimate change moves the counts, regenerate and review the diff:
`node tool/check_wasm_unreachable.mjs <main.wat> --write-baseline` keeps the
existing reasons and marks new entries `REVIEW`. With the old `Pbkdf2` call
in `VaultCrypto` the guard fails (`VaultCrypto.deriveA`, `_pbkdf2`); with
HEAD it passes.

The pairing probe runs the real flow in Chromium at -O4 (offer, answer, code,
approval, `finish()`, the PIN vault with the real 600,000-round PBKDF2 and its
fixed vector, unlock, a wrong PIN and the first sync):

```sh
flutter build web --release --wasm --no-web-resources-cdn --pwa-strategy=none \
  --no-strip-wasm -t test/wasm/web_pairing_probe.dart -o build/wasm_probe
node tool/serve_web.mjs --dir build/wasm_probe   # open it; read the console
```

The console prints `PROBE <scenario> OK|FAIL` and `PROBE DONE ok=N fail=M`. The
pure-Dart part also runs in Node 24: `dart compile wasm -O4
test/wasm/web_pairing_probe.dart -o build/p/probe.wasm && node
test/wasm/run_probe.mjs build/p` (Node's WebCrypto runs the PIN vault too).
