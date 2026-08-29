# Backends

`flutter_ota_kit` ships **four first-party, cloud-native backends**. They are selected on the
device with `FlutterPatcher.configureSupabase(...)` / `configurePostgres(...)` /
`configureCloudflare(...)` / `configureAws(...)`, and on the CLI with
`flutter-ota init <supabase|postgres|cloudflare|aws>` (which writes `.flutter_ota_kit/config.json`).

You can also skip the built-in sources entirely and build a `PatchInfo` yourself from your own
update / staging / auth protocol — the runtime (verification, staging, crash protection,
rollback) is identical regardless of where the patch came from.

## The plugin model

The CLI and the device SDK share one design:

- **Device SDK** — every `configureX` builds a `*UpdateSource` that performs the update check
  and returns a single `ServerUpdateResult`. The rest of the SDK only understands
  `ServerUpdateResult`, so verification, staging, crash protection, and rollback behave the
  same for all backends.
- **CLI** — `resolveBackend(config)` (in `packages/cli-tools/lib/src/backend.dart`) picks a
  database plugin + a node-storage profile per provider:

  | Backend     | Database plugin            | Storage profile            |
  |-------------|----------------------------|----------------------------|
  | supabase    | `supabaseDatabase`         | `supabaseStorage`          |
  | postgres    | `postgresDatabase`         | `postgresStorage`          |
  | cloudflare  | `d1Database`               | `r2Storage`                |
  | aws         | `s3Database`               | `s3Storage`                |

All four are first-party plugins under `plugins/`. There is no local/self-hosted server anymore.

| Backend     | Device source class        | `migrate` does                              | Storage                     | Database            |
|-------------|----------------------------|--------------------------------------------|-----------------------------|---------------------|
| supabase    | `SupabaseUpdateConfig`     | **Full**: SQL migrations + `bundles` bucket| Supabase Storage            | Postgres (Supabase) |
| postgres    | `PostgresUpdateConfig`     | Prints SQL to run manually                 | Postgres `bytea` column     | Postgres            |
| cloudflare  | `CloudflareUpdateConfig`   | Prints `wrangler` commands                | R2 (S3-compatible)          | D1 (SQLite)         |
| aws         | `AwsUpdateConfig`          | Prints AWS CLI / Terraform steps           | S3 (+ optional CloudFront)  | S3 blob DB          |

---

## Supabase (recommended, fully automated)

- `flutter-ota init supabase` writes the config; `flutter-ota migrate supabase` runs all
  migrations **and** creates the `bundles` storage bucket. Nothing else to provision.
- The device reads bundles over PostgREST and resolves a signed Storage URL directly — no
  server process.
- **Use the anon key on the device** (RLS-protected reads). Never ship the service-role key.

**CLI env vars:** `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY`,
`SUPABASE_BUCKET` (default `bundles`).

**Device:**

```dart
FlutterPatcher.configureSupabase(SupabaseUpdateConfig(
  supabaseUrl: 'https://<ref>.supabase.co',
  anonKey: '<ANON_KEY>',           // RLS-protected reads — safe to ship
  serviceRoleKey: '<SERVICE_ROLE>', // only if the device must write (rare)
  bucket: 'bundles',
  channel: 'production',
  platform: Platform.android,
  updateStrategy: UpdateStrategy.fingerprint,
  appVersion: '1.0.0',
  fingerprintHash: kBuildFingerprintHash, // baked at build time
));
```

**CLI:**

```bash
flutter-ota init supabase
flutter-ota migrate supabase
flutter-ota deploy --source dist --channel production --backend supabase \
  --key <PRIVATE_KEY_BASE64>
```

---

## Postgres

- Needs a reachable Postgres database. `migrate postgres` prints the SQL to create the
  `bundles` + `flutter_ota_kit_storage` tables — run it manually.
- Bundle metadata lives in Postgres; the artifact bytes live in a `bytea` column.
- If you do not expose the `flutter_ota_kit_storage` table over HTTP, set
  `servingBaseUrl` to a proxy that fronts it (or put a PostgREST layer in front).

**CLI env vars:** `POSTGRES_HOST`, `POSTGRES_PORT` (default 5432), `POSTGRES_DB`,
`POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_SSLMODE`.

**Device:**

```dart
FlutterPatcher.configurePostgres(PostgresUpdateConfig(
  host: 'db.example.com',
  port: 5432,
  database: 'app',
  username: 'readonly',
  password: '...',
  sslMode: 'require',
  servingBaseUrl: 'https://patches.example.com', // optional proxy in front of storage table
  channel: 'production',
  platform: Platform.android,
  updateStrategy: UpdateStrategy.fingerprint,
  appVersion: '1.0.0',
));
```

**CLI:**

```bash
flutter-ota init postgres
flutter-ota migrate postgres   # prints SQL to run manually
flutter-ota deploy --source dist --channel production --backend postgres \
  --key <PRIVATE_KEY_BASE64>
```

---

## Cloudflare (D1 + R2)

- `migrate cloudflare` prints the `wrangler d1 create` / `wrangler r2 bucket create` commands.
- Bundle metadata lives in D1 (SQLite); artifacts live in R2 (S3-compatible). Presigned R2
  URLs are resolved on the device.

**CLI env vars:** `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_D1_DATABASE_ID`, `CLOUDFLARE_API_TOKEN`,
`R2_BUCKET`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BASE_PATH` (optional),
`R2_ACCOUNT_ID` (optional, for the endpoint).

**Device:**

```dart
FlutterPatcher.configureCloudflare(CloudflareUpdateConfig(
  accountId: '<ACCOUNT_ID>',
  databaseId: '<D1_DATABASE_ID>',
  cloudflareApiToken: '<API_TOKEN>',
  bucketName: '<R2_BUCKET>',
  accessKeyId: '<R2_ACCESS_KEY_ID>',
  secretAccessKey: '<R2_SECRET_ACCESS_KEY>',
  basePath: 'bundles',          // optional key prefix
  channel: 'production',
  platform: Platform.android,
  updateStrategy: UpdateStrategy.fingerprint,
  appVersion: '1.0.0',
));
```

**CLI:**

```bash
flutter-ota init cloudflare
flutter-ota migrate cloudflare  # prints wrangler commands
flutter-ota deploy --source dist --channel production --backend cloudflare \
  --key <PRIVATE_KEY_BASE64>
```

---

## AWS (S3)

- `migrate aws` prints the S3 bucket + DB setup (AWS CLI / Terraform). Bundle metadata lives
  in an S3-backed blob "database"; artifacts live in S3, optionally fronted by CloudFront.

**CLI env vars:** `AWS_BUCKET`, `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
`AWS_ENDPOINT` (optional), `AWS_BASE_PATH` (optional), `AWS_SESSION_TOKEN` (optional),
`AWS_CLOUDFRONT_DISTRIBUTION_ID` (optional).

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
  updateStrategy: UpdateStrategy.fingerprint,
  appVersion: '1.0.0',
));
```

**CLI:**

```bash
flutter-ota init aws
flutter-ota migrate aws      # prints S3 + DB setup
flutter-ota deploy --source dist --channel production --backend aws \
  --key <PRIVATE_KEY_BASE64>
```

---

## Target a specific version / fingerprint

Every `configureX` accepts `appVersion` (semver target) **or** `fingerprintHash`
(build-fingerprint target) — not both. `UpdateStrategy.fingerprint` is recommended for
Android (matches `Build.FINGERPRINT` at runtime so only matching builds receive a patch).

## Force vs. normal updates

`ServerUpdateResult.shouldForceUpdate` (set with `flutter-ota deploy --force` / the bundle
`force` flag) makes the SDK apply immediately via `applyUpdate` → `restart`, bypassing the
next-cold-start wait. `checkAndApplyUpdates()` handles both cases automatically.

## See also
- [Configuration](configuration.md) — per-backend environment variables and the secrets policy
- [CLI Reference](cli-reference.md) — `migrate` / `deploy` / `bundle` flags for each backend
- [Developer Guide](developer-guide.md) — end-to-end workflow
- [Getting Started](getting-started.md) — pick a backend and go
