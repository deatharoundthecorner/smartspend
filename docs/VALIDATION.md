# Validation and handoff

Validated on 16 November 2026 using Flutter 3.50.0 stable and Dart 3.14.0 on Linux.
Commands in this cloud environment used `CI=true`, which explicitly disables
Flutter's Azure metadata environment probe. No source changes to Flutter were made.

| Check | Result |
| --- | --- |
| `flutter pub get` | Passed; resolved versions committed in `pubspec.lock` |
| `dart run build_runner build` | Passed after correcting a reserved SQL identifier; generated Drift code committed |
| Drift schema dump and schema helper generation | Passed; version 1 snapshot and test helpers committed |
| `dart format .` | Passed, 27 Dart files; final run required no formatting changes |
| `flutter analyze --no-pub` | Passed, no issues found |
| `TZ=Asia/Colombo flutter test --no-pub --reporter expanded --timeout 30s` | Passed, all 26 tests |
| Targeted November month-boundary test with `TZ=America/New_York` | Passed, 1 test across daylight-saving change |
| `flutter build apk --debug --no-pub` | Attempted, blocked: no Android SDK installed; no APK produced |

The first test run exposed a stream-error mapping bug; it was corrected using an
error-event transformer, and the final suite tests recovery after overflow as well
as mapping the failure. Provider tests use live subscriptions and await asynchronous
updates, matching presentation usage. No failing test was disabled or skipped.

Coverage includes schema initialization and snapshot equivalence, same-version
reopening without reseeding, file persistence, exact money parsing/formatting and
bounds, sums and comparisons, local month boundaries, expense CRUD, literal search,
filters, duplicate submission retries/conflicts, stale edits, category lifecycle,
budget upserts/usage, verified receipt requirements, FKs, outbox transaction rollback,
SQL sum overflow and stream recovery, and Riverpod provider integration.

## Limits

- Version 1 is the first schema. There is no older released schema to migrate;
  no v1-to-v2 upgrade is claimed or implemented. Upgrade tests must be added with v2.
- Tests exercise real SQLite in memory and temporary files on Linux. They do not
  verify Android device installation, native plugin packaging, or UI workflows.
- The Android build is unverified until run on a machine with Android SDK installed.
- The product screens, OCR, attachment creation, cloud authentication, sync worker,
  Drive backups and report export remain future work. No paid service is configured.

## Exact next steps for the team

1. Review the pull request and `API_CONTRACTS.md`; agree on the initial v1 interface.
   Do not merge without team approval.
2. Antigravity should branch from `codex/backend-foundation` into its own frontend
   branch, then replace the bootstrap route and add forms, history, dashboard,
   budgets and report presentation using domain interfaces and public providers.
3. Install the pinned Flutter version and Android SDK locally, then run:

   ```sh
   flutter pub get
   flutter analyze
   flutter test
   flutter build apk --debug
   flutter run
   ```

4. On an Android phone or emulator, verify offline create/edit/delete, app restart
   persistence, category archiving, duplicate Save taps, and local month selection.
5. After frontend integration and Android validation, request team review and merge.
   Plan receipt verification and cloud synchronization as separate tasks afterward.

## Resolved direct dependencies

| Package | Locked version | Purpose |
| --- | --- | --- |
| flutter_riverpod | 3.5.0 | Repository composition and reactive UI data |
| go_router | 18.1.4 | Minimal routing foundation |
| drift / drift_flutter | 2.35.4 / 0.3.1 | Typed SQLite schema, reactive queries and native connection |
| sqlite3 | 3.9.1 | SQLite engine and typed database exceptions |
| uuid | 4.6.0 | Entity IDs and mutation IDs |
| intl | 0.20.3 | English calendar labels; money formatting remains integer-only |
| material_ui | 1.11.0 | Current Flutter Material bootstrap widgets |
| drift_dev / build_runner | 2.35.3 / 2.17.1 | Database and schema test code generation |
| flutter_lints | 6.0.0 | Static quality checks |

`flutter` and `flutter_test` are supplied by the pinned SDK. Transitive versions are
recorded in `pubspec.lock`; no cloud, OCR or charting dependency was added.
