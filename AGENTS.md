# Contributor and agent guide

Gift Huddle is GPL-3.0-or-later; see LICENSE and CONTRIBUTING.md.

- `app/`: Flutter 3.47.7 application and tests.
- `server/`: Cloudflare Worker and TypeScript tests.
- `docs/adr/`: architecture decisions, including the sync model.

```sh
cd app && flutter pub get && flutter gen-l10n && dart run build_runner build -d && flutter analyze && flutter test
cd server && pnpm install && pnpm test
```

Keep changes focused. Use invented data (Aritz, Nora, Leo), never family data
or credentials. No accounts, no analytics. UI strings go through ARB: Spanish
source, Catalan and English translations. Sync merges per field with logical
clocks and tombstones; model changes need tests in `app/test/sync`.

Maintainer commits (name `Daniel Mont Ferrandiz` or an address containing
`dferrandizmont`) must use `dev@mainshai.com`; GitHub may use
`noreply@github.com` as committer. Other contributors keep their own identity,
but no Gmail addresses in commits, tags or files. Maintainers enable the local
hooks with `git config core.hooksPath .githooks`; CI checks history and
annotated tag chains. Contributions are submitted as pull requests under
GPL-3.0-or-later. Do not push, publish or deploy without the owner's instruction.
