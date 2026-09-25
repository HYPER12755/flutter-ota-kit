# CLI Reference

The `flutter-ota` CLI builds patches, deploys them to your backend, and manages
bundles / channels / rollbacks — mirroring the `hot-updater` workflow.

## Install

```bash
npm install -g @_nazmiforreal/flutter-ota
flutter-ota --help
```

A prebuilt `linux-x64` binary ships in the package. On other platforms the CLI
is compiled on install from bundled Dart source, which requires the **Flutter
SDK** (the CLI depends on the `flutter_ota_kit` Flutter package). During local
development you can also run it straight from source:

```bash
dart run bin/flutter_ota_kit.dart <command>   # from packages/cli-tools
```

## Invocation

```
flutter-ota <command> [subcommand] [flags]
```

Global option: `-v, --verbose` — print full error stack traces.

Help works at every level, including nested subcommands:

```bash
flutter-ota --help
flutter-ota bundle --help
flutter-ota bundle list --help
flutter-ota pocketbase records list --help
```

## Config resolution

Every backend-touching command resolves settings with this precedence:

```
explicit flag  >  environment variable  >  .flutter_ota_kit/config.json  >  built-in default
```

Config file search order:
1. `./.flutter_ota_kit/config.json` (project — written by `init`)
2. `~/.flutter_ota_kit/config.json` (global — `init --global`)

Secrets (service-role keys, DB passwords, tokens) belong in your shell
environment or `.env`, **not** in the committed config. See
[Configuration](configuration.md) for the full env-var list per backend.

---

## Commands

| Command | Purpose |
|---------|---------|
| `init` | Scaffold config + integration files for a backend |
| `config` | Get / set / list configuration values |
| `keys` | Generate an Ed25519 signing keypair |
| `doctor` | Diagnose the environment + backend connectivity |
| `fingerprint` | Compute a deterministic build fingerprint |
| `build` | Pack a release APK into a device-ready `patch.zip` |
| `deploy` | Upload a bundle + register it on the backend |
| `bundle` | Manage bundles (list/show/delete/disable/enable/force/promote/update) |
| `channel` | Manage channels (list/get/set) |
| `rollback` | Roll a channel back to a previous bundle |
| `storage` | Inspect / delete stored bundle objects |
| `migrate` | Run backend schema migrations |
| `console` | Open the web console |
| `pocketbase` | Manage a local PocketBase instance |

---

### `init`

Scaffold `.flutter_ota_kit/config.json`, an `.env` template, and
`lib/flutter_ota_kit_setup.dart`; add `INTERNET` permission and gitignore
entries.

```bash
flutter-ota init supabase        # backend as first positional arg
flutter-ota init                 # interactive picker on a TTY
```

| Flag | Default | Description |
|------|---------|-------------|
| `-p, --provider` | `supabase` | Backend (also accepted as the first positional arg): `supabase` / `postgres` / `cloudflare` / `aws` / `pocketbase` |
| `-c, --channel` | `production` | Default channel |
| `--platform` | `android` | Default platform |
| `-s, --source` | `./dist` | Default deploy source |
| `--global` | — | Write the global `~/.flutter_ota_kit` config (no scaffolding) |
| `-f, --force` | — | Overwrite an existing config |

---

### `build`

Pack a release APK into `dist/patch.zip` (+ `manifest.json`). Includes every ABI
found in the APK by default, so one bundle serves all devices.

```bash
flutter-ota build \
  --apk build/app/outputs/flutter-apk/app-release.apk \
  --version 1.0.1 \
  --target-version-code 100
```

| Flag | Description |
|------|-------------|
| `-a, --apk` | **Required.** Release APK to extract `libapp.so` + assets from |
| `-V, --version` | **Required.** Patch version string (stored in `manifest.version`) |
| `-t, --target-version-code` | **Required.** versionCode of the APK users already have |
| `-A, --assets` | Asset key(s) to overlay (repeatable; `@file` reads a list) |
| `--abi` | Restrict to one ABI (e.g. `arm64-v8a`); default = all in the APK |
| `-o, --out` | Output dir (default `dist`) |

---

### `deploy`

Upload the bundle to storage and register it in the database.

```bash
flutter-ota deploy -b supabase -s dist -c production -p android \
  --target-app-version 1.0.0 --force -m "hotfix: crash on login"
```

| Flag | Description |
|------|-------------|
| `-b, --backend` | Backend provider (defaults to configured one) |
| `-s, --source` | Source dir or `patch.zip` to upload |
| `-c, --channel` | Target channel |
| `-p, --platform` | Platform (default `android`) |
| `-m, --message` | Release message (shown in the forced-update UI) |
| `-f, --force` | Force the update on clients |
| `-t, --target-app-version` | Semver target (XOR with fingerprint) |
| `-F, --fingerprint-hash` | Fingerprint target (XOR with app version) |
| `-k, --key` | Ed25519 private key file — signs the bundle |
| `-g, --git-commit-hash` | Git commit (auto-detected if omitted) |
| `-i, --bundle-id` | Explicit bundle id (uuidv7 by default) |

---

### `bundle`

```bash
flutter-ota bundle list -c production
flutter-ota bundle show   -i <uuid>
flutter-ota bundle force  -i <uuid>          # force; --off to clear
flutter-ota bundle promote -i <uuid> -c beta
flutter-ota bundle update -i <uuid> -m "new note" --enabled true
flutter-ota bundle disable -i <uuid>
flutter-ota bundle delete  -i <uuid> [--keep-storage]
```

All subcommands accept `-b, --backend`. Common flags:

| Subcommand | Flags |
|------------|-------|
| `list` | `-c, --channel` · `-p, --platform` · `--enabled <true\|false>` · `-l, --limit` (default 20) |
| `show` | `-i, --id` (required) |
| `delete` | `-i, --id` · `--keep-storage` |
| `disable` / `enable` | `-i, --id` |
| `force` | `-i, --id` · `--off` (clear instead of set) |
| `promote` | `-i, --id` · `-c, --channel` |
| `update` | `-i, --id` · `-m, --message` · `--target-version` · `--enabled <true\|false>` · `-f, --force <true\|false>` |

---

### `channel`

```bash
flutter-ota channel list
flutter-ota channel get -c production
flutter-ota channel set -c production -i <uuid>
```

| Subcommand | Flags |
|------------|-------|
| `list` | `-b, --backend` |
| `get` | `-c, --channel` |
| `set` | `-c, --channel` · `-i, --bundle-id` |

---

### `rollback`

Disable the latest enabled bundle on a channel (or roll back to a specific one).

```bash
flutter-ota rollback -c production
flutter-ota rollback -c production -i <uuid>
```

| Flag | Description |
|------|-------------|
| `-b, --backend` | Backend provider |
| `-c, --channel` | **Required.** Channel to roll back |
| `-i, --bundle-id` | Roll back to this specific bundle |
| `-p, --platform` | Platform filter |

---

### `storage`

```bash
flutter-ota storage list --prefix bundles
flutter-ota storage delete --key bundles/<id>/patch.zip
flutter-ota storage delete --uri <full-storage-uri>
```

| Subcommand | Flags |
|------------|-------|
| `list` | `-b, --backend` · `--prefix` |
| `delete` | `-b, --backend` · `--key` (repeatable) · `--uri` |

---

### `migrate`

Provision the backend schema.

```bash
SUPABASE_SERVICE_ROLE_KEY=… flutter-ota migrate supabase   # fully automated
flutter-ota migrate postgres --database-url postgres://…
flutter-ota migrate cloudflare                             # creates D1/R2, runs SQL
flutter-ota migrate aws                                    # no SQL — informational
flutter-ota migrate pocketbase                             # installs the PB schema
flutter-ota migrate supabase --dry-run                     # print instead of apply
```

| Flag | Description |
|------|-------------|
| `-b, --backend` | Backend provider |
| `-d, --dry-run` | Print migrations instead of applying |
| `--database-url` | Postgres connection string (or `DATABASE_URL`) |
| `--management-key` | Supabase Management API key (or `SUPABASE_MANAGEMENT_KEY`) — no separate Postgres connection needed |
| `--migrations-dir` | Directory of ordered `*.sql` files |
| `--account-id` / `--api-token` / `--d1-database-id` / `--r2-bucket` | Cloudflare (or `CLOUDFLARE_*` / `R2_BUCKET`) |
| `--pocketbase-url` / `--pocketbase-admin-email` / `--pocketbase-admin-password` | PocketBase (or `POCKETBASE_*`) |

Per-backend behavior: **supabase** uses the Management API or a Postgres
connection (and ensures the storage bucket); **postgres** applies SQL and tracks
it in `_flutter_ota_kit_migrations`; **cloudflare** creates the D1 DB if needed,
runs SQL, ensures the R2 bucket; **aws** has no SQL (bucket/prefix auto-created
on first deploy); **pocketbase** installs the collection schema.

---

### `keys`

Generate an Ed25519 keypair for signing bundles.

```bash
flutter-ota keys              # print a private/public keypair
flutter-ota keys --save       # also persist the public key into the config
```

Sign at deploy time with `deploy --key <private-key-file>`; put the public key
in your app via `FlutterPatcher.init(publicKeyBase64: '…')`.

---

### `fingerprint`

```bash
flutter-ota fingerprint --source ./dist
```

| Flag | Default | Description |
|------|---------|-------------|
| `-s, --source` | `./dist` | Directory to fingerprint |

---

### `doctor`

```bash
flutter-ota doctor -b supabase
```

Checks the environment and backend connectivity; prints the channel list when
the backend is reachable.

---

### `config`

```bash
flutter-ota config get supabase.url
flutter-ota config set supabase.bucket bundles
flutter-ota config list
```

| Subcommand | Flags |
|------------|-------|
| `get` | `-k, --key` (or positional key) |
| `set` | `-k, --key` · `--value` (or two positional args) |
| `list` | — |

---

### `console`

```bash
flutter-ota console          # print the console URL
flutter-ota console --open   # launch with `flutter run -d chrome`
```

---

### `pocketbase`

Manage a local single-binary PocketBase backend. Subcommands: `install`,
`serve`, `stop`, `status`, `backup`, `export`, `import`, `admin`, `migrate`,
`health`, `logs`, `records`, `collections`, `settings`, `sql`, `crons`,
`query`, `config`. Several have their own nested subcommands (e.g.
`pocketbase backup create|list|delete|restore`, `pocketbase records
list|get|create|update|delete|batch`).

```bash
flutter-ota pocketbase install
flutter-ota pocketbase serve --admin-email a@b.c --admin-password '…'
flutter-ota pocketbase status
flutter-ota pocketbase records list --help    # per-subcommand help
```

See [Backends → PocketBase](backends.md) for the end-to-end setup.

---

## See also

- [Getting Started](getting-started.md) — the 5-minute path
- [Backends](backends.md) — per-backend setup + env vars
- [Configuration](configuration.md) — precedence + full env-var list
- [Production Playbook](production-playbook.md) — staged rollout + rollback
