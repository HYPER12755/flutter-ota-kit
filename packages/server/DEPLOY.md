# Deploying the flutter_patcher server

`packages/server` (`flutter_patcher_server`) is a faithful Dart port of
hot-updater's `packages/server` (the framework-agnostic update-check + bundle
management API). It exposes the same HTTP contract (`/api/version`,
`/api/fingerprint/...`, `/api/app-version/...`, `/api/bundles/*`) so any
hot-updater-compatible client works unchanged.

## 1. Database + storage backends

The server is backend-agnostic. You wire a `DatabasePlugin` and one or more
`StoragePlugin` via `createHotUpdater`:

| Backend      | Database plugin            | Storage plugin                 |
|--------------|----------------------------|--------------------------------|
| Supabase     | `supabaseDatabase(config)`  | `supabaseStorage(config)`      |
| Postgres     | `postgresDatabase(config)`  | (reuse Supabase/R2 storage)    |
| Cloudflare   | `d1Database(config)` / `cloudflareWorkerDatabase(config)` | `r2Storage(config)` / `s3LambdaEdgeStorage(config)` |
| AWS          | `s3Database(config)`        | `s3Storage(config)`            |

Apply the matching SQL migrations **before** running the server:

- Supabase / Postgres: `plugins/supabase/supabase/migrations/*.sql`
  (run via `supabase db push` or `psql`).
- Cloudflare D1: `plugins/cloudflare/migrations/*.sql`
  (apply with `wrangler d1 execute <db> --file=...` in order).
- Postgres raw schema: `plugins/postgres/sql/bundles.sql` (the other files in
  that dir are PL/pgSQL RPCs used by hot-updater's TS postgres plugin; the Dart
  `postgresDatabase` issues equivalent direct SQL).

## 2. Run the demo (in-memory, smoke test)

```bash
cd packages/server
dart pub get
dart run bin/server.dart            # listens on :8080 (override PORT)
curl localhost:8080/api/version
```

The demo binary uses an in-memory database + storage and is for local smoke
testing only — it does not persist bundles.

## 3. Production host app

Create a small Dart app that depends on `flutter_patcher_server` plus the
plugin(s) you chose, then wire them:

```dart
import 'package:flutter_patcher_server/flutter_patcher_server.dart';
import 'package:flutter_patcher_supabase/flutter_patcher_supabase.dart';

void main() {
  final api = createHotUpdater(ServerOptions(
    database: supabaseDatabase(SupabaseConfig(
      url: Platform.environment['SUPABASE_URL']!,
      anonKey: Platform.environment['SUPABASE_ANON_KEY']!,
      serviceRoleKey: Platform.environment['SUPABASE_SERVICE_ROLE_KEY']!,
    ))(),
    storages: [
      supabaseStorage(SupabaseStorageConfig(
        url: Platform.environment['SUPABASE_URL']!,
        serviceRoleKey: Platform.environment['SUPABASE_SERVICE_ROLE_KEY']!,
        bucket: 'bundles',
      )),
    ],
  ));
  // mount api.handler on your HTTP server / edge runtime
}
```

## 4. Docker

```bash
docker build -f packages/server/Dockerfile -t flutter-patcher-server .
docker run -p 8080:8080 -e PORT=8080 flutter-patcher-server
```

The image builds the demo binary. For production, replace `bin/server.dart`
with your host app (step 3) and rebuild.

## 5. Supabase Edge Function (alternative deploy path)

`plugins/supabase/supabase/edge-functions/index.ts` is a Deno/TypeScript edge
function that serves the same API on Supabase Edge Functions. Deploy it with
`supabase functions deploy server` (it mirrors this Dart server's contract, so
clients are interchangeable).
