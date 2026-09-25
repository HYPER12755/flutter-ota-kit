# flutter-ota

[![npm](https://img.shields.io/npm/v/@_nazmiforreal/flutter-ota.svg)](https://www.npmjs.com/package/@_nazmiforreal/flutter-ota)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/HYPER12755/flutter-ota-kit/blob/main/LICENSE)

### The command line for [flutter_ota_kit](https://pub.dev/packages/flutter_ota_kit) — build patches, deploy them to your backend, and manage rollouts.

`flutter-ota` is the companion CLI for **flutter_ota_kit**, open-source OTA code
push for Flutter Android. Pack a release APK into a signed patch, upload it to
the backend **you** own (Supabase / Postgres / Cloudflare / AWS / PocketBase),
and manage channels, staged rollouts, and instant rollback — no store review, no
monthly bill.

> The runtime SDK your app depends on is the separate
> [`flutter_ota_kit`](https://pub.dev/packages/flutter_ota_kit) pub package.

---

## Install

```bash
npm i -g @_nazmiforreal/flutter-ota
flutter-ota --help
```

A prebuilt `linux-x64` binary ships in the package. On other platforms the CLI
compiles from bundled Dart source on first install, which needs the
[**Flutter SDK**](https://flutter.dev) (the CLI shares the `flutter_ota_kit`
Flutter package). If Flutter isn't available, build a binary once yourself:

```bash
cd $(npm root -g)/@_nazmiforreal/flutter-ota/dart-src/packages/cli-tools
flutter pub get && dart compile exe bin/flutter_ota_kit.dart -o ../../bin/flutter-ota-<os>-<arch>
```

---

## The 60-second workflow

```bash
# 1. Scaffold config + a setup helper for your backend
#    (adds the latest flutter_ota_kit to your pubspec automatically)
flutter-ota init supabase        # or: postgres | cloudflare | aws | pocketbase

# 2. Provision the backend (Supabase & PocketBase are fully automated)
flutter-ota migrate supabase

# 3. Build the release APK, then pack it into a device-ready patch
flutter build apk --release
flutter-ota build \
  --apk build/app/outputs/flutter-apk/app-release.apk \
  --version 1.0.1 \
  --target-version-code 100

# 4. Sign + deploy it to a channel
flutter-ota deploy --source dist --channel production \
  --target-app-version 1.0.0 --force -m "hotfix: crash on login"
```

Devices pick up the patch on their next launch. Pull it back with:

```bash
flutter-ota rollback --channel production
```

---

## Commands

| Command | What it does |
|---------|--------------|
| `init <backend>` | Scaffold config, `.env`, and `lib/flutter_ota_kit_setup.dart`; add the SDK dependency + `INTERNET` permission |
| `build` | Pack a release APK into `dist/patch.zip` (all ABIs by default) |
| `deploy` | Upload + register a bundle; sign it with `--key` |
| `bundle` | `list` / `show` / `delete` / `disable` / `enable` / `force` / `promote` / `update` |
| `channel` | `list` / `get` / `set` the live bundle per channel |
| `rollback` | Disable the latest enabled bundle (or roll back to a specific one) |
| `storage` | `list` / `delete` stored bundle objects |
| `migrate` | Provision the backend schema |
| `keys` | Generate an Ed25519 signing keypair |
| `fingerprint` | Compute a deterministic build fingerprint |
| `doctor` | Diagnose the environment + backend connectivity |
| `config` | `get` / `set` / `list` config values |
| `console` | Open the web console |
| `pocketbase` | Manage a local single-binary PocketBase backend |

Help works at every level, including nested subcommands:

```bash
flutter-ota deploy --help
flutter-ota bundle list --help
flutter-ota pocketbase records list --help
```

---

## Backends

Select one with `--backend supabase|postgres|cloudflare|aws|pocketbase` (or set
`provider` in `.flutter_ota_kit/config.json`). Settings resolve with a clear
precedence:

```
explicit flag  >  environment variable  >  .flutter_ota_kit/config.json  >  default
```

Config search order: `./.flutter_ota_kit/config.json`, then
`~/.flutter_ota_kit/config.json`. Secrets belong in your shell env or `.env`,
never in committed config.

| Backend | Provisioning |
|---------|--------------|
| **Supabase** | `migrate supabase` — SQL + storage bucket, fully automated |
| **PocketBase** | `pocketbase install` + `pocketbase serve` — single binary, schema auto-installed |
| **Postgres** | `migrate postgres` applies SQL migrations |
| **Cloudflare** | `migrate cloudflare` creates D1 + R2, runs SQL |
| **AWS** | No SQL — S3 bucket/prefix created on first `deploy` |

---

## Documentation

- [CLI Reference](https://github.com/HYPER12755/flutter-ota-kit/blob/main/doc/cli-reference.md)
- [Getting Started](https://github.com/HYPER12755/flutter-ota-kit/blob/main/doc/getting-started.md)
- [Backends](https://github.com/HYPER12755/flutter-ota-kit/blob/main/doc/backends.md)
- [Production Playbook](https://github.com/HYPER12755/flutter-ota-kit/blob/main/doc/production-playbook.md)

---

## License

MIT
