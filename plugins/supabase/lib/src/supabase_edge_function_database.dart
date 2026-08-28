/// Faithful port of hot-updater `plugins/supabase/src/supabaseEdgeFunctionDatabase.ts`.
library;

import 'package:flutter_patcher_plugin_core/flutter_patcher_plugin_core.dart';

import 'supabase_database.dart';

/// Config for the Supabase edge-function database plugin.
class SupabaseEdgeFunctionDatabaseConfig {
  final String supabaseUrl;
  final String supabaseServiceRoleKey;

  const SupabaseEdgeFunctionDatabaseConfig({
    required this.supabaseUrl,
    required this.supabaseServiceRoleKey,
  });
}

/// Edge-function variant of [supabaseDatabase]: builds the same database plugin
/// from a url + service-role key pair (no anon key).
DatabasePlugin Function() supabaseEdgeFunctionDatabase(
  SupabaseEdgeFunctionDatabaseConfig config, [
  DatabasePluginHooks? hooks,
]) {
  return supabaseDatabase(
    SupabaseDatabaseConfig(
      supabaseUrl: config.supabaseUrl,
      supabaseServiceRoleKey: config.supabaseServiceRoleKey,
    ),
    hooks,
  );
}
