# Beginner Guide — Zero to your first OTA

This is the guide Sam wishes existed when they shipped their first Flutter
hot update. It walks through the **exact** things a human does, in order,
the first time they use `flutter_ota_kit` — every command you type, every
file you touch, every mistake you're likely to make.

By the end you'll have pushed a real over-the-air update to a device and
watched it apply with zero clicks.

**Audience:** first-time user. You should be comfortable with `flutter
build`, `adb install`, and reading Dart code. You do **not** need to know
anything about native Android, code signing beyond MD5, or backend
infrastructure.

**Time:** 30 minutes if everything works. 60–90 minutes if you hit
troubleshooting (most users hit the `.env` issue once, see step 4).

---

## 0. Before you start

You need five things in front of you:

| What                                  | Why                                                                          |
|---------------------------------------|------------------------------------------------------------------------------|
| A Flutter app                         | We'll wire OTA into it. (This guide uses `my_shop`.)                        |
| Flutter 3.47+ installed               | `flutter --version` should report 3.47.0 or newer.                          |
| An Android target                     | A physical phone **or** an emulator. For x86_64 emulator use `--target-platform android-x64`; for an ARM phone use `android-arm64`. |
| A Supabase project                    | Free tier is enough. From **Project Settings → API** copy:                  |
|                                       | • `SUPABASE_URL` (e.g. `https://xxxx.supabase.co`)                            |
|                                       | • **anon** key (`sb_publishable_…`)                                           |
|                                       | • **service_role** key (`sb_secret_…`) — only the CLI needs this, for `migrate` / `deploy`. |
| 30 minutes                            | This is not a "5-minute quick start" — it's the first time you're doing it. |

> **Other backends work too.** Postgres, Cloudflare, AWS, and PocketBase
> are all first-class. Swap `supabase` for the backend you picked in the
> commands below. The credential/env-var names per backend are in
> [Backends](backends.md).

### Which backend should I pick?

The first time, pick the one that matches your day job:

- **Supabase** if you already use it (or want everything automated — the
  CLI creates the table, RPCs, and storage bucket for you).
- **Postgres** if you have a Postgres database handy. You'll run a few
  SQL files yourself, but it's the most "just a database" option.
- **Cloudflare** if you're on the Workers/R2 stack. D1 + R2, prints
  `wrangler` commands.
- **AWS** if you already have an AWS account. S3 + DynamoDB / RDS.
- **PocketBase** if you want a single-binary self-hosted backend with
  zero cloud account. The CLI ships PocketBase + installs the schema
  for you.

**For the rest of this guide, I'll use Supabase** because it's the most
"just works" option. The exact same steps apply to the others — only
step 7 (provision) and step 9 (deploy) differ.

---

## 1. Create or `cd` into your Flutter app

If you don't have an app yet:

```bash
flutter create my_shop
cd my_shop
```

If you already have one, just `cd` into it. The rest of the guide
assumes you're in the project root (the directory with `pubspec.yaml`).

**Verify:** `ls pubspec.yaml` should print `pubspec.yaml`. If it doesn't,
you're in the wrong directory.

---

## 2. Install the SDK + CLI

```bash
# 1. Flutter package — the OTA runtime your app depends on at run time
flutter pub add flutter_ota_kit

# 2. CLI — builds patches and deploys them to your backend
npm install -g @_nazmiforreal/flutter-ota

# 3. Verify the CLI is reachable
flutter-ota --help
```

The CLI ships a prebuilt Linux/macOS/Windows binary and falls back to
compiling from Dart source on other platforms. The `flutter-ota`
command is the shorthand for it.

**Verify:** `flutter-ota --version` should print a version number, not
`command not found`. If it says "command not found", your `npm bin -g`
isn't on `$PATH`; the install printed the path — add it.

---

## 3. Scaffold the project

This is the **one command that wires everything**:

```bash
flutter-ota init supabase
```

It does five things, in order:

1. **Writes `.flutter_ota_kit/config.json`** — the CLI's working state.
   May contain your service-role key. **Git-ignored.**
2. **Writes `.env`** — your app-side secrets (anon key, URL, channel).
   **Git-ignored.**
3. **Ensures `flutter_ota_kit:` is in `pubspec.yaml`** — if you already
   ran `flutter pub add` in step 2, this is a no-op; otherwise it adds it.
4. **Adds the `INTERNET` permission** to
   `android/app/src/main/AndroidManifest.xml` (Flutter's auto-init
   `ContentProvider` is merged in by the plugin).
5. **Generates `lib/flutter_ota_kit_setup.dart`** — your backend wiring.
   This is the file `main.dart` calls into.

After step 5 your `.gitignore` contains both `.flutter_ota_kit/` and `.env`,
so you'll never commit secrets by accident.

**Verify:** `cat lib/flutter_ota_kit_setup.dart` should print a small
generated file. `cat .env` should print a scaffold with placeholder
values for `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `CHANNEL`, `APP_VERSION`.

---

## 4. Put your real secrets in `.env` (never in code)

Open the generated `.env` and replace the placeholders with your real
Supabase values:

```bash
# .env  (git-ignored — safe for secrets)
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_ANON_KEY=sb_publishable_xxxxxxxxxxxxxxxxxxxxxxxxxxxx
SUPABASE_BUCKET=bundles
CHANNEL=production
APP_VERSION=1.0.0
SDK_VERSION=1.0.0
```

**Why this works:** the generated `lib/flutter_ota_kit_setup.dart` reads
each of these with `String.fromEnvironment(...)`. Build-time env wins over
the project config file and over built-in defaults, so:

- Non-secret defaults (channel, platform) stay in code, easy to commit.
- Secrets (URL, anon key) live in `.env` only — git-ignored.
- Production deploys can override via `--dart-define=KEY=value` without
  touching the file system.

Build/run with the env file:

```bash
# dev (with hot reload)
flutter run --dart-define-from-file=.env

# release APK for device or emulator
flutter build apk --release --target-platform android-x64 \
  --dart-define-from-file=.env
```

> **The service-role key is CLI-only.** Never put it in `.env` you
> might share or commit. Export it in your shell when you run `migrate`
> / `deploy`:
> ```bash
> export SUPABASE_SERVICE_ROLE_KEY=sb_secret_xxxxxxxx
> ```

**Verify:** `cat .env` should now have your real `SUPABASE_URL` and
`sb_publishable_…` key, not the placeholders.

---

## 5. Wire `main.dart`

Open `lib/main.dart` and add two lines: one import, one call. The
generated `setupFlutterOta()` does the heavy lifting.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_ota_kit/flutter_ota_kit.dart';
import 'flutter_ota_kit_setup.dart';   // generated by step 3

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupFlutterOta();        // ← this is the only new line
  runApp(const MyApp());
}
```

What `setupFlutterOta()` does:

1. Calls `FlutterPatcher.configureSupabase(...)` (or whichever backend
   `init` chose) with the values from your `.env` /
   `--dart-define`.
2. Calls `FlutterPatcher.init(autoApplyUpdates: true)` — the
   `autoApplyUpdates: true` flag is what makes a forced update
   download, apply, and **restart the app with no button press**.
3. Wraps your app in `FlutterOtaApp` so the SDK can show a progress
   overlay during a forced install. If you don't want the overlay, set
   `FlutterPatcher.showUpdateUi = false` — the install still works, you
   just don't see the spinner.

**Verify:** `grep -n setupFlutterOta lib/main.dart` should show your
call. If you see a `late` initialization error in the IDE, you've put
the call after `runApp()` — move it before.

---

## 6. `flutter pub get` (to refresh the lockfile)

```bash
flutter pub get
```

You already added the dependency in step 2 — this just resolves the new
transitive deps that `flutter-ota init` may have pulled in.

**Verify:** `flutter pub deps | grep flutter_ota_kit` should print at
least one line, not an empty result.

---

## 7. Provision the backend

This creates the database tables, RPCs, and storage bucket that
flutter_ota_kit expects.

```bash
# The CLI needs your service-role key to create tables / buckets.
# Set it just for this command:
SUPABASE_SERVICE_ROLE_KEY=sb_secret_xxxxxxxx \
  flutter-ota migrate supabase
```

**For Supabase this is fully automatic** — it creates the `bundles`
table, the `get_update_info_*` RPCs, and the public `bundles` storage
bucket. For other backends:

- **Postgres** — prints SQL to run against your database
- **Cloudflare** — prints `wrangler` commands (D1 + R2)
- **AWS** — prints S3 + DynamoDB / RDS commands

**Verify:** `supabase` dashboard should now show a `bundles` table and a
`bundles` storage bucket. Or run `flutter-ota doctor` — if the backend
is reachable, it should print your channel list.

---

## 8. Build a release APK — your "baseline"

This is the version your users install. Everything you ship later
patches **on top of** this, so build it carefully.

```bash
# x86_64 emulator example (use android-arm64 for a real phone)
flutter build apk --release --target-platform android-x64 \
  --dart-define-from-file=.env

# Install on the emulator or phone
flutter install
# or: adb install build/app/outputs/flutter-apk/app-release.apk
```

Open the app once to confirm it runs. The app version shown in
`pubspec.yaml` (e.g. `1.0.0+1`) is your **baseline version** — every
patch you ship later must be explicitly versioned to apply to this
baseline.

**Verify:** the app launches, you can see the home screen. If it
crashes immediately, check the logcat:

```bash
adb logcat | grep -i flutter
```

Most first-time crashes are missing `INTERNET` permission (check
`AndroidManifest.xml` — `init` should have added it) or wrong Supabase
URL.

---

## 9. Make a change, build a patch, and deploy

Change something visible in `lib/main.dart`. The simplest possible
change:

```dart
appBar: AppBar(title: const Text('my_shop — now with OTA!')),
```

Now build the patch (a binary diff of your new APK against the
baseline) and push it to Supabase:

```bash
# 1. Rebuild the release APK (the patch is diffed from this output)
flutter build apk --release --target-platform android-x64 \
  --dart-define-from-file=.env

# 2. Pack it into dist/patch.zip
flutter-ota build --name 1.0.1 --platform android --arch x86_64

# 3. Push it. --force = zero-click, auto-restart on the client.
export SUPABASE_SERVICE_ROLE_KEY=sb_secret_xxxxxxxx
flutter-ota deploy -b supabase -s dist -c production -p android \
  --target-app-version 1.0.0 --force -m "first hot fix"
```

What each flag means:

| Flag | Why |
|------|-----|
| `--name 1.0.1` | A distinct version. Bump it on every deploy; the SDK's loop guard skips a bundle whose version already equals the installed one. |
| `--target-app-version 1.0.0` | The bundle applies to baseline `1.0.0` (whatever your pubspec `version` is). Patches are bound to a base version, so a `1.0.1` patch won't apply to a `1.0.2` user. |
| `--force` | The app must apply + restart immediately (zero clicks). Without it, the bundle is staged and applies on the next cold start. |
| `-m "first hot fix"` | A human-readable message stored on the bundle. Your app can show this in a "what's new" dialog or in the SDK's forced-update overlay. |

**Verify:** `flutter-ota channel list` should now show a `1.0.1` bundle
on the `production` channel.

---

## 10. Watch it land

Kill the app and open it again. Because you deployed with `--force`
and `setupFlutterOta()` enabled `autoApplyUpdates`, here's what you
should see:

1. The app boots on `1.0.0` (the baseline).
2. In the background, the SDK calls `checkForUpdate()`.
3. It finds the forced `1.0.1` bundle, downloads + stages it.
4. The app **restarts automatically** — no tap, no dialog.
5. The app bar now reads `my_shop — now with OTA!`.

That's your first OTA. 🎉

**Verify:** check `adb logcat | grep flutter` and you should see
something like:

```
[FlutterPatcher] checkForUpdate: forced update available (1.0.1)
[FlutterPatcher] applyUpdate: patch 1.0.1 staged, restarting…
```

If you see "no update" instead, the most common reason is
`--target-app-version` mismatch — see FAQ below.

---

## 11. The mistakes Sam made (so you don't)

These are the five things that actually break, in order of how often
they happen:

1. **Forgot `--dart-define-from-file=.env` at build time.** Without it,
   `SUPABASE_URL` is empty and every backend call fails. *Always* pass
   it on both `flutter run` and `flutter build apk`. The error message
   is unhelpful: "no update available" or a connection-refused in
   `logcat`. **Fix:** make a script `scripts/build.sh` that always
   includes the flag, and never run `flutter build apk` without it.

2. **Ran `migrate` with the anon key.** Supabase needs the **service-role**
   key to create tables, RPCs, and buckets. The anon key is
   read-only-ish. **Fix:** export `SUPABASE_SERVICE_ROLE_KEY` before
   `migrate`, never put it in `.env`.

3. **Deployed without `--force` and expected an instant update.** A
   non-forced bundle is **staged for the next cold start** — that's the
   whole point of "staged rollout." Use `--force` for critical fixes.
   Use no `--force` for staged rollouts (1% → 5% → ...) where you
   want the update to be picked up organically.

4. **Reused the same `--name` on a second deploy.** The SDK's loop
   guard says "I'm already on `1.0.1`, no need to apply `1.0.1`
   again" and skips the install. **Fix:** bump the version on every
   deploy, every time. CI should refuse to deploy with a duplicate
   name.

5. **Edited Dart but the patch looked unchanged.** `flutter-ota build`
   diffs the **APK output**, not the Dart source. If you forget to
   re-run `flutter build apk` between edits, the diff is empty. **Fix:**
   always run `flutter build apk --release` *before* `flutter-ota
   build`, even for tiny changes.

Bonus mistake, less common but uglier:

6. **Shipped a `target-app-version` that doesn't match the user's
   installed version.** If your app's `pubspec.yaml` is `1.0.0+1` but
   you deployed with `--target-app-version 1.0.1`, the backend keeps
   the bundle but the user's `getUpdateInfo` filter rejects it. The
   app silently stays "up to date." **Fix:** always set
   `--target-app-version` to match the `version:` field in pubspec
   (without the `+build_number`).

---

## 12. Where to go next

You've shipped your first OTA. The rest of the docs fill in the details.

**Setup / configuration**
- [Configuration](configuration.md) — every env var, resolution order,
  secrets policy, build-time vs. runtime vs. project-config
- [Backends](backends.md) — Supabase / Postgres / Cloudflare / AWS /
  PocketBase setup, side-by-side

**Workflow**
- [Developer Guide](developer-guide.md) — full workflow reference (init,
  migrate, build, deploy, SDK API, targeting, troubleshooting)
- [CLI Reference](cli-reference.md) — every command, subcommand, and
  flag

**Production**
- [Production Playbook](doc/production-playbook.md) — staged rollout,
  diagnostic reporting, emergency rollback procedures
- [Crash Protection](doc/crash-protection.md) — auto-rollback,
  blacklist, Android version differences
- [Architecture](doc/architecture.md) — internals, server protocol,
  signing, advanced config

**Reference**
- [API Reference](doc/api-reference.md) — `FlutterPatcher` methods,
  error codes, asset patching
- [FAQ](doc/faq.md) — versioning, cold start, store policy
