# flutter_ota_kit_supabase

Supabase backend for [flutter_ota_kit](https://github.com/HYPER12755/flutter_ota_kit).
Implements the bundle **database** (PostgREST `bundles` table) and **storage**
(signed URLs) used both by the `flutter-ota` CLI and by the Flutter SDK's
`FlutterPatcher.configureSupabase(...)`.

## What's inside

- `supabaseDatabase` / `SupabaseDatabaseConfig` — read/update bundles over the
  Supabase REST (PostgREST) API.
- `supabaseStorage` / `SupabaseStorageConfig` / `parseSupabaseStorageUri` —
  resolve presigned download URLs.
- Edge-function variants: `supabaseEdgeFunctionDatabase`,
  `supabaseEdgeFunctionStorage` (extra security boundary via a Supabase Edge
  Function instead of direct client access).
- `SupabaseClientFactory` / `createSupabaseHttpClient` — test seams / custom
  HTTP clients.
- `SupabaseServiceRoleConfig` — holds the service-role or anon key with a
  `resolveKey()` helper.

## Configuration (environment)

| Variable | Purpose |
| --- | --- |
| `SUPABASE_URL` | Project REST URL (`https://<ref>.supabase.co`). |
| `SUPABASE_ANON_KEY` | Public anon key (RLS-protected reads). |
| `SUPABASE_SERVICE_ROLE_KEY` | Service-role key (migrations / writes). |
| `SUPABASE_BUCKET` | Storage bucket holding patch artifacts. |
| `SUPABASE_BASE_PATH` | Optional prefix for stored objects. |
| `SUPABASE_DATABASE_URL` | Connection string for migrations (alternative). |

## Usage (Flutter SDK)

```dart
import 'package:flutter_ota_kit/flutter_ota_kit.dart';

FlutterPatcher.configureSupabase(SupabaseUpdateConfig(
  supabaseUrl: 'https://<ref>.supabase.co',
  anonKey: '<anon>',
  bucket: 'bundles',
  channel: 'production',
  platform: Platform.android,
  updateStrategy: UpdateStrategy.appVersion,
  appVersion: '1.0.0',
));
```

See [doc/backends.md](https://github.com/HYPER12755/flutter_ota_kit/blob/main/doc/backends.md).

## License

MIT.
