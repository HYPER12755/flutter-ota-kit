# CLI Reference — `flutter-ota`

The `flutter-ota` CLI (npm `@_nazmiforreal/flutter-ota`) provisions backends,
builds patches, and deploys them. Every command accepts a global
`-v, --verbose` flag (prints full error stack traces) and `-h, --help`.

Run `flutter-ota --help` or `flutter-ota <command> --help` for the live,
authoritative flag list.

---

## Global flags
| Flag | Description |
| --- | --- |
| `-v, --verbose` | Show full error stack traces. |
| `-h, --help` | Show usage. |

---

## `init <backend>`
Scaffold a project for one backend (`supabase`, `postgres`, `cloudflare`, `aws`).
Writes `.flutter_ota_kit/config.json`, a `.env` scaffold, adds the
`INTERNET` permission, and generates `lib/flutter_ota_kit_setup.dart`.

| Flag | Abbr | Default | Notes |
| --- | --- | --- | --- |
| `--provider` | `-p` | positional backend | backend provider |
| `--channel` | `-c` | `production` | default channel |
| `--platform` | | `android` | target platform |
| `--source` | `-s` | `./dist` | default deploy source |
| `--global` | | off | write to `~/.flutter_ota_kit` (no scaffolding) |
| `--force` | `-f` | off | overwrite an existing config |

```bash
flutter-ota init supabase
flutter-ota init postgres --channel staging
```

---

## `migrate <backend>`
Provision a backend. Supabase runs the full SQL migration + creates the
`bundles` table, RPCs, and storage bucket automatically. Other backends print the
SQL / `wrangler` / AWS commands you run manually.

| Flag | Abbr | Notes |
| --- | --- | --- |
| `--backend` | `-b` | backend provider |
| `--database-url` | | override DB connection URL |
| `--management-key` | | Supabase Management API key (or `SUPABASE_MANAGEMENT_KEY`) |
| `--migrations-dir` | | custom migrations directory |
| `--dry-run` | `-d` | print migrations instead of applying |

```bash
flutter-ota migrate supabase
flutter-ota migrate postgres --dry-run
```

---

## `build`
Build a patch from a Flutter build and pack it into `dist/patch.zip`.

| Flag | Abbr | Notes |
| --- | --- | --- |
| `--arch` | `-a` | target ABI (e.g. `x86_64`, `arm64-v8a`) |
| `--name` | | patch version (defaults to app version) |
| `--target-version` | `-t` | target app version code |
| `--source` | | build output dir to pack |
| `--platform` | `-p` | default `android` |
| `--channel` | `-c` | channel to tag |
| `--output` | `-o` | output path |
| `--key` | `-k` | Ed25519 private key file to **sign** the bundle |

```bash
flutter build apk --release
flutter-ota build --name 1.0.1 --platform android --arch x86_64
```

---

## `deploy`
Upload a patch to the backend and register the bundle.

| Flag | Abbr | Notes |
| --- | --- | --- |
| `--backend` | `-b` | backend provider |
| `--source` | `-s` | directory to zip + upload |
| `--channel` | `-c` | target channel |
| `--platform` | `-p` | default `android` |
| `--message` | `-m` | release note |
| `--force` | `-f` | **forced** update (auto-restart on client) |
| `--target-app-version` | | native app version this bundle applies to |
| `--fingerprint-hash` | | target by build fingerprint instead of app version |
| `--key` | `-k` | Ed25519 private key to sign the bundle |
| `--git-commit-hash` | | auto-detected if omitted |
| `--bundle-id` | `-i` | explicit bundle id (uuidv7 by default) |

```bash
flutter-ota deploy -b supabase -s dist -c production -p android \
  --target-app-version 1.0.0 --force -m "critical fix"
```

---

## `channel`
Manage channels. Subcommands: `list`, `get`, `set`.

| Subcommand | Flags |
| --- | --- |
| `channel list` | `-b/--backend` |
| `channel get` | `-b/--backend`, `-c/--channel` |
| `channel set` | `-b/--backend`, `-c/--channel` (set default channel) |

---

## `bundle`
Inspect and manage registered bundles. Subcommands:

| Subcommand | Key flags | Purpose |
| --- | --- | --- |
| `bundle list` | `-b`, `-c`, `-p`, `--enabled`, `-l/--limit` | list bundles |
| `bundle show` | `-b`, `--id` | show one bundle |
| `bundle delete` | `-b`, `--id`, `--keep-storage` | delete a bundle (optionally keep the storage object) |
| `bundle enable` | `-b`, `--id` | enable a bundle |
| `bundle disable` | `-b`, `--id` | disable a bundle |
| `bundle force` | `-b`, `--id`, `--off` | set / clear the forced-update flag |
| `bundle promote` | `-b`, `--id`, `-c` | promote a bundle to a channel |
| `bundle update` | `-b`, `--id`, `-m/--message`, `--target-version`, `--enabled` | edit a bundle |

---

## `config`
Read/write the project `config.json`. Subcommands: `get`, `set`, `list`.

| Subcommand | Flags |
| --- | --- |
| `config get` | `-k/--key` (dot-path, e.g. `supabase.url`) |
| `config set` | `-k/--key`, `--value` |
| `config list` | — |

---

## `keys`
Ed25519 key management for bundle signing.

| Flag | Notes |
| --- | --- |
| `--save` | persist the public key into the project config |

```bash
flutter-ota keys            # show/generate keypair
flutter-ota keys --save     # persist public key into config
```

---

## `rollback`
Roll a channel/platform back to a previous bundle.

| Flag | Abbr | Notes |
| --- | --- | --- |
| `--backend` | `-b` | backend provider |
| `--channel` | `-c` | channel to roll back |
| `--bundle-id` | `-i` | roll back to this specific bundle id |
| `--platform` | `-p` | platform filter |

---

## `console`
Open the backend console / dashboard.

| Flag | Notes |
| --- | --- |
| `--open` | open in browser |

---

## `doctor`
Validate the local environment and backend connectivity.

| Flag | Abbr | Notes |
| --- | --- | --- |
| `--backend` | `-b` | backend to check |

---

## `fingerprint`
Compute the build fingerprint hash used by `UpdateStrategy.fingerprint` targeting.

| Flag | Abbr | Default | Notes |
| --- | --- | --- | --- |
| `--source` | `-s` | `./dist` | directory to fingerprint |

---

## `storage`
Inspect / delete raw storage objects. Subcommands: `list`, `delete`.

| Subcommand | Flags |
| --- | --- |
| `storage list` | `-b/--backend`, `--prefix` |
| `storage delete` | `-b/--backend`, `--uri` |

---

## Next
- [Configuration](configuration.md) — env vars, `.env`, resolution order, secrets policy
- [Developer Guide](developer-guide.md) — end-to-end workflow
- [Backends](backends.md) — per-backend setup details
