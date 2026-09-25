/// Faithful port of hot-updater `plugins/supabase/src/supabaseConfig.ts`.
library;

import 'supabase_client_adapter.dart';

/// Configuration requiring either a service role key or an anon key.
class SupabaseServiceRoleConfig {
  final String supabaseUrl;
  final String? supabaseServiceRoleKey;
  final String? supabaseAnonKey;

  /// Optional test seam: a factory that builds the [SupabaseClientLike] used by
  /// the plugin. When omitted, [createSupabaseHttpClient] is used (REST API).
  /// Mirrors the TS `vi.mock("@supabase/supabase-js")` test seam.
  final SupabaseClientFactory? clientFactory;

  const SupabaseServiceRoleConfig({
    required this.supabaseUrl,
    this.supabaseServiceRoleKey,
    this.supabaseAnonKey,
    this.clientFactory,
  });

  /// Resolve the best available key — service role preferred over anon.
  String resolveKey() {
    final key = supabaseServiceRoleKey ?? supabaseAnonKey;
    if (key == null || key.isEmpty) {
      throw StateError(
        'Supabase service role key is required. Set supabaseServiceRoleKey.',
      );
    }
    return key;
  }
}
