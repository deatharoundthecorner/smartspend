# SmartSpend

smartspend app

Offline Android personal expense tracking. English UI, LKR currency, and no paid
services. This branch supplies the backend foundation; the initial screen is only
a bootstrap placeholder for the frontend developer.

## Toolchain and setup

Use Flutter **3.50.0 stable** / Dart **3.14.0**, Android Studio with Android SDK, and
Java supported by the generated Android Gradle plugin. Install SDK components and
accept licenses via `flutter doctor --android-licenses`. Run `flutter doctor` to
check your local setup.

```sh
git clone https://github.com/deatharoundthecorner/smartspend.git
cd smartspend
git switch codex/backend-foundation
flutter pub get
dart run build_runner build
dart format .
flutter analyze
flutter test
flutter build apk --debug
flutter run
```

The Android application ID is `com.smartspend.app`. The debug APK is generated at
`build/app/outputs/flutter-apk/app-debug.apk`. No API keys or cloud accounts are
needed. Do not commit personal databases, receipts, signing keys or credentials.
Commit `pubspec.lock` and generated Drift source so everyone builds the same app.
Regenerate Drift code after changing schema files.

## Frontend integration

Read [API_CONTRACTS.md](API_CONTRACTS.md) for exact model fields, provider names,
repository methods, examples and loading/error/success behavior. Architecture and
schema decisions are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
Validation evidence is recorded in [docs/VALIDATION.md](docs/VALIDATION.md).

Antigravity owns presentation, navigation, themes and product screens. Use public
repository providers and domain models; never query Drift from a widget. Normalize
month arguments using `DateTime(year, month)` and preserve submission UUIDs on save
retries. Money is integer minor units; `parseLkr('1,250.00')` returns `125000`.

## Collaboration

Backend work stays on `codex/backend-foundation`, reviewed through a PR to `main`.
Do not force-push or merge without team approval. The frontend developer should
review the v1 contracts and branch from this foundation if starting integration
before merge. Keep frontend commits on a separate branch such as
`antigravity/frontend`. Only the backend owner manages initial pubspec changes.
Coordinate any shared model/signature changes in the PR before implementing them.

Dependencies include Riverpod, GoRouter, Drift/SQLite, UUID and Intl. The bootstrap
uses the current Flutter Material package (`material_ui`) to avoid deprecated
Material imports. FL Chart is
not added because no shared logic needs it; the frontend can request it when chart
presentation is implemented. Cloud sync and receipt scanning are intentionally
future work. No billing configuration is included.
