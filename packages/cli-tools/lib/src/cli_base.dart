import 'package:args/args.dart';

import 'backend.dart';
import 'config.dart';
import 'pack.dart';
import 'ui/ui.dart';

export 'runner.dart';

/// Run [body], mapping errors to a non-zero exit code with a clean message.
Future<int> runGuarded(Future<void> Function() body) async {
  try {
    await body();
    return 0;
  } on StateError catch (e) {
    err(e.message);
    return 1;
  } on PackException catch (e) {
    err(e.message);
    return e.exitCode;
  } catch (e) {
    err(e.toString());
    return 1;
  }
}

/// Resolve a [Backend] from config, or return the injected override (tests).
Backend requireBackend(FlutterPatcherConfig? config, {Backend? override}) {
  if (override != null) return override;
  if (config == null) {
    throw StateError(
      'No configuration found. Run `flutter_patcher init` or set '
      'SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY.',
    );
  }
  return resolveBackend(config);
}

/// Apply a `--backend` flag override to the loaded config.
///
/// Returns `cfg` unchanged when no `--backend` flag is present. When the flag
/// is set but no config exists yet, a minimal config with that provider is
/// created (so env-driven credentials still resolve).
FlutterPatcherConfig? effectiveConfig(
  FlutterPatcherConfig? cfg,
  ArgResults argResults,
) {
  final backend = argResults['backend'] as String?;
  if (backend == null) return cfg;
  final base = cfg ??
      FlutterPatcherConfig(
        provider: backend,
        supabase: const SupabaseConfigJson(),
        postgres: const PostgresConfigJson(),
        cloudflare: const CloudflareConfigJson(),
        aws: const AwsConfigJson(),
      );
  return base.copyWith(provider: backend);
}
