# Contributing to Gift Huddle

English · [Español](CONTRIBUTING.es.md)

Describe the problem, expected behaviour and verification in your pull request.
Keep changes focused and use invented data (Aritz, Nora and Leo).
Report security issues using [SECURITY.md](SECURITY.md).

## Build and test

Use Flutter 3.47.7, with an Android SDK or macOS and Xcode for iOS.

```sh
cd app && flutter pub get && flutter gen-l10n && dart run build_runner build -d && flutter test
```

Run `flutter analyze` from `app/` as well. Release signing reads a local
`key.properties` file that is not in the repository; use debug builds locally.

The Cloudflare Worker needs Node.js 22 and pnpm 10:

```sh
cd server && pnpm install && pnpm test
```

## Project rules

- No accounts and no analytics. Do not introduce tracking or personal data.
- UI text belongs in ARB files: Spanish is the source, with Catalan and English
  translations (`app/lib/l10n/`).
- Sync merges each field independently using logical clocks; deletions are
  tombstones. Model changes must include tests in `app/test/sync`.
- `app/` contains Flutter, `server/` the Worker and `docs/adr/` design decisions.
- Keep keys and release credentials out of pull requests.
- Commit under whatever name and address you like, but not with a Gmail
  or Googlemail address (CI rejects them in commits, tags and files); the
  maintainer's commits must use `dev@mainshai.com`.

By submitting a pull request, you agree to license your contribution under
GPL-3.0-or-later, as described in [LICENSE](LICENSE).
