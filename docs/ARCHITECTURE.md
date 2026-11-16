# Architecture and ownership

SmartSpend is an Android-first Flutter application. It stores personal expenses
locally using Drift/SQLite, and needs no server or account for the initial scope.
The application ID is `com.smartspend.app`. Default currency and UI language are
LKR and English. The initial app/router are wiring placeholders, not product UI.

## Boundaries

- `lib/features/*/domain`: immutable models and repository interfaces, no Drift or UI.
- `lib/features/*/data`: database-backed repository implementations.
- `lib/core/database`: schema, migrations, transaction/error helpers.
- `lib/core/formatting` and `lib/core/utils`: exact money and calendar operations.
- `lib/app/providers.dart`: infrastructure composition and reactive public providers.
- `lib/app/app.dart`, `router.dart`, future theme and presentation directories:
  frontend-owned after bootstrap. Antigravity owns navigation, forms, dashboard,
  transaction history, report display and styling.

No database operations belong in widgets. Dashboard and analytics use the shared
monthly analytics interface. No empty feature skeleton or fake financial data is
needed to make a report appear populated.

## Schema v1

| Table | Purpose and integrity |
| --- | --- |
| `expenses` | UUID primary key, unique submission UUID and original draft fingerprint, positive signed 64-bit minor units, LKR-only constraint, category FK, optional verified receipt FK, UTC timestamps and soft-delete tombstone |
| `categories` | UUID, unique normalized name, creation/update/archive dates; restrictive FK deletion preserves history |
| `receipt_attachments` | Reserved for explicitly verified attachment records, local path and verification time; no scanner/upload service |
| `budgets` | UUID, local month key, optional category FK, positive minor units; expression unique index handles overall budgets with null category |
| `app_settings` | Key/value settings; currency seeded to LKR |
| `sync_outbox` | UUID mutation events queued atomically with local writes; entity identity, upsert/delete, attempt count and future retry metadata |
| `report_history` | Reserved local export metadata; no report generator in this task |

Only settings use natural keys. Financial/domain entities and outbox events use
UUIDs. All timestamps are UTC epoch **microseconds**, mapped explicitly to UTC
DateTime. Partial expense indexes cover active date and category/date searches.
Foreign keys are enabled on every open and checked for existing violations.
The database connection is provided by drift_flutter on Android.

Ten requested categories are seeded once during database creation. Category IDs
are generated UUIDs, not stable constants: frontend must load the category list.
Name matching is SQLite's ASCII lower/trim convention, not a multilingual collation.

SQL `SUM`/`COUNT` produce report values from live rows. SQLite integer sum overflow
is reported as validation failure; SQLite `TOTAL` (floating point) is never used.
Money parsing, grouping, checked sums and percentage intermediates use integer or
BigInt arithmetic. Percentages are integer basis points, truncated toward zero.

Expense insert/update/delete and category/budget mutations enqueue an outbox event
within the same transaction. No worker sends these events anywhere. The outbox is
an ordered change notification, not a snapshot of historical versions; a future
worker must load current entities and design account scoping, compaction,
idempotency, retention and conflict rules before synchronization is enabled.
Budget deletion is physical, with an outbox delete event. Expense deletion is soft.

## Migration policy

Version 1 is the first schema: no earlier shipped version exists. Creation and
same-version reopening are tested, including data and seed preservation. The v1
schema snapshot is committed for future upgrade tests. No artificial v0-to-v1
migration or destructive fallback is used. Unsupported upgrades fail explicitly.

Snapshot tooling:

```sh
dart run drift_dev schema dump lib/core/database/app_database.dart drift_schemas/
dart run drift_dev schema generate drift_schemas/ test/generated_migrations/
```

For the next schema change:
1. Export and retain the old schema before editing.
2. Increase `schemaVersion` and implement each forward step in `onUpgrade`.
3. Use Drift migration tooling and fixtures representing old rows and attachments.
4. Test preservation of amounts, IDs, timestamps, FKs, indexes and archived/deleted
   records across every supported starting version, then export the new schema.
5. Review migration and contract changes with the frontend developer before merge.

Never delete the user's database to resolve a schema mismatch. Do not ship a new
version before old-schema migration tests pass.

## Deliberately deferred

Firebase Authentication, Firestore Spark, Google Drive receipt backup, synchronization
workers and OCR are not integrated. No Firebase packages, Blaze configuration,
Cloud Storage, paid APIs, subscriptions or billing setup are present. Receipt scan
results remain an unverified transient domain model until a future verification UI
and attachment workflow are reviewed. Report export/history writing is also future
work. The initial scope does not promise cross-device backup or cloud security.
