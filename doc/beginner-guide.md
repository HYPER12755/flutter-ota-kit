# Beginner Guide — From zero to your first OTA

This is the guide Sam wishes existed when they shipped their first Flutter hot
update. It walks through the **exact** things a human does, in order, the first
time they use `flutter_ota_kit` — with every command and code snippet you'll
actually type. By the end you'll have pushed a real over-the-air update to a
device and watched it apply with zero clicks.

---

## 0. Before you start

You'll need:

- A Flutter app (we'll create one called `my_shop`).
- Node/npm installed (for the CLI).
- An Android target — a physical phone **or** an emulator. For an x86_64 emulator
  use `--target-platform android-x64`; for a real ARM phone use `android-arm64`.
- A Supabase project (free tier is fine). From **Project Settings → API** grab:
  - `SUPABASE_URL` (e.g. `https://xxxx.supabase.co`)
  - **anon** key (`sb_publishable_…`)
  - **service_role** key (`sb_secret_…`) — only the CLI needs this, for
    `migrate` / `deploy`.

> Other backends (Postgres, Cloudflare, AWS) work too — swap `supabase` for
> `postgres` / `cloudflare` / `aws` in the commands. Env-var names per backend are
> in [Configuration](configuration.md).

---

## 1. You create a Flutter app

```bash
flutter create my_shop
cd my_shop
```

> Already have an app? Skip this and `cd` into it.

---

## 2. You install the SDK + CLI

```bash
# Flutter package — the OTA runtime your app depends on
flutter pub add flutter_ota_kit

# CLI — builds patches and deploys them to your backend
npm install -g @_nazmiforreal/flutter-ota
flutter-ota --help
```

You now have the `flutter-ota` command. It ships a prebuilt Linux binary and
falls back to compiling its Dart source on other platforms.

---

## 3. You scaffold the project

```bash
flutter-ota init supabase
```

This is the one command that wires everything. It:

1. writes `.flutter_ota_kit/config.json` — the CLI's working state (including the
   service-role key it needs for `migrate`/`deploy`). **Git-ignored.**
2. writes a **`.env`** scaffold at the project root — your app-side secrets.
   **Git-ignored.**
3. ensures `flutter_ota_kit:` is present in `pubspec.yaml` (you already added it in step 2, but `init` keeps it in sync).
4. adds the `INTERNET` permission to
   `android/app/src/main/AndroidManifest.xml`.
5. generates `lib/flutter_ota_kit_setup.dart` — your backend wiring.

Your `.gitignore` now contains `.flutter_ota_kit/` and `.env`, so you'll never
commit secrets by accident.

---

## 4. You put secrets in `.env` (never in code)

Open the generated `.env` and fill in the real values:

```bash
# .env  (git-ignored — safe for secrets)
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_ANON_KEY=sb_publishable_xxxxxxxxxxxxxxxx
SUPABASE_BUCKET=bundles
CHANNEL=production
APP_VERSION=1.0.0
SDK_VERSION=1.0.0
```

Why this works: the generated `lib/flutter_ota_kit_setup.dart` reads these with
`String.fromEnvironment(...)`. **Environment wins** over the config file and over
built-in defaults, so you keep non-secret defaults in code and inject only
secrets at build time:

```bash
# dev
flutter run --dart-define-from-file=.env

# release build for a device / emulator
flutter build apk --release --target-platform android-x64 \
  --dart-define-from-file=.env
```

> The **service-role** key is CLI-only. Export it in your shell (not in `.env`
> you might share) when you run `migrate`/`deploy`:
> ```bash
> export SUPABASE_SERVICE_ROLE_KEY=sb_secret_xxxxxxxx
> ```

---

## 5. You wire `main.dart`

Open `lib/main.dart` and call the generated `setupFlutterOta()` **once**, after
`WidgetsFlutterBinding.ensureInitialized()` and **before** `runApp()`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_ota_kit/flutter_ota_kit.dart';
import 'flutter_ota_kit_setup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupFlutterOta();        // configures Supabase + enables forced auto-restart
  runApp(const MyApp());
}
```

`setupFlutterOta()` does `FlutterPatcher.init(autoApplyUpdates: true)` — that flag
is what makes a forced update download, apply, and **restart the app with no
button press**.

---

## 6. You get dependencies

```bash
flutter pub get
```

---

## 7. You provision the backend

```bash
export SUPABASE_SERVICE_ROLE_KEY=sb_secret_xxxxxxxx   # CLI needs this
flutter-ota migrate supabase
```

For Supabase this is fully automatic: it creates the `bundles` table, the RPCs,
and the public `bundles` storage bucket. (Postgres/Cloudflare/AWS print the SQL
or `wrangler`/AWS commands for you to run manually.)

---

## 8. You build a release APK — your "baseline"

This is what users install from the store. The OTA will patch *on top* of it, so
build it with your secrets:

```bash
flutter build apk --release --target-platform android-x64 \
  --dart-define-from-file=.env

# install it on the emulator / phone
flutter install
# or: adb install build/app/outputs/flutter-apk/app-release.apk
```

Open the app once to confirm it runs. This is version `1.0.0` — your baseline.

---

## 9. You make a change, build a patch, and deploy

Change something visible — say the app bar title or a color in `lib/main.dart`:

```dart
appBar: AppBar(title: const Text('my_shop — now with OTA!')),
```

Now build a **patch** (a diff of your app) and deploy it:

```bash
# 1. Build the APK output the patch is diffed from
flutter build apk --release --target-platform android-x64 --dart-define-from-file=.env

# 2. Pack it into dist/patch.zip (use --name for the new patch version)
flutter-ota build --name 1.0.1 --platform android --arch x86_64

# 3. Push it. --force = zero-click, auto-restart on the client.
flutter-ota deploy -b supabase -s dist -c production -p android \
  --target-app-version 1.0.0 --force -m "first hot fix"
```

What each flag means:

- `--target-app-version 1.0.0` — this bundle applies to baseline `1.0.0`.
- `--force` — the app **must** apply + restart immediately (zero clicks).
  Without it, the bundle is staged and applies on the **next cold start**.
- `--name 1.0.1` — a distinct version. Always bump it; the SDK's loop guard
  skips a bundle whose version already equals the installed one.

---

## 10. You watch it land

Kill the app and open it again (cold start). Because you deployed with `--force`
and `setupFlutterOta()` enabled `autoApplyUpdates`, here's what Sam sees:

1. App boots on `1.0.0`.
2. In the background, the SDK checks for an update.
3. It finds the forced `1.0.1` bundle, downloads + stages it.
4. The app **restarts automatically** — no tap, no dialog.
5. The app bar now reads `my_shop — now with OTA!`.

That's your first OTA. 🎉

---

## The mistakes Sam made (so you don't)

- **Forgot `--dart-define-from-file=.env` at build** → `SUPABASE_URL` is empty →
  "no update" / connection errors. *Always* build/run with it.
- **Ran `migrate` with the anon key** → needs the **service-role** key. Export
  `SUPABASE_SERVICE_ROLE_KEY` first.
- **Deployed without `--force` and expected an instant update** → non-forced
  bundles apply on the next cold start. Use `--force` for critical fixes.
- **Reused `--name 1.0.1` on a second deploy** → the loop guard sees the same
  version and won't re-apply. Bump the version every deploy.
- **Edited Dart but the patch looked unchanged** → `flutter-ota build` diffs the
  current `flutter build apk` output, so always rebuild the APK first.

---

## Where to go next

- [Configuration](configuration.md) — every env var, resolution order, secrets policy
- [CLI Reference](cli-reference.md) — all commands, subcommands, and flags
- [Developer Guide](developer-guide.md) — the full workflow reference
- [Backends](backends.md) — per-backend setup (Postgres / Cloudflare / AWS)
- [API Reference](api-reference.md) — `FlutterPatcher` methods, error codes, asset patching
- [FAQ](faq.md) — versioning, cold start, store policy
