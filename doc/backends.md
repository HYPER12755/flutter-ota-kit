# Backends

`flutter_ota_kit` ships **five first-party backends** — four cloud-native
(Supabase / Postgres / Cloudflare / AWS) and one self-hosted
(PocketBase). On the device, you select one with
`FlutterPatcher.configureSupabase(...)` / `configurePostgres(...)` /
`configureCloudflare(...)` / `configureAws(...)` /
`configurePocketBase(...)`. On the CLI, `flutter-ota init <backend>`
writes `.flutter_ota_kit/config.json` and the generated setup file.

You can also skip the built-in sources entirely and build a
`ServerUpdateResult` yourself from your own update / staging / auth
protocol — the runtime (verification, staging, crash protection,
rollback) is identical regardless of where the patch came from.

---

## Choosing a backend

This is a quick decision tree. Skip ahead to the per-backend sections
once you've picked.

| You have... | Pick |
|-------------|------|
| A Supabase project, or want zero provisioning | **Supabase** (fully automated) |
| A Postgres database handy, no cloud account | **Postgres** (run 2 SQL files) |
| Cloudflare Workers / R2 stack | **Cloudflare** (D1 + R2) |
| AWS account, want IAM-controlled access | **AWS** (S3 + DynamoDB) |
| Nothing, want a single-binary self-hosted option | **PocketBase** (~15MB Go binary) |
| Custom protocol / update flow | Build your own (see [Custom update source](api-reference.md#custom-update-source)) |

**My recommendation for first-time users:** Supabase if you have an
account, PocketBase if you don't. Both have the shortest setup-to-deploy
distance.

---

## The plugin model

The CLI and the device SDK share one design:

- **Device SDK** — every `configureX` builds a `*UpdateSource` that
  performs the update check and returns a single `ServerUpdateResult`.
  The rest of the SDK only understands `ServerUpdateResult`, so
  verification, staging, crash protection, and rollback behave the
  same for all 5 backends.
- **CLI** — `resolveBackend(config)` (in
  `packages/cli-tools/lib/src/backend.dart`) picks a database plugin +
  a node-storage profile per provider:

| Backend     | Database plugin             | Storage profile     | Required at migrate time?       |
|-------------|-----------------------------|---------------------|---------------------------------|
| supabase    | `supabaseDatabase`          | `supabaseStorage`   | **Yes** — fully automated       |
| postgres    | `postgresDatabase`          | `postgresStorage`   | Run 2 SQL files manually        |
| cloudflare  | `d1Database`                | `r2Storage`         | Run `wrangler` commands         |
| aws         | `s3Database`                | `s3Storage`         | Run AWS CLI / Terraform steps   |
| pocketbase  | `pocketbaseDatabase`       | `pocketbaseStorage` | **Yes** — fully automated       |

All five are first-party plugins under `plugins/`. The PocketBase plugin
is unique in that the CLI also ships a prebuilt PB binary that it can
download and run on your behalf — see [`pocketbase`](cli-reference.md#pocketbase).

There is also a **web console** (`flutter-ota console`) that gives you
a UI to view, edit, and deploy bundles via the sidecar server. It's
backend-agnostic and works with all 5.

---

## Supabase (recommended, fully automated)

The most "just works" option if you already use Supabase or want
zero-friction provisioning.

- **`flutter-ota init supabase`** writes the config.
- **`flutter-ota migrate supabase`** runs all SQL migrations **and**
  creates the `bundles` storage bucket. Nothing else to provision.
- The device reads bundles over PostgREST and resolves a signed
  Storage URL directly — no server process.

**Use the anon key on the device** (RLS-protected reads). Never ship
the service-role key.

| Pros | Cons |
|------|------|
| Fully automated migration | Vendor lock-in (Supabase APIs) |
| Free tier works for small apps | RLS mistakes can leak bundles |
| Realtime updates built in (if you want them later) | Storage egress costs at scale |
| Postgres if you outgrow Supabase's API | — |

**CLI env vars:** `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`,
`SUPABASE_ANON_KEY`, `SUPABASE_BUCKET` (default `bundles`).

**Device:**

```dart
FlutterPatcher.configureSupabase(SupabaseUpdateConfig(
  supabaseUrl: 'https://<ref>.supabase.co',
  anonKey: '<ANON_KEY>',             // RLS-protected reads — safe to ship
  serviceRoleKey: '<SERVICE_ROLE>',   // only if the device must write (rare)
  bucket: 'bundles',
  channel: 'production',
  platform: Platform.android,
  updateStrategy: UpdateStrategy.appVersion,
  appVersion: '1.0.0',
));
```

**CLI:**

```bash
flutter-ota init supabase
flutter-ota migrate supabase
flutter-ota deploy -b supabase -s dist -c production -p android \
  --target-app-version 1.0.0 --force
```

---

## Postgres

Pick this if you already have a Postgres database handy and don't
need a cloud provider.

- Needs a reachable Postgres database.
- `migrate postgres` prints the SQL to create the `bundles` and
  `flutter_ota_kit_storage` tables — run it manually.
- Bundle metadata lives in Postgres; the artifact bytes live in a
  `bytea` column.
- If you do not expose the `flutter_ota_kit_storage` table over
  HTTP, set `servingBaseUrl` to a proxy that fronts it (or put a
  PostgREST layer in front).

| Pros | Cons |
|------|------|
| Full SQL access — you can JOIN against your own tables | Bytes are in DB (more rows = more storage) |
| No cloud dependency | `migrate` is manual (no auto-apply) |
| Easy to back up (pg_dump) | `bytea` download URL needs a proxy |

**CLI env vars:** `POSTGRES_HOST`, `POSTGRES_PORT` (default 5432),
`POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_SSLMODE`,
`POSTGRES_SERVING_BASE_URL`.

**Device:**

```dart
FlutterPatcher.configurePostgres(PostgresUpdateConfig(
  host: 'db.example.com',
  port: 5432,
  database: 'app',
  username: 'readonly',
  password: '...',
  sslMode: 'require',
  servingBaseUrl: 'https://patches.example.com',  // required (proxies the bytea table)
  channel: 'production',
  platform: Platform.android,
  updateStrategy: UpdateStrategy.appVersion,
  appVersion: '1.0.0',
));
```

**CLI:**

```bash
flutter-ota init postgres
flutter-ota migrate postgres    # prints SQL; run it manually
flutter-ota deploy -b postgres -s dist -c production -p android \
  --target-app-version 1.0.0 --force
```

---

## Cloudflare (D1 + R2)

Pick this if you're already on the Cloudflare Workers / R2 stack.

- `migrate cloudflare` prints the `wrangler d1 create` /
  `wrangler r2 bucket create` commands.
- Bundle metadata lives in D1 (SQLite, distributed by Cloudflare);
  artifacts live in R2 (S3-compatible, no egress fees).
- Presigned R2 URLs are resolved on the device.

| Pros | Cons |
|------|------|
| No egress fees on R2 | D1 limits (10GB per DB, 5M writes/day) |
| Workers + R2 = same global edge network | Wrangler tooling required |
| Free tier covers most apps | D1 latency for huge `bundles` tables |

**CLI env vars:** `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_D1_DATABASE_ID`,
`CLOUDFLARE_API_TOKEN`, `R2_BUCKET`, `R2_ACCESS_KEY_ID`,
`R2_SECRET_ACCESS_KEY`, `R2_BASE_PATH` (optional), `R2_ACCOUNT_ID`
(optional, for the endpoint).

**Device:**

```dart
FlutterPatcher.configureCloudflare(CloudflareUpdateConfig(
  accountId: '<ACCOUNT_ID>',
  databaseId: '<D1_DATABASE_ID>',
  cloudflareApiToken: '<API_TOKEN>',
  bucketName: '<R2_BUCKET>',
  accessKeyId: '<R2_ACCESS_KEY_ID>',
  secretAccessKey: '<R2_SECRET_ACCESS_KEY>',
  basePath: 'bundles',                  // optional key prefix
  region: 'auto',                       // R2 uses 'auto' for global
  endpoint: null,                       // optional S3-compatible endpoint
  channel: 'production',
  platform: Platform.android,
  updateStrategy: UpdateStrategy.appVersion,
  appVersion: '1.0.0',
));
```

**CLI:**

```bash
flutter-ota init cloudflare
flutter-ota migrate cloudflare    # prints wrangler commands; run them
flutter-ota deploy -b cloudflare -s dist -c production -p android \
  --target-app-version 1.0.0 --force
```

---

## AWS (S3)

Pick this if you already have an AWS account and want IAM-controlled
access to your update infrastructure.

- `migrate aws` prints the S3 bucket + DB setup (AWS CLI /
  Terraform). The CLI does not create AWS resources automatically —
  that's an IAM decision your account owner should approve.
- Bundle metadata lives in an S3-backed blob "database"; artifacts
  live in S3, optionally fronted by CloudFront for a custom domain.

| Pros | Cons |
|------|------|
| Full IAM control (per-key policies) | Highest setup complexity |
| S3 + CloudFront = global, cheap egress | CloudFront invalidation adds latency |
| Works with AWS SSO / SAML | S3 list operations can be slow at scale |
| ECS / Lambda / Fargate friendly | — |

**CLI env vars:** `AWS_BUCKET`, `AWS_REGION`, `AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY`, `AWS_ENDPOINT` (optional), `AWS_BASE_PATH`
(optional), `AWS_SESSION_TOKEN` (optional, for STS), and
`AWS_CLOUDFRONT_DISTRIBUTION_ID` (optional, custom domain).

**Device:**

```dart
FlutterPatcher.configureAws(AwsUpdateConfig(
  bucketName: '<BUCKET>',
  region: 'us-east-1',
  accessKeyId: '<ACCESS_KEY_ID>',
  secretAccessKey: '<SECRET_ACCESS_KEY>',
  basePath: 'bundles',                 // optional key prefix
  endpoint: null,                     // optional (e.g. MinIO)
  sessionToken: null,                 // optional (STS)
  cloudfrontDistributionId: null,     // optional custom domain
  channel: 'production',
  platform: Platform.android,
  updateStrategy: UpdateStrategy.appVersion,
  appVersion: '1.0.0',
));
```

**CLI:**

```bash
flutter-ota init aws
flutter-ota migrate aws          # prints S3 + DB setup
flutter-ota deploy -b aws -s dist -c production -p android \
  --target-app-version 1.0.0 --force
```

---

## PocketBase (self-hosted, single binary)

The newest backend and the easiest to get started with if you have no
cloud account. PocketBase is a ~15MB Go binary that bundles SQLite,
auth, file storage, an admin UI, and a REST API.

- The CLI **downloads** PB on first `pocketbase install` (or you can
  point at your own PB instance).
- The CLI's `pocketbase serve` starts a local PB, installs the
  flutter_ota_kit schema, and stays in the foreground.
- Bundle metadata lives in a PB `bundles` collection; artifacts live
  in PB file storage (per-record files, served via signed download
  URLs).

| Pros | Cons |
|------|------|
| Single binary, no Docker, no DB | Single-machine (no clustering) |
| Free (MIT) | Admin UI runs on the same process as the API |
| Admin UI built in (Dashboard) | No realtime sync (yet) |
| JS hooks for custom logic | You operate the server yourself |
| Runs anywhere (Raspberry Pi, VM, Docker) | — |

**CLI env vars:** `POCKETBASE_URL`, `POCKETBASE_ADMIN_EMAIL`,
`POCKETBASE_ADMIN_PASSWORD`, `POCKETBASE_BUNDLES_COLLECTION`
(default `bundles`), `POCKETBASE_BUCKET` (default `bundles`).

**Device:**

```dart
FlutterPatcher.configurePocketBase(PocketBaseUpdateConfig(
  url: 'http://pb.example.com',
  adminEmail: 'admin@example.com',     // PB admin (not a user) account
  adminPassword: '...',
  bundlesCollection: 'bundles',         // name of the PB collection
  bundlesBucket: 'bundles',            // name of the PB file storage bucket
  channel: 'production',
  platform: Platform.android,
  updateStrategy: UpdateStrategy.appVersion,
  appVersion: '1.0.0',
));
```

**CLI — local PB (the easy way):**

```bash
# Download PB (one-time, ~15MB)
flutter-ota pocketbase install

# Start it (installs the schema on first start)
POCKETBASE_ADMIN_EMAIL=admin@local.dev POCKETBASE_ADMIN_PASSWORD=secret \
  flutter-ota pocketbase serve --port 8090
```

Then in your project:

```bash
# .env
POCKETBASE_URL=http://127.0.0.1:8090
POCKETBASE_ADMIN_EMAIL=admin@local.dev
POCKETBASE_ADMIN_PASSWORD=secret

flutter-ota init pocketbase
flutter-ota deploy -b pocketbase -s dist -c production -p android \
  --target-app-version 1.0.0 --force
```

**CLI — remote PB (the production way):**

Point `POCKETBASE_URL` at your own PB instance (self-hosted, in a VM,
or in a container) and skip the CLI's `pocketbase install/serve` —
just `init pocketbase` and `deploy`.

---

## Target by version or fingerprint

Every `configureX` accepts **either** `appVersion` (semver target) **or**
`fingerprintHash` (build-fingerprint target) — not both.

- **`UpdateStrategy.appVersion`** (recommended for most apps): the
  backend keeps only bundles whose `target_app_version` is
  semver-compatible with the reported version. Mismatch → no bundle
  returned.
- **`UpdateStrategy.fingerprint`** (recommended for staged rollouts):
  the backend keeps only bundles whose `target_fingerprint_hash` matches
  the device's runtime build fingerprint. Use this when you need to
  target a specific binary build (e.g. for a closed beta of a specific
  store release).

```dart
// appVersion strategy (semver)
FlutterPatcher.configureSupabase(SupabaseUpdateConfig(
  // ...
  updateStrategy: UpdateStrategy.appVersion,
  appVersion: '1.0.0',
));

// fingerprint strategy (content-hash)
FlutterPatcher.configureSupabase(SupabaseUpdateConfig(
  // ...
  updateStrategy: UpdateStrategy.fingerprint,
  fingerprintHash: kBuildFingerprintHash,   // baked at build time
));
```

The build fingerprint is computed by the CLI's `fingerprint` command
and passed to `deploy --fingerprint-hash`. See
[CLI Reference → fingerprint](cli-reference.md#fingerprint).

---

## Force vs. normal updates

`ServerUpdateResult.shouldForceUpdate` (set with `flutter-ota deploy --force`)
makes the SDK apply the update immediately via
`applyUpdate` → `restart`, bypassing the next-cold-start wait.
`checkAndApplyUpdates()` handles both cases automatically.

The forced-update path is what enables zero-click updates with
`autoApplyUpdates: true`. See
[Beginner Guide → Step 9](beginner-guide.md) for the full UX flow.

---

## See also

- [Configuration](configuration.md) — per-backend env vars, secrets policy
- [CLI Reference](cli-reference.md) — `migrate` / `deploy` / `bundle` flags
- [Developer Guide](developer-guide.md) — full workflow reference
- [Architecture](architecture.md) — internals, signing, advanced config
- [Getting Started](getting-started.md) — pick a backend and go
- [Production Playbook](production-playbook.md) — staged rollout, emergency rollback
