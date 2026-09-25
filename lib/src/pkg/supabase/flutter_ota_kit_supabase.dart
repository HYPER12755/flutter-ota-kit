/// flutter_ota_kit_supabase — Supabase backend for flutter_ota_kit.
///
/// Faithful Dart translation of hot-updater's `plugins/supabase`:
/// database + storage plugins (direct + edge-function variants) over the
/// Supabase REST (PostgREST) API.
library;

export 'src/supabase_config.dart';
export 'src/supabase_client_adapter.dart'
    show SupabaseClientLike, SupabaseClientFactory;
export 'src/supabase_client_http.dart' show createSupabaseHttpClient;
export 'src/supabase_database.dart'
    show supabaseDatabase, SupabaseDatabaseConfig;
export 'src/supabase_storage.dart'
    show supabaseStorage, SupabaseStorageConfig, parseSupabaseStorageUri;
export 'src/supabase_signed_url_batcher.dart'
    show createSupabaseSignedUrlBatcher, ResolveSignedUrl;
export 'src/supabase_edge_function_database.dart'
    show supabaseEdgeFunctionDatabase, SupabaseEdgeFunctionDatabaseConfig;
export 'src/supabase_edge_function_storage.dart'
    show supabaseEdgeFunctionStorage, SupabaseEdgeFunctionStorageConfig;
export 'src/types.dart' show SupabaseBundleRow;
export 'src/supabase_bundle_mapper.dart' show mapRowToBundle;
