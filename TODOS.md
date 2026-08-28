# flutter_patcher — Master Roadmap (hot-updater parity)

> Goal: a fully self-hosted OTA ("code push") platform for **Flutter Android**,
> feature-parity with [hot-updater](https://github.com/gronxb/hot-updater),
> translated to Dart/Flutter. Everything lives in this one monorepo.
> Reference checkout: `/home/user/reference/hot-updater` (read-only study copy).
>
> Rules: Android only (skip iOS). Every phase battle-tested against real
> infrastructure before moving on. Small batches, verified steps.
>
> **Current state (updated 2026-08-28):** core + plugin-core COMPLETE (1,065
> tests). All four cloud backend plugins COMPLETE (supabase 20, postgres 11,
> cloudflare 20, aws 10 tests — Lambda@Edge removed, see Phase 3.12). **Phase 4
> shelf server COMPLETE** (`packages/server`, `createHotUpdater`/`createHandler`/
> `HandlerAPI`, 6 integration tests, clean analyze).
>
> **Device SDK — direct cloud device sources (NEW):** `lib/flutter_patcher.dart`
> now wires `configureSupabase` / `configurePostgres` / `configureCloudflare` /
> `configureAws`, each talking DIRECTLY to its backend (no local server) and
> reusing the same backend plugins `deploy` uses. `ServerUpdateSource` (self-hosted
> server) is retained only for `standalone`. **Supabase verified end-to-end on
> emulator-5554** (hasUpdate=true, signed absolute patch URL, apply ok=true, anon
> key + RLS). postgres/cloudflare/aws device sources implemented + `dart analyze`
> clean but NOT yet live-verified (need cloud creds).
>
> **Cleanup:** mock/local in-memory servers removed (`packages/server/bin/server.dart`,
> `bin/mock_server.dart`, `standalone_server.dart`); Lambda@Edge storage removed
> (dead/unwired). **`migrate`** is now per-backend (`migrations/<backend>/` dirs;
> supabase via mgmt-API or postgres, postgres via direct postgres, cloudflare →
> wrangler, aws/standalone short-circuit); dry-run verified for all 5. Server
> `changedAssets` now resolved from the bundle manifest.
>
> **Pending:** live-verify postgres/cloudflare/aws device sources (need creds);
> standalone new approach (awaiting user plan); Postgres serving proxy (infra).

---

## Architecture translation table

| hot-updater (TS/RN)                    | flutter_patcher (Dart/Flutter)                     |
|----------------------------------------|----------------------------------------------------|
| root monorepo (pnpm workspaces)        | this repo (root = device SDK, like packages/react-native) |
| `packages/core`                        | `packages/core/` → `flutter_patcher_core`          |
| `plugins/plugin-core`                  | `plugins/plugin-core/` → `flutter_patcher_plugin_core` (NOTE: under `plugins/`, not `packages/`) |
| `packages/react-native`                | root `lib/` + `android/` (the device SDK)          |
| `packages/server`                      | `packages/server/` → `flutter_patcher_server`      |
| `packages/hot-updater` + `cli-tools`   | `bin/` + `packages/cli-tools/`                     |
| `packages/console` (React web UI)      | `packages/console/` → Flutter web                  |
| `plugins/*`                            | `plugins/` mirroring same names                    |
| `plugins/supabase/supabase/migrations` | `plugins/supabase/supabase/migrations/*.sql`       |
| `plugins/postgres/sql` PL/pgSQL RPCs   | `plugins/postgres/sql/*.sql`                       |
| `examples/`                            | `example/` (existing demo app)                     |
| bsdiff bundle diffing                  | deferred (phase 9)                                 |

## Core data model (must match hot-updater exactly)

- Bundle id = **UUIDv7**, ordering by lexicographic compare (time-sortable).
- `NIL_UUID = 00000000-0000-0000-0000-000000000000` rollback sentinel.
- Platform enum: `android` (ios skipped).
- Status machine: server returns `UPDATE` / `ROLLBACK`; client derives
  `UP_TO_DATE`. ROLLBACK forces `shouldForceUpdate=true`.
- Bundle fields: id, platform, should_force_update, enabled, file_hash,
  git_commit_hash, message, channel (default `production`), storage_uri,
  target_app_version (semver range) XOR fingerprint_hash, metadata jsonb,
  manifest_storage_uri, manifest_file_hash, asset_base_storage_uri,
  rollout_cohort_count (0–1000, default 1000), target_cohorts text[].
- `bundle_patches` table: id "<bundleId>:<baseBundleId>", FKs, hashes,
  patch_storage_uri, order_index.
- Constraint: `(target_app_version IS NOT NULL) OR (fingerprint_hash IS NOT NULL)`.

---

## Phase 1 — `packages/flutter_patcher_core` (pure Dart) ✅ COMPLETE

- [x] `types.dart`: Bundle, Platform, UpdateStatus, UpdateInfo, GetBundlesArgs, etc.
- [x] `uuid.dart`: UUIDv7 generator + NIL_UUID + lexicographic ordering.
- [x] `rollout.dart`: cohort eligibility, coprime/modular-inverse rollout position.
- [x] `semver.dart`: `semverSatisfies(range, version)` — 819 tests including verkit ground truth.
- [x] Unit tests: 819 passing.

## Phase 2 — Supabase backend (first real backend)

- [ ] `supabase/migrations/` numbered SQL files mirroring hot-updater's
      evolution but landing directly at 0.31-equivalent schema:
      init → channels → fingerprints/storage_uri → file_hash in RPCs →
      rollout cohorts → manifest/diff columns → RLS hardening.
- [ ] RPCs: `get_target_app_version_list`, `get_update_info_by_app_version`,
      `get_update_info_by_fingerprint_hash`, `is_cohort_eligible` (+ helpers),
      `get_channels`, `semver_satisfies` — return shapes identical to
      hot-updater `(id, should_force_update, message, status, storage_uri, file_hash)`.
- [ ] Storage: private bucket `flutter-patcher-storage`, key layout
      `bundles/<id>/patch.zip`, `bundles/<id>/manifest.json`,
      signed URL minting (3600s).
- [ ] Deploy path A (no custom server): device SDK calls Supabase RPC directly.
- [x] Deploy path B: edge function / shelf server exposing hot-updater-compatible
      REST (`/api/fingerprint/:platform/:hash/:channel/:min/:cur`, `/api/app-version/...`).
      Done: `packages/server` (`createHotUpdater`/`createHandler`) + `Dockerfile` +
      `DEPLOY.md`; Supabase Edge Function TS mirror at
      `plugins/supabase/supabase/edge-functions/index.ts`. SQL migrations copied
      and verified aligned (see Phase 9 backends).
- [ ] **Battle test**: apply migrations to real project via SUPABASE_PAT,
      insert bundles, hit RPCs from example app, verify UPDATE/ROLLBACK/cohort paths.

## Phase 3 — Plugin system (Dart contracts) ← IN PROGRESS (Batch 4e complete)

- [x] `DatabasePlugin` interface: getChannels, getBundleById, getBundles, appendBundle,
      updateBundle, deleteBundle, commitBundle, getUpdateInfo; Unit-of-Work overlay.
- [x] `StoragePlugin` interface: supportedProtocol, node/runtime profiles.
- [x] `createDatabasePlugin`: double-curried factory with lazy init + UoW integration.
- [x] `createBlobDatabasePlugin`: blob-based database (update.json per channel/platform/target).
- [x] `getUpdateInfo` + `resolveUpdateInfoFromBundles`: app-version + fingerprint strategies.
- [x] Storage layout helpers: asset/bundle/legacy layouts, space normalization.
- [x] Query helpers: `bundleMatchesQueryWhere`, `sortBundles`, `paginateBundles`.
- [x] Unit of Work: `BundleUnitOfWork`, store, request state, seed/overlay.
- [x] Generate min bundle ID (zeroed-random UUIDv7).
- [x] 246 plugin-core tests + 819 core tests = 1,065 total passing.
- [x] Plugin-core package COMPLETE: all 22 TS source files ported to Dart (Batch 4a–4e).

## Phase 3.5 — Supabase plugin (Dart port) ← COMPLETE (Batch 5)

- [x] Supabase service-role config + client-factory seam (`SupabaseServiceRoleConfig.clientFactory`).
- [x] `supabase_database.dart`: full port of `supabaseDatabase.ts`, `supabaseBundleMapper.ts`,
      `uuid.ts`, `appendBundleSql.ts`, `getChannelApps`, `getUpdateInfoByAppVersion`,
      `getUpdateInfoByFingerprintHash`, `getChannels`. clientFactory seam injected.
- [x] `supabase_storage.dart`: full port of `supabaseStorage.ts` — `parseStorageUri`,
      `formatObjectPath`, bundle/asset/legacy `getStorageUri`, `getDownloadUrl` (batched),
      `exists`, `upload`, `remove`, `listObjects`, `deleteObjects`; `supabaseStorage` export
      (node+runtime profiles).
- [x] `supabase_signed_url_batcher.dart`: faithful port of `supabaseSignedUrlBatcher.ts`
      (batched signed-URL minting with 500ms debounce); fixed flush bug (reassign pending map).
- [x] `supabase_edge_function_database.dart` + `supabase_edge_function_storage.dart`: edge variants.
- [x] Barrel exports: `lib/flutter_patcher_supabase.dart` + `lib/edge.dart`.
- [x] Monorepo restructure: `packages/plugin-core` → `plugins/plugin-core`; empty skeleton
      dirs created for server, cli-tools, console, test-utils, aws, bare, cloudflare, postgres,
      mock, standalone, rock, js, expo, firebase, sentry-plugin, datadog-plugin, bugsnag-plugin.
- [x] **20 supabase tests passing** (mock client + bundle mapper + database + storage), `dart analyze` clean.
- [ ] `supabase/migrations/` SQL (deferred — Phase 5 backend parity work / real Supabase).

## Phase 3.6 — Postgres plugin (Dart port) ← COMPLETE (Batch 6)

- [x] `postgres_config.dart`: `PostgresConfig` (host/port/database/user/pass/sslMode) +
      `clientFactory` seam (mirrors Supabase testability).
- [x] `postgres_client.dart`: `PostgresClientLike` interface + real `PostgresClient`
      wrapper over `package:postgres` v3 (`Connection.open`, `execute` → column maps,
      `runTx`); lazy connection open.
- [x] `postgres_bundle_mapper.dart`: faithful port of `postgres.ts` mapper
      (`mapRowToBundle` / `bundleToRowValues` / `bundleToPatchRows`).
- [x] `postgres_types.dart`: `PostgresBundleRow` / `PostgresBundlePatchRow`
      (snake_case, jsonb metadata handling).
- [x] `postgres_database.dart`: `postgresDatabase` plugin — raw-SQL `getBundleById`,
      `getBundles` (dynamic WHERE + COUNT + LIMIT/OFFSET), `getChannels`, `commitBundle`
      (transactional insert/upsert/delete with `RETURNING id`), faithful to `postgres.ts`.
- [x] `postgres_get_update_info.dart`: `getUpdateInfo` calling the PL/pgSQL RPCs
      (`get_target_app_version_list`, `get_update_info_by_app_version`,
      `get_update_info_by_fingerprint_hash`) — shares the same RPC contract as Supabase.
- [x] Barrel `lib/flutter_patcher_postgres.dart`.
- [x] **11 postgres tests passing** (mapper + getChannels/getBundles/getBundleById/
      commitBundle/getUpdateInfo) with a mock `PostgresClientLike`; `dart analyze` clean.
- [ ] SQL DDL + RPC migrations (`plugins/postgres/sql/*.sql`) — deferred to Phase 5
      (battle-test against a real Postgres).

## Phase 3.7 — Cloudflare D1 plugin (Dart port) ← COMPLETE (Batch 7)

- [x] `d1_config.dart`: `D1DatabaseConfig` (databaseId/accountId/cloudflareApiToken)
      + `clientFactory` seam (`D1ClientFactory`) for testability, mirroring
      supabase/postgres.
- [x] `d1_client.dart`: `D1ClientLike` interface + real `D1Client` over
      `package:http` (Cloudflare D1 REST `POST .../query`; flattens `result[*].results`).
- [x] `d1_bundle_mapper.dart`: `transformRowToBundle` / `bundleToPatchRows` /
      `parseMetadata` / `parseTargetCohorts` (faithful to `d1Database.ts`).
- [x] `d1_build_where.dart`: `buildWhereClause` emitting SQLite dialect
      (`?` positional params, `json_each(?)` IN clauses).
- [x] `d1_database.dart`: `d1Database` plugin (`createDatabasePlugin`) —
      `getBundleById`, `getBundles` (WHERE + COUNT + LIMIT/OFFSET), `getChannels`,
      `commitBundle` (sequential INSERT OR REPLACE / DELETE), and `getUpdateInfo`
      resolved **in-process** via `resolveUpdateInfoFromBundles`
      (NB: cloudflare D1 does NOT use SQL RPCs, unlike supabase/postgres).
- [x] Barrel `lib/flutter_patcher_cloudflare.dart`.
- [x] **11 cloudflare tests passing** (mapper + getChannels/getBundles/
      getBundleById/commitBundle/getUpdateInfo) with a mock `D1ClientLike`;
      `dart analyze` clean.
- [ ] **R2 storage plugin** (`r2Storage`/`r2S3Storage`/`r2WranglerStorage`/`r2WorkerStorage`)
      — deferred to Batch 8 (needs an S3-compatible client / signing).
- [ ] `cloudflareWorkerDatabase` (worker D1 binding variant) — deferred to Batch 9.
- [ ] D1 SQL migrations (`plugins/cloudflare/sql/*.sql`, `worker/migrations/*.sql`)
      — deferred to Phase 5.

## Phase 3.8 — Cloudflare R2 storage plugin (Dart port) ← COMPLETE (Batch 8)

- [x] `r2_config.dart`: `R2S3StorageConfig` (accountId/bucketName/accessKeyId/secretAccessKey/
      basePath/region/endpoint) + `clientFactory` seam.
- [x] `r2_s3_client.dart`: `R2S3ClientLike` interface + `R2S3Client` over `package:http`
      with **AWS Signature V4** signing (delete/put/head/get objects, presigned GET URLs,
      ListObjectsV2 parsing). Service name `r2`, region `auto`, path-style addressing.
- [x] `r2_storage_profile.dart`: `createS3StorageProfile` (node: upload/exists/delete/
      downloadFile/listObjects/deleteObjects) + `createS3RuntimeStorageProfile`
      (runtime: getDownloadUrl/readText), via `createStorageKeyBuilder`/`parseStorageUri`/
      `getContentType`.
- [x] `r2_storage.dart`: `r2Storage = createUniversalStoragePlugin<R2S3StorageConfig>`
      (`supportedProtocol: 'r2'`, node + runtime profiles) — faithful to `r2Storage.ts`.
- [x] Barrel export updated.
- [x] **4 R2 storage tests passing** (plugin metadata, node upload/exists/download/delete,
      runtime getDownloadUrl/readText(+missing→null), listObjects prefix filter) with a
      mock `R2S3ClientLike`; `dart analyze` clean. (The real SigV4 client is untested against
      live R2, as with the other backend plugins' real clients.)
- [ ] `cloudflareWorkerDatabase` (worker D1 binding variant) — deferred to Batch 9.
- [ ] D1/R2 SQL + migrations — deferred to Phase 5.

## Phase 3.9 — Cloudflare Workers `d1WorkerDatabase` (Dart port) ← COMPLETE (Batch 9)

- [x] Extracted shared `D1DatabasePlugin` (the full query/update-info logic) into
      `d1_database_plugin.dart`; both `d1Database` (REST) and `cloudflareWorkerDatabase`
      (binding) construct it from a `D1ClientLike` — no logic duplication.
- [x] `cloudflare_worker_database.dart`: `CloudflareWorkerDatabaseConfig`
      (supplies a `D1ClientLike` via `getDb`) + `cloudflareWorkerDatabase`
      (`createDatabasePlugin`, name `d1WorkerDatabase`), faithful to
      `cloudflareWorkerDatabase.ts`.
- [x] Barrel export updated (`CloudflareWorkerDatabaseConfig`, `cloudflareWorkerDatabase`).
- [x] **5 worker tests passing** (getChannels / getBundleById / commitBundle
      append→update→delete / getUpdateInfo appVersion / getUpdateInfo fingerprint)
      reusing the in-memory `MockD1Client`; `dart analyze` clean.
- [ ] D1/R2 SQL + migrations (`plugins/cloudflare/sql/*.sql`, `worker/migrations/*.sql`)
      — deferred to Phase 5 (battle-test against live Cloudflare).

## Phase 3.10 — AWS `s3Storage` (Dart port) ← COMPLETE (Batch 10a)

- [x] `plugins/aws` package created (`flutter_patcher_aws`) with `AwsS3StorageConfig`
      (bucketName/region/accessKeyId/secretAccessKey/basePath/endpoint/sessionToken
      + `clientFactory` test seam) and `applyS3RuntimeAwsConfig` (region from
      `AWS_REGION`/`AWS_DEFAULT_REGION`).
- [x] `aws_s3_client.dart`: `AwsS3ClientLike` + `AwsS3Client` — AWS SigV4 over
      `package:http`, virtual-hosted addressing (service `s3`): delete / put / head /
      get objects, listing, multi-delete (DeleteObjects batches of 1000), and
      presigned GET URLs.
- [x] `aws_storage_profile.dart` + `aws_storage.dart`: `s3Storage` via
      `createUniversalStoragePlugin` (name `s3Storage`, protocol `s3`), faithful to
      `s3Storage.ts` (node: upload/exists/delete/listObjects/deleteObjects/downloadFile;
      runtime: getDownloadUrl/readText). Bucket-mismatch guards preserved.
- [x] **4 tests passing** (plugin metadata / upload+exists+downloadFile+delete /
      runtime getDownloadUrl+readText+nil / listObjects prefix filter) via
      in-memory `MockAwsS3Client`; `dart analyze` clean.

## Phase 3.11 — AWS `s3Database` (blob/document DB over S3) ← COMPLETE (Batch 10b)

- [x] `aws_database.dart`: `S3DatabaseConfig` (bucketName/region/creds/basePath/
      cloudfrontDistributionId/shouldWaitForInvalidation/apiBasePath + `clientFactory`
      and `cloudfrontClientFactory` test seams) and `S3BlobOperations implements
      BlobOperations` (faithful port of `s3Database.ts`'s `BlobOperations`): `toStorageKey`/
      `fromStorageKey` via `createDatabaseKeyBuilder`, `listObjects`/`loadObject`/
      `uploadObject`/`deleteObject`, `S3ArchivedObjectError` + `shouldSkipLoadObjectError`,
      no-op `validateChannel`, and `invalidatePaths` → CloudFront `CreateInvalidation`.
- [x] `aws_cloudfront_client.dart`: `AwsCloudFrontClientLike` + `AwsCloudFrontClient`
      (AWS SigV4, service `cloudfront`, global region `us-east-1`): `CreateInvalidation`
      POST + optional poll-until-Completed; failures are warned-and-continued unless
      `shouldWaitForInvalidation`.
- [x] `s3Database = createBlobDatabasePlugin<S3DatabaseConfig>(...)` (name `s3Database`).
      **6 database tests passing** (commit writes `channel/platform/version/update.json`
      + invalidates CloudFront / getUpdateInfo appVersion / getBundles / deleteBundle +
      invalidate / no invalidation when distribution id omitted) via in-memory
      `MockAwsS3Client` + `MockCloudFrontClient`; `dart analyze` clean. AWS package now
      **10 tests total**.

## Phase 3.12 — AWS `s3LambdaEdgeStorage` + CloudFront signed URLs ← COMPLETE (Batch 10c)

- [x] `aws_cloudfront_signer.dart`: `cloudfrontSignedUrl` (faithful port of
      `@aws-sdk/cloudfront-signer`'s `getSignedUrl`) — RSA-SHA1 custom-policy
      signed URL, with `parseRsaPrivateKeyPem` (PKCS#1 + PKCS#8) and
      `verifyCloudfrontSignedUrl` (test seam). Added `pointycastle` + `asn1lib`.
- [x] `aws_ssm_client.dart`: minimal SSM `GetParameter` client (SigV4, service
      `ssm`) so the `ssmParameterName`/`ssmRegion` private-key source works
      (faithful to hot-updater's `applySsmRuntimeAwsConfig`).
- [x] `with_cloudfront_signed_url.dart`: `WithCloudFrontSignedUrlOptions` +
      `withCloudFrontSignedUrl` — wraps a storage plugin so `s3://` download URLs
      become CloudFront signed URLs (delegating non-`s3://` to the base).
- [x] `aws_lambda_edge_storage.dart`: `AwsLambdaEdgeStorageConfig` (S3 config +
      CF options) + `s3LambdaEdgeStorage`/`awsLambdaEdgeStorage` (faithful to
      `s3LambdaEdgeStorage.ts`/`awsLambdaEdgeStorage.ts`).
- [x] **4 tests passing** (signer round-trip+verify / lambda-edge signs `s3://`
       URLs and verifies / `publicBaseUrl` resolver / plugin name suffix) with
       runtime-generated RSA key pairs; `dart analyze` clean. AWS package now
       **14 tests total**.
- [!] **REMOVED (2026-08-28):** `aws_lambda_edge_storage.dart` + its test were
       deleted as dead/unwired code per user direction — `awsLambdaEdgeStorage`/
       `s3LambdaEdgeStorage` were never wired into `resolveBackend`, so the AWS
       package is now **10 tests** (s3Storage 4 + s3Database 6).

## Phase 3.13 — AWS SQL/DynamoDB migrations — PENDING (Phase 5)

- [ ] `s3Storage`/`s3Database` SQL-equivalent setup + live-account battle-testing
      (DynamoDB not used — `s3Database` is the blob/document store) deferred to
      Phase 5 alongside the other plugins' migrations.

## Module inventory — hot-updater → flutter_patcher (status)

Source of truth: `/home/user/reference/hot-updater/{packages,plugins}` (read-only).

### Packages
| hot-updater package            | flutter_patcher                        | Status |
|--------------------------------|----------------------------------------|--------|
| `packages/core`                | `packages/core` (`flutter_patcher_core`)        | DONE (819 tests) |
| `packages/plugin-core`         | `plugins/plugin-core` (`flutter_patcher_plugin_core`) | DONE (246 tests) |
| `packages/react-native`        | root `lib/`+`android/` (device SDK)   | DONE (ported from RN) |
| `packages/hot-updater`         | root main SDK / `bin/` CLI entry      | DONE (lib) · CLI deferred (user: end) |
| `packages/android-helper`      | (native Gradle/Java in `android/`)    | N/A (RN-specific helper) |
| `packages/apple-helper`        | —                                      | SKIP (iOS) |
| `packages/bsdiff`              | native diff (defer to Phase 9)        | PENDING |
| `packages/server`              | `packages/server` (`flutter_patcher_server`, shelf) | DONE (Phase 4) |
| `packages/cli-tools`           | `packages/cli-tools` (`flutter_patcher_cli`) | DONE (Phase 6, 15 tests) |
| `packages/console`             | `packages/console` (Flutter web)      | SKELETON (Phase 7) |
| `packages/test-utils`          | `packages/test-utils`                 | SKELETON |

### Plugins
| hot-updater plugin     | flutter_patcher                  | Status |
|------------------------|----------------------------------|--------|
| `plugin-core`          | DONE                             | DONE |
| `supabase`             | DONE (20 tests)                  | DONE |
| `postgres`             | `plugins/postgres`               | DONE (11 tests)                            |
| `cloudflare`           | `plugins/cloudflare`             | DONE (d1Database + R2 + worker, 20 tests) · migrations PENDING |
| `aws`                  | `plugins/aws`                    | DONE (s3Storage + s3Database + s3LambdaEdgeStorage, 14 tests) · migrations PENDING |
| `firebase`             | `plugins/firebase`               | OUT OF SCOPE (user decision) |
| `bare`                 | `plugins/bare`                   | PENDING (no-cloud self-host) |
| `standalone`           | `plugins/standalone`             | DONE (REST client + server routes; CLI `--backend standalone`) |
| `mock`                 | `plugins/mock`                   | OUT OF SCOPE (user decision) |
| `rock`                 | `plugins/rock`                   | PENDING (investigate — small) |
| `sentry-plugin`        | `plugins/sentry-plugin`          | PENDING (observability) |
| `datadog-plugin`       | `plugins/datadog-plugin`         | PENDING (observability) |
| `bugsnag-plugin`       | `plugins/bugsnag-plugin`         | PENDING (observability) |
| `js`                   | —                                | SKIP (RN JS runtime) |
| `expo`                 | —                                | SKIP (Expo/RN) |

> Note: only `supabase` was ported so far. The other backend plugins above are
> real parity targets (Phase 9). The server/CLI/console packages are skeleton dirs
> pending their phases. The remaining device-SDK work (Phase 5) and edge-function
> deploy paths are also outstanding.

## CLI tool — PRE-PLAN (design only; NOT implemented yet — per user)

- **Language/runtime: Dart, wrapped by npm.** The whole project is Dart/Flutter, so
  the CLI is a Dart executable (hot-updater's `@hot-updater/cli-tools` is TS/npm — we
  do not carry that over). It lives at `packages/cli-tools/` with a `bin/flutter_patcher.dart`
  entry, uses `package:args` `CommandRunner` for subcommand dispatch, and **reuses the
  Dart backend plugins directly** (no logic duplicated in TS). To satisfy the user's
  `npm -g i flutter-patcher` requirement, an npm-publishable wrapper package lives at
  `npm/flutter-patcher/` (bin launcher + `dart compile exe` postinstall + shipped
  supabase migrations) that installs the single native binary globally. No TS copied.
- **Command surface (mirrors hot-updater `packages/hot-updater/src/bin`):**
  `init`, `bundle` (create/pack update), `channel` (get/set/list), `deploy`,
  `rollback`, `promote`, `fingerprint`, `doctor` (+`doctorInfrastructure`),
  `generate` (emit SQL migrations: `generate-standalone-sql`, `generate-prisma-schema`),
  `migrate`, `keys`, `storage` (list/delete GC), `console` (launch web console),
  `patch` (re-pack), `config`. RN-only `buildNative`/`runNative` → adapt to Flutter
  `build`/`run` hooks or drop.
- **Config:** `flutter_patcher.config.dart` + `defineConfig(...)` helper (Dart, not JS).
- **Provider wiring:** supabase first (env-driven), then postgres/cloudflare/aws/bare.
- **Deferred:** implement only when the user says "do the CLI".

## Phase 4 — Server API parity (Dart shelf)

- [x] Routes (basePath `/api`): GET version; update-check fingerprint +
      app-version routes with cohort segment; bundles CRUD (gated);
      channels; cursor pagination identical semantics.
- [x] Response compatibility: legacy `null` body vs `{"status":"UP_TO_DATE"}`
      behind SDK-version header (`createHotUpdater` SDK-version check `>=0.31.0`).
- [x] `createHotUpdater` + `createHandler` + `HandlerAPI` (+ `HotUpdaterAPI`)
      with in-memory demo `bin/server.dart`; 6 passing integration tests
      (d1Database mock + in-memory storage), clean analyze.
- [ ] Dockerfile + deploy docs; smoke tests with real HTTP client.

## Phase 5 — Device SDK upgrades (root package lib/+android/)

- [x] **Backend wiring (NEW this pass):** device SDK now supports BOTH a self-hosted
       `ServerUpdateSource` (`packages/client`) AND **direct cloud device sources**
       for every cloud backend — `SupabaseUpdateSource`, `PostgresUpdateSource`,
       `CloudflareUpdateSource`, `AwsUpdateSource` (in `lib/src/`), each wired via
       `FlutterPatcher.configureSupabase|Postgres|Cloudflare|Aws(...)` + dispatched
       in `checkForUpdate()`. Each source reuses the same backend plugins `deploy`
       uses (e.g. `supabaseDatabase`/`supabaseStorage`, `postgresDatabase`/
       `postgresStorage`, `d1Database`/`r2Storage`, `s3Database`/`s3Storage`) — no
       server required for cloud backends. `ServerUpdateSource` (self-hosted server)
       retained for `standalone`. `PatchInfo`/apply-result types live in
       `flutter_patcher_core`.
- [x] **Supabase verified end-to-end on emulator-5554:** `hasUpdate=true`, signed
       absolute `patchUrl`, `apply result ok=true` (anon key + RLS policies).
- [ ] **postgres/cloudflare/aws device sources:** implemented + `dart analyze` clean,
       but NOT yet live-verified on-device (need cloud credentials / local Postgres).
- [ ] Update strategies: send `_updateStrategy=fingerprint|appVersion`,
      fingerprintHash baked at build (gradle meta-data), appVersion passthrough.
- [ ] Channel support: build-time channel, runtime switch + resetChannel,
      isolation keys per fingerprint/channel.
- [ ] Cohort: derive from ANDROID_ID hash, send as param.
- [ ] Install state machine parity: staging/stable slots, verificationPending,
      crashed-history.json (max 10), launch-report.json, recovery marker;
      watchdog for hangs.
- [ ] Min bundle id handling (BuildConfig at build time).
- [ ] Progress phases aligned (download/finalize/completed).
- [ ] **Battle test**: real device, kill -9 style crashes, forced rollbacks,
      channel switches, cohort pinning.

## Phase 6 — CLI (`dart run flutter_patcher:<command>`) ← COMPLETE

Commands (parity set, all implemented): `init`, `build` (pack a release APK into a
device-ready `dist/patch.zip`, **all ABIs included** so one bundle serves every
device arch), `deploy`, `bundle list|delete|promote`, `rollback`, `channel`
       (get/set/list), `fingerprint`, `doctor`, `migrate` (per-backend: supabase via
       mgmt-API or postgres, postgres via direct postgres, cloudflare → wrangler,
       aws/standalone short-circuit; `--dry-run` lists the backend's own SQL dir),
       `config` (get/set/list, persisted to `.flutter_patcher.json`), `keys`
(Ed25519 keygen, priv/pub base64), `console` (launches console URL), `patch`
(re-pack existing source), `mock_server` (in-memory local server). Flags mirror
hot-updater UX (e.g. `deploy --channel --message --platform --target-app-version
--target-fingerprint --key --storage-uri --enabled`).
- [x] Implementation in `packages/cli-tools/` (`flutter_patcher_cli`): `config.dart`
       (resolve supabase/storage config w/ env override), `backend.dart`, `util.dart`
       (zip/fingerprint/gitCommitHash), `sign.dart` (Ed25519 via `cryptography`),
       `operations.dart` (deployBundle/listBundles/deleteBundle/promoteBundle/
       rollbackChannel/listChannels/getChannel), `cli_base.dart`, `pack.dart`
       (`packPatch` — multi-ABI APK→`patch.zip`, shared by `bin/pack.dart` and the
       `build` command), and the command files. `dart analyze` clean.
- [x] **Signing contract fixed (CRITICAL):** `deployBundle` now writes `fileHash` as a
       plain **MD5 hex** (device SDK rejects anything else — the old `sig:`-prefixed
       hash was never a valid MD5), signs `ed25519(md5Hex UTF-8 bytes)` with the deploy
       key, and stores the raw base64 signature in `BundleMetadata.signature` (round-trips
       through the `metadata` JSON, so **no DB migration needed**). `generateEd25519KeyPair`
       emits an **X.509 SPKI** base64 public key (what the Android `SignatureVerifier`
       expects), and `ed25519Verify` tolerates a SPKI prefix. The shelf server
       (`packages/server`) now emits `signature` on `AppUpdateAvailableInfo` from the
       bundle's `metadata.signature`. Verified by a CLI test: deploy → assert `fileHash`
       matches `^[0-9a-f]{32}$`, then `ed25519Verify(md5Hex, signature, spkiPub) == true`.
- [x] **Deploy artifact fixed (CRITICAL):** the old `deploy` re-zipped the whole `dist/`
       dir, producing a **nested zip the device cannot parse**. Now, if `--source` points
       at a `.zip` it uploads that directly; otherwise if the source dir contains a
       `patch.zip` (e.g. produced by `build`) it uploads *that*; else it zips the dir.
       An end-to-end CLI test builds a multi-ABI APK → `build` → `deploy` → downloads the
       stored artifact and asserts it is the genuine `patch.zip` (root `manifest.json` +
       per-ABI `libapp.so`, **not** a nested `dist/patch.zip`).
- [x] **6 integration tests** against an in-memory `MockSupabaseClient` (deploy →
       upload+register, bundle list, bundle delete, promote, rollback-disables-latest,
       channel list), plus standalone-backend tests (deploy+sign, build+deploy chain) and
       `packPatch` unit/integration tests — **15 CLI tests passing**.
- [x] Provider wiring: supabase first (env-driven `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`,
       or `--url`/`--service-role-key`), storage uri `--storage-uri`.
- [x] npm wrapper at `npm/flutter-patcher/`: `bin/flutter-patcher.js` launcher + `scripts/postinstall.js`
      (`dart compile exe` build / prebuilt-binary resolution) + shipped `migrations/supabase/*.sql`,
      so `npm -g i flutter-patcher` installs a working global `flutter-patcher` binary.
- [x] **Multi-backend support (NEW):** `resolveBackend` + all commands (`deploy`, `bundle`,
      `rollback`, `channel`, `doctor`, `migrate`) accept `--backend supabase|postgres|cloudflare|aws`
      (flag > `FLUTTER_PATCHER_BACKEND`/env > `provider` in `.flutter_patcher.json`). Per-backend
      config sections + env-resolution added (`resolvePostgres*Config`, `resolveCloudflare*Config`,
      `resolveAws*Config`). Added `postgresStorage` plugin (bytea table) so the postgres backend has
       storage. `dart analyze` clean; **15 CLI tests pass** — supabase + backend-lifecycle
       (postgres/cloudflare/aws/standalone) + deploy-signing + build→deploy chain +
       `packPatch` integration tests, using in-memory mock clients exercising
       deploy → upload+register → listBundles → getChannel → promote → rollback →
       delete, plus storage upload/download.
- [ ] Config file `flutter_patcher.config.dart` + `defineConfig(...)` helper (Dart config module)
      — deferred; current `config` subcommand edits `.flutter_patcher.json` (JSON) instead.

## Phase 7 — Console (Flutter web)

- [ ] Bundle table (filter by channel/platform/enabled), deploy dialog,
      promote/rollback actions, channel manager, rollout slider.
- [ ] Talks to Phase 4 server API only (same contract).

## Phase 8 — Security & ops

- [x] Ed25519 signature path: `keys` CLI generates a keypair (X.509 SPKI public key,
       base64) and `deploy --key <privB64>` signs the bundle (`ed25519(md5Hex UTF-8)`)
       stored in `metadata.signature`; the shelf server surfaces it on the update
       response; the Android `SignatureVerifier` verifies it (API≥33 real, API<33 strict).
       See Phase 6 for the contract fix.
- [ ] RLS policies review, service-role separation docs.
- [ ] Storage GC command (listObjects/deleteObjects).

## Phase 9 — Remaining backends (FULL parity — all in scope)

> **CLI multi-backend (NEW this pass):** the `flutter_patcher` CLI now supports
> `supabase` (done earlier), `postgres`, `cloudflare`, `aws`, and `standalone`
> backends via a single `--backend` flag (or `provider` in `.flutter_patcher.json`),
> each with env/JSON config resolution and in-memory mock-backed (or
> self-hosted-server) lifecycle tests
> (deploy → upload+register → list → getChannel → promote → rollback → delete,
> plus storage upload/download). A `postgresStorage` plugin (Postgres bytea)
> was added so the postgres backend is fully self-contained. See Phase 6 for details.
> Production device-SDK end-to-end (real signed/served storage URLs) is validated
> for the D1 path via the `packages/client` e2e test; cloudflare/aws/postgres use
> their real cloud URLs in production. `standalone` talks to any server exposing
> our REST contract — the `packages/server` shelf server now additionally mounts
> admin + storage CRUD routes (`/api/bundles*`, `/api/upload`, `/api/getDownloadUrl`,
> `/api/delete`, `/api/readText`, `/api/list`, `/api/_file`) so it can act as that
> self-hosted backend.

- [x] `plugins/postgres/` — Dart client (pg-compatible) DONE (11 tests, clean
      analyze). SQL DDL copied to `plugins/postgres/sql/bundles.sql` (+ reference
      PL/pgSQL RPCs in the same dir); connection-config driven.
- [x] `plugins/cloudflare/` — D1 schema/migrations (SQLite dialect) copied to
      `plugins/cloudflare/migrations/*.sql` and verified aligned with the Dart
      `d1Database`/`cloudflareWorkerDatabase` column names; R2 storage via
      S3-compatible API DONE (4 tests); `s3LambdaEdgeStorage` + CloudFront signed
      URLs DONE (4 tests). Worker script mounting the shelf server API = deploy
      path B (Phase 4 server / Supabase edge fn parity).
- [x] `plugins/aws/` — S3 storage + blob-database (`update.json` per
       channel/platform/target layout), CloudFront invalidation hooks,
       Lambda@Edge handler equivalent (or documented Docker alternative).
       DONE (14 aws tests, clean analyze); CLI `--backend aws` wired.
- [ ] `plugins/firebase/` — Firestore database plugin + Cloud Storage storage
       plugin + Cloud Function update resolver. **OUT OF SCOPE (user decision).**
- [x] `plugins/standalone/` — REST clients (database + storage) for any
       user-hosted server implementing our API contract. DONE:
       `standaloneRepository` (`createDatabasePlugin`) + `standaloneStorage`
       (`createUniversalStoragePlugin`) with injectable `http.Client` seams;
       11 plugin unit tests (`MockClient`) + 1 server e2e test (shelf server
       admin+storage routes ↔ standalone client: deploy→upload→list→download
       →rollback) + 1 CLI backend lifecycle test. CLI `--backend standalone`
       wired (env `STANDALONE_BASE_URL` / `standalone.baseUrl`).
- [ ] `plugins/mock/` — in-memory implementations powering unit/integration tests.
       **OUT OF SCOPE (user decision).**
- [ ] Bundle diffing: content-addressed asset layout + binary diff patches
      for libapp.so/asset changes with fallback-to-archive semantics.
- [ ] Integration plugins: sentry / datadog / bugsnag hooks (deploy tagging,
      release correlation).

## Phase 10 — Deferred

- [ ] iOS support (explicitly out of scope for now).

---

## Verification discipline (applies to every phase)

1. Unit tests green locally (`dart test` in each package).
2. Example app end-to-end OTA round trip on real device before merge.
3. Public endpoint checks through studio proxy (ports 3000/8080 pattern).
4. Rollback + crash-recovery exercised, not assumed.
