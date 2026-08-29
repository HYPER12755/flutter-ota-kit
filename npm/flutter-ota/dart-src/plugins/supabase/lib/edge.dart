/// Edge-function entrypoint for flutter_ota_kit_supabase.
///
/// Mirrors hot-updater's `plugins/supabase/src/edge.ts`: exposes only the
/// edge-runnable variants (runtime-only database + storage plugins).
library;

export 'src/supabase_edge_function_database.dart'
    show supabaseEdgeFunctionDatabase, SupabaseEdgeFunctionDatabaseConfig;
export 'src/supabase_edge_function_storage.dart'
    show supabaseEdgeFunctionStorage, SupabaseEdgeFunctionStorageConfig;
