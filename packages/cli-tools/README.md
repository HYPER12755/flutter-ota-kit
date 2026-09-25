# flutter_ota_kit_cli

[![npm](https://img.shields.io/npm/v/@_nazmiforreal/flutter-ota.svg)](https://www.npmjs.com/package/@_nazmiforreal/flutter-ota)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](../../LICENSE)

### The command line for [flutter_ota_kit](https://pub.dev/packages/flutter_ota_kit) — build patches, deploy them to your backend, and manage rollouts.

`flutter-ota` is the companion CLI for **flutter_ota_kit**, open-source OTA code
push for Flutter Android. It packs a release APK into a signed patch, uploads it
to the backend **you** own (Supabase / Postgres / Cloudflare / AWS / PocketBase),
and gives you first-class commands for channels, staged rollouts, and instant
rollback.

> This tool ships via npm as `@_nazmiforreal/flutter-ota`. The runtime SDK your
> app depends on is the separate [`flutter_ota_kit`](https://pub.dev/packages/flutter_ota_kit)
> pub package.

---

## Install

```bash
npm i -g @_nazmiforreal/flutter-ota
flutter-ota --help
```

A prebuilt `linux-x64` binary ships in the package. On other platforms the CLI
compiles from bundled Dart source on first install, which needs the
[**Flutter SDK**](https://flutter.dev) (the CLI shares the `flutter_ota_kit`
package). No Flutter? Point `flutter-ota` at a prebuilt binary you build once
with `dart compile exe`.

---

## The 60-second workflow

```bash
# 1. Scaffold config + a setup helper for your backend (adds the latest
#    flutter_ota_kit to your pubspec automatically)
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

Devices pick up the patch on their next launch. To pull it back:

```bash
flutter-ota rollback --channel production
```

---

## Commands

| Command | What it does |
|---------|--------------|
| `init <backend>` | Scaffold `.flutter_ota_kit/config.json`, `.env`, and `lib/flutter_ota_kit_setup.dart`; add the SDK dependency + `INTERNET` permission |
| `build` | Pack a release APK into a device-ready `dist/patch.zip` (all ABIs by default) |
| `deploy` | Upload + register a bundle; sign it with `--key` |
| `bundle` | `list` / `show` / `delete` / `disable` / `enable` / `force` / `promote` / `update` |
| `channel` | `list` / `get` / `set` the live bundle per channel |
| `rollback` | Disable the latest enabled bundle on a channel (or roll back to a specific one) |
| `storage` | `list` / `delete` stored bundle objects |
| `migrate` | Provision the backend schema (Supabase / Postgres / Cloudflare / AWS / PocketBase) |
| `keys` | Generate an Ed25519 signing keypair |
| `fingerprint` | Compute a deterministic build fingerprint for fingerprint-targeted rollouts |
| `doctor` | Diagnose the environment + backend connectivity |
| `config` | `get` / `set` / `list` config values |
| `console` | Open the web console |
| `pocketbase` | Manage a local single-binary PocketBase backend (install / serve / …) |

Every command has help, including nested subcommands:

```bash
flutter-ota deploy --help
flutter-ota bundle list --help
flutter-ota pocketbase records list --help
```

Meaningful short flags map to the option's own name — e.g. on `deploy`:
`-s`ource, `-c`hannel, `-m`essage, `-f`orce, `-t`arget-app-version,
`-k`ey, `-b`ackend.

---

## Backends

Select one with `--backend supabase|postgres|cloudflare|aws|pocketbase` (or set
`provider` in `.flutter_ota_kit/config.json`). Each resolves settings with a
clear precedence:

```
explicit flag  >  environment variable  >  .flutter_ota_kit/config.json  >  default
```

Config file search order: `./.flutter_ota_kit/config.json`, then the global
`~/.flutter_ota_kit/config.json`. Secrets (service-role keys, DB passwords,
tokens) belong in your shell environment or `.env` — never in committed config.

| Backend | Provisioning |
|---------|--------------|
| **Supabase** | `migrate supabase` runs SQL + creates the storage bucket — fully automated |
| **PocketBase** | `pocketbase install` + `pocketbase serve` — single binary, schema auto-installed |
| **Postgres** | `migrate postgres` applies the SQL migrations |
| **Cloudflare** | `migrate cloudflare` creates D1 + R2 and runs SQL |
| **AWS** | No SQL — the S3 bucket/prefix is created on first `deploy` |

See the [Backends guide](https://github.com/HYPER12755/flutter-ota-kit/blob/main/doc/backends.md)
for per-backend env vars and setup.

---

## Signing

```bash
flutter-ota keys --save                 # generate a keypair, save the public half
flutter-ota deploy --key <private-file> # sign the bundle (Ed25519 over the MD5)
```

Put the public key in your app via `FlutterPatcher.init(publicKeyBase64: '…')`;
keep the private key on your CI/build machine, never in the app bundle.

---

## Documentation

- [CLI Reference](https://github.com/HYPER12755/flutter-ota-kit/blob/main/doc/cli-reference.md) — every command + flag
- [Getting Started](https://github.com/HYPER12755/flutter-ota-kit/blob/main/doc/getting-started.md)
- [Backends](https://github.com/HYPER12755/flutter-ota-kit/blob/main/doc/backends.md)
- [Configuration](https://github.com/HYPER12755/flutter-ota-kit/blob/main/doc/configuration.md)
- [Production Playbook](https://github.com/HYPER12755/flutter-ota-kit/blob/main/doc/production-playbook.md)

---

## License

MIT
