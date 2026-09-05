# CLI Reference — `flutter-ota`

The `flutter-ota` CLI (npm `@_nazmiforreal/flutter-ota`) scaffolds your
project, provisions backends, builds patches, and deploys them. Every
command accepts `-v, --verbose` (full error stack traces) and `-h, --help`.

`flutter-ota --help` is the live, authoritative flag list. This page
documents what each command does and the common usage patterns — read
this to know which command to reach for.

---

## Quick reference (the 5 you'll use)

| Command | What it does | When you reach for it |
|---------|--------------|------------------------|
| `init <backend>` | Scaffold the project | Once per project, or when switching backends |
| `migrate <backend>` | Create the tables, buckets, RPCs | Once per backend, or after a schema change |
| `build` | Make a `patch.zip` from your latest APK | Every release |
| `deploy` | Push `patch.zip` to your backend, register a bundle | Every release |
| `doctor` | Sanity-check the env + backend | When something doesn't work |

The other 11 commands are for fine-grained control (rollback, channel
management, key management, storage inspection, etc.). They're
documented below.

---

## Global flags

| Flag | Effect |
|------|--------|
| `-v, --verbose` | Print full error stack traces |
| `-h, --help` | Print usage for the current command |

Every command reads `.env` for the same env vars as the SDK does
(see [Configuration](configuration.md)). Pass `--dart-define-from-file=.env`
to `flutter build` (the SDK build step, not `flutter-ota build`) so
secrets reach the compiled app.

---

## `init <backend>`

Scaffold a project for one of the 5 supported backends
(`supabase` / `postgres` / `cloudflare` / `aws` / `pocketbase`).

What it does, in order:

1. Writes `.flutter_ota_kit/config.json` — CLI working state
2. Writes `.env` at the project root with placeholder values
3. Ensures `flutter_ota_kit:` is in `pubspec.yaml`
4. Adds `INTERNET` to `android/app/src/main/AndroidManifest.xml`
5. Generates `lib/flutter_ota_kit_setup.dart`
6. Adds `.flutter_ota_kit/` and `.env` to `.gitignore`

| Flag | Abbr | Default | Meaning |
|------|------|---------|---------|
| `--provider` | `-p` | positional | Backend (same as the first positional arg) |
| `--channel` | `-c` | `production` | Default channel |
| `--platform` | | `android` | Default platform |
| `--source` | `-s` | `./dist` | Default deploy source dir |
| `--global` | | off | Write to `~/.flutter_ota_kit/config.json` instead of project |
| `--force` | `-f` | off | Overwrite an existing config |

```bash
flutter-ota init supabase
flutter-ota init postgres --channel staging
flutter-ota init pocketbase        # the newest backend, single-binary self-hosted
```

---

## `migrate <backend>`

Provision the backend's tables, RPCs, and storage. What gets created:

| Backend | What `migrate` does |
|---------|---------------------|
| `supabase` | Runs the SQL migration, creates the `bundles` table, `get_update_info_*` RPCs, and the public `bundles` storage bucket. **Fully automatic** with the Management API key. |
| `postgres` | Prints the SQL files in `plugins/postgres/sql/` for you to run against your database. |
| `cloudflare` | Prints the `wrangler` commands to create the D1 database, run migrations, and configure the R2 bucket. |
| `aws` | Prints the S3 / DynamoDB / RDS commands. **Does not** create AWS resources automatically — that's an IAM decision. |
| `pocketbase` | No separate `migrate` needed; the `pocketbase install` + `pocketbase serve` commands install the schema. |

| Flag | Abbr | Meaning |
|------|------|---------|
| `--backend` | `-b` | Backend (same as positional) |
| `--database-url` | | Postgres: override DB connection string (default: `POSTGRES_HOST` env) |
| `--management-key` | | Supabase Management API key (default: `SUPABASE_MANAGEMENT_KEY` env) |
| `--migrations-dir` | | Override the directory of `.sql` files to run |
| `--dry-run` | `-d` | Print the migrations instead of applying them |

```bash
flutter-ota migrate supabase
flutter-ota migrate postgres --dry-run     # show the SQL without applying
flutter-ota migrate cloudflare
```

---

## `build`

Build a `patch.zip` from your latest Flutter build.

Typical flow:

```bash
# 1. Build the release APK (this is what the patch is diffed from)
flutter build apk --release --target-platform android-x64

# 2. Pack it
flutter-ota build --name 1.0.1 --platform android --arch x86_64

# 3. Deploy it
flutter-ota deploy -b supabase -s dist -c production -p android \
  --target-app-version 1.0.0 --force
```

| Flag | Abbr | Default | Meaning |
|------|------|---------|---------|
| `--arch` | `-a` | host arch | Target ABI: `x86_64`, `arm64-v8a`, `armeabi-v7a` |
| `--name` | | app version | The patch's `version` field (e.g. `1.0.1`) |
| `--target-version` | `-t` | host versionCode | The host APK's `versionCode` (from `pubspec.yaml`) |
| `--source` | | `./dist` | Build output dir to pack (default: just-built APK location) |
| `--platform` | `-p` | `android` | Platform tag |
| `--channel` | `-c` | `production` | Channel tag |
| `--output` | `-o` | `./dist` | Where to write `patch.zip` |
| `--key` | `-k` | | Ed25519 private key file (PEM) to sign the bundle |
| `--assets` | | none | Comma-separated list of asset paths to include (since 0.1.3) |
| `--abi` | | host ABIs | Restrict the patch to specific ABIs (smaller patches for mixed-ABI fleets) |

```bash
# Single-ABI patch (smaller, for ARM-only fleet)
flutter-ota build --name 1.0.1 --arch arm64-v8a --abi arm64-v8a

# With assets
flutter-ota build --name 1.0.1 \
  --assets assets/hero.png,assets/icons/home.svg,assets/strings/zh.json

# Signed patch
flutter-ota build --name 1.0.1 --key ./keys/release.pem
```

---

## `deploy`

Upload `dist/patch.zip` to the configured backend and register a
bundle record. Returns the bundle id.

| Flag | Abbr | Default | Meaning |
|------|------|---------|---------|
| `--backend` | `-b` | from config | `supabase` / `postgres` / `cloudflare` / `aws` / `pocketbase` |
| `--source` | `-s` | `./dist` | Directory containing `patch.zip` |
| `--channel` | `-c` | from config | Target channel |
| `--platform` | `-p` | `android` | Platform tag |
| `--message` | `-m` | `''` | Release note (shown in the forced-update overlay) |
| `--force` | `-f` | off | Mark the bundle as forced-update. The app auto-restarts on the user's device when the SDK detects it. |
| `--target-app-version` | | host app version | Which app version this bundle applies to. **Must match** the user's installed `pubspec.yaml` `version:` field. |
| `--fingerprint-hash` | | | Alternative to `--target-app-version` for fingerprint-strategy targeting. |
| `--key` | `-k` | | Ed25519 private key file to sign the bundle |
| `--git-commit-hash` | | auto-detect | `git rev-parse HEAD` if omitted |
| `--bundle-id` | `-i` | uuidv7 | Explicit bundle id (default: random uuidv7) |

```bash
# Standard deploy (next cold start)
flutter-ota deploy -b supabase -s dist -c production -p android \
  --target-app-version 1.0.0

# Forced update (auto-restart on the user's device)
flutter-ota deploy -b supabase -s dist -c production -p android \
  --target-app-version 1.0.0 --force -m "critical security fix"
```

---

## `channel`

Manage release channels. Subcommands: `list`, `get`, `set`.

| Subcommand | Flags | Effect |
|------------|-------|--------|
| `channel list` | `-b` | List all channels on the backend |
| `channel get` | `-b`, `-c` | Show the currently-live bundle on a channel |
| `channel set` | `-b`, `-c` | Set the default channel (persists into `config.json`) |

```bash
flutter-ota channel list
flutter-ota channel get -b supabase -c production
flutter-ota channel set -c beta    # next deploy will land on 'beta'
```

---

## `bundle`

Inspect and manage registered bundles. This is the read/write
interface to the `bundles` table on your backend.

| Subcommand | Key flags | Effect |
|------------|-----------|--------|
| `bundle list` | `-b`, `-c`, `-p`, `--enabled`, `-l/--limit` | List bundles (filterable) |
| `bundle show` | `-b`, `--id` | Show one bundle's full record |
| `bundle delete` | `-b`, `--id`, `--keep-storage` | Delete a bundle; `--keep-storage` keeps the `patch.zip` in the storage bucket |
| `bundle enable` | `-b`, `--id` | Re-enable a disabled bundle |
| `bundle disable` | `-b`, `--id` | Mark a bundle as disabled (the SDK won't return it) |
| `bundle force` | `-b`, `--id`, `--off` | Set or clear (`--off`) the forced-update flag |
| `bundle promote` | `-b`, `--id`, `-c` | Promote a bundle to a different channel |
| `bundle update` | `-b`, `--id`, `-m`, `--target-version`, `--enabled` | Edit a bundle's metadata in-place |

```bash
# List the 5 most recent bundles on production
flutter-ota bundle list -b supabase -c production -l 5

# Disable a bad bundle without deleting it
flutter-ota bundle disable -b supabase --id 01a059a6-...

# Force-promote a candidate to production
flutter-ota bundle promote -b supabase --id 01a059a6-... -c production
```

---

## `config`

Read/write the project (or global) `config.json`. Subcommands: `get`,
`set`, `list`.

| Subcommand | Flags | Effect |
|------------|-------|--------|
| `config get` | `-k/--key` (dot-path, e.g. `supabase.url`) | Read one value |
| `config set` | `-k/--key`, `--value` | Set one value |
| `config list` | — | Dump the whole `config.json` |

```bash
flutter-ota config list
flutter-ota config get -k supabase.bucket
flutter-ota config set -k channel -v beta
```

`config.json` stores CLI working state — the service-role key, the
default channel, the default platform, etc. It is **git-ignored**.

---

## `keys`

Generate, inspect, and persist Ed25519 keypairs for bundle signing.

```bash
flutter-ota keys                  # show current public key (or generate one)
flutter-ota keys --save           # persist public key into project config
flutter-ota keys --global         # same, but into ~/.flutter_ota_kit
```

The keypair is stored in `~/.flutter_ota_kit/keys.json` (git-ignored).
The public half is what your app's `init(publicKeyBase64: ...)` reads
at build time. The private half is what `build --key` and `deploy --key`
use to sign.

For the device side, see [Architecture → Patch signing](architecture.md#patch-signing)
for the full flow.

---

## `rollback`

Roll a channel back to a previous bundle. This is a **server-side**
rollback: it changes the channel's `current_bundle` pointer so the next
update-check returns the older bundle.

| Flag | Abbr | Meaning |
|------|------|---------|
| `--backend` | `-b` | backend provider |
| `--channel` | `-c` | channel to roll back |
| `--bundle-id` | `-i` | roll back to this specific bundle id |
| `--platform` | `-p` | platform filter (default: all) |

```bash
# Roll production back to the previous stable bundle
flutter-ota rollback -b supabase -c production --bundle-id 01a059a5-...
```

This is **not** the same as `FlutterPatcher.rollback()` in the SDK,
which is a local operation that deletes the patch on the user's device.
The CLI's `rollback` changes the server's view; the device's
`FlutterPatcher.rollback()` clears the local state.

---

## `pocketbase`

Manage a local PocketBase instance. PocketBase is unique among the
backends — the CLI ships a prebuilt PB binary and can install/serve
it for you, so a single command gives you a fully working backend.

| Subcommand | Effect |
|------------|--------|
| `pocketbase install` | Download the right PB binary for the current platform to `~/.flutter_ota_kit/pocketbase/<version>/` |
| `pocketbase serve` | Start a local PB instance, install the flutter_ota_kit schema, and wait for SIGINT to stop |
| `pocketbase stop` | Hint (kill the `serve` process via Ctrl+C) |
| `pocketbase status` | Show installed PB version and binary path |

| Flag | Default | Meaning |
|------|---------|---------|
| `--version` | `0.22.21` | PB version to install |
| `--port` | `8090` | HTTP port |
| `--host` | `127.0.0.1` | Bind address (use `0.0.0.0` for LAN access) |
| `--data-dir` | `~/.flutter_ota_kit/pocketbase/<version>/` | PB data dir (the `pb_data` equivalent) |
| `--admin-email` | from env | Bootstrap admin email (required for `serve`) |
| `--admin-password` | from env | Bootstrap admin password (required for `serve`) |
| `--install-hooks` | `true` | Copy bundled JS hooks into `pb_data/pb_hooks/` on start |

```bash
# Install PB locally
flutter-ota pocketbase install

# Start PB with admin creds (from .env or shell)
POCKETBASE_ADMIN_EMAIL=admin@local.dev POCKETBASE_ADMIN_PASSWORD=secret \
  flutter-ota pocketbase serve --port 8090

# Then point your project at it:
# .env
#   POCKETBASE_URL=http://127.0.0.1:8090
#   POCKETBASE_ADMIN_EMAIL=admin@local.dev
#   POCKETBASE_ADMIN_PASSWORD=secret

flutter-ota init pocketbase
flutter-ota migrate pocketbase    # (no-op; serve installs the schema)
flutter-ota build --name 1.0.1
flutter-ota deploy -b pocketbase -s dist -c production -p android \
  --target-app-version 1.0.0 --force
```

For production, point `POCKETBASE_URL` at your own PB instance
(self-hosted or in the cloud) and skip the CLI's local server.

---

## `console`

Open the web-based admin UI for the configured backend.

```bash
flutter-ota console            # opens in your default browser if --open
flutter-ota console --no-open  # just print the URL
```

The console is a Flutter web app served from `packages/console/`. It
talks to the local sidecar server (`flutter_ota_kit_cli`'s built-in
admin API on port 3000 by default) which proxies to your real
backend. Bundles, channels, storage, and deploys are all editable in
the UI.

---

## `doctor`

Validate the local environment and backend connectivity. Run this when
something doesn't work.

```bash
flutter-ota doctor
# Output:
#   ✓ Dart 3.13.2
#   ✓ Supabase URL reachable
#   ✓ service-role key valid
#   ✓ bundles table exists
#   ✓ bundles bucket exists
#   ✓ channel list: production, staging, beta
```

| Flag | Abbr | Meaning |
|------|------|---------|
| `--backend` | `-b` | Force a specific backend check (otherwise: the one in `config.json`) |

For PocketBase, `doctor` also checks the binary is installed at
`~/.flutter_ota_kit/pocketbase/<version>/` and probes the health
endpoint.

---

## `fingerprint`

Compute the build fingerprint hash used by `UpdateStrategy.fingerprint`
targeting. This is a per-build content hash (not the Android `fingerprintHash`
of the app) that lets you target devices by their exact APK content.

| Flag | Abbr | Default | Meaning |
|------|------|---------|---------|
| `--source` | `-s` | `./dist` | Directory to fingerprint (the build output) |

```bash
flutter-ota fingerprint -s dist
# Output: 8d969eef6ecad3c29a3a629280e686cf0c3f5d5a86aff3ca12020c923adc6c92
```

Use the hash as `--fingerprint-hash` on `deploy` to target only devices
running an APK with that exact build.

---

## `storage`

Inspect / delete raw storage objects. This bypasses the bundle
abstraction and operates on the underlying storage bucket directly —
useful for cleaning up orphans after a failed `deploy`.

| Subcommand | Flags |
|------------|-------|
| `storage list` | `-b/--backend`, `--prefix` |
| `storage delete` | `-b/--backend`, `--uri` |

```bash
# List orphan objects (not referenced by any bundle)
flutter-ota storage list -b supabase --prefix bundles/

# Delete a specific object
flutter-ota storage delete -b supabase --uri supabase-storage://bundles/abc.zip
```

**Use with care** — deleting a storage object that's still referenced
by a bundle leaves the bundle in a broken state.

---

## See also

- [Configuration](configuration.md) — every env var, `.env` format, resolution order
- [Backends](backends.md) — per-backend setup with copy-paste commands
- [Developer Guide](developer-guide.md) — full workflow reference
- [Architecture](architecture.md) — internals, signing, advanced config
- [Production Playbook](production-playbook.md) — staged rollout,
  diagnostic reporting, emergency rollback
