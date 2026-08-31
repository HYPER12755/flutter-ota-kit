import 'package:flutter/services.dart';
import 'package:restart_app/restart_app.dart';

/// MethodChannel constants and thin wrappers for talking to the Android native layer.
class PatcherChannel {
  PatcherChannel._();

  static const MethodChannel channel = MethodChannel('flutter_ota_kit');

  /// Persists the Dart-side config to native (SharedPreferences). On the next cold
  /// start the native side reads this config during `Application.attachBaseContext`
  /// to verify signatures and load the patch.
  static Future<void> saveConfig({
    required String publicKeyBase64,
    required int maxCrashCount,
    required bool strictSignature,
    required List<String> loaderFieldCandidates,
    required bool loaderFallbackHeuristic,
  }) async {
    await channel.invokeMethod<void>('saveConfig', {
      'publicKeyBase64': publicKeyBase64,
      'maxCrashCount': maxCrashCount,
      'strictSignature': strictSignature,
      'loaderFieldCandidates': loaderFieldCandidates,
      'loaderFallbackHeuristic': loaderFallbackHeuristic,
    });
  }

  /// Called at the very start of Dart `init`: marks "booting" (it cross-checks the
  /// native `attachBaseContext` marker as a safety net).
  static Future<void> markBooting() async {
    await channel.invokeMethod<void>('markBooting');
  }

  /// Called after the first Dart frame renders -> resets the circuit-breaker counter.
  static Future<void> reportBootSuccess() async {
    await channel.invokeMethod<void>('reportBootSuccess');
  }

  /// Reports an uncaught Dart exception during the boot phase. The native side treats
  /// it like an `ApplicationExitInfo` REASON_CRASH: `crash_count += 1`, and once the
  /// threshold is reached it trips the circuit breaker, deletes the patch, and
  /// blacklists it.
  ///
  /// When called: only inside the "verifyAfter window" (between the first frame
  /// rendering and `verifyAfter` seconds later), triggered by the
  /// `PlatformDispatcher.onError` / `FlutterError.onError` hooks installed by
  /// `FlutterPatcher.init`. Business exceptions after the window closes do not call
  /// this method.
  static Future<void> reportDartBootError(String message) async {
    await channel.invokeMethod<void>('reportDartBootError', {
      'message': message,
    });
  }

  /// Download + verify signature + write atomically (atomic swap). Takes effect on
  /// the next cold start.
  ///
  /// The native side returns `Map{ok, error, message}`, deserialized by the caller
  /// via `PatchApplyResult.fromNative`.
  static Future<Object?> applyPatch(Map<String, dynamic> patch) async {
    return channel.invokeMethod<Object?>('applyPatch', patch);
  }

  /// Deletes the current patch + resets the circuit-breaker flag.
  static Future<void> rollback() async {
    await channel.invokeMethod<void>('rollback');
  }

  /// The currently installed patch version (null / empty when none installed).
  static Future<String?> currentVersion() async {
    return channel.invokeMethod<String>('currentVersion');
  }

  /// Diagnostics from the last cold-start patch load.
  ///
  /// The native side returns `Map?` (see `BootDiagnosticStore`), deserialized by the
  /// caller via `PatchBootDiagnostic.fromNative`; `null` means it was never recorded.
  static Future<Map<dynamic, dynamic>?> lastBootDiagnostic() async {
    return channel.invokeMethod<Map<dynamic, dynamic>?>('lastBootDiagnostic');
  }

  /// Absolute path to a plugin-writable cache directory, used for internal staging by
  /// `applyPatchBytes`. Isolated from the existing `PatchManager.patchDir` (one is
  /// temporary staging, the other is the final patch).
  static Future<String?> cacheDir() async {
    return channel.invokeMethod<String>('cacheDir');
  }

  /// The host APK's versionCode (uses `longVersionCode` on API 28+). The native side
  /// returns -1 (INVALID_VERSION_CODE) on failure.
  static Future<int?> appVersionCode() async {
    final v = await channel.invokeMethod<int>('appVersionCode');
    if (v == null || v < 0) return null;
    return v;
  }

  /// The device's preferred ABI, so the server can serve ABI-specific patches.
  static Future<String?> deviceAbi() async {
    return channel.invokeMethod<String>('deviceAbi');
  }

  /// The local blacklist of patches known to "crash on install". The native side
  /// returns `List<Map>`, deserialized by the caller via `BlacklistEntry.fromNative`.
  static Future<List<dynamic>?> blacklist() async {
    return channel.invokeMethod<List<dynamic>>('blacklist');
  }

  /// Clears the blacklist. Use with care: normally only called during debugging.
  static Future<void> clearBlacklist() async {
    await channel.invokeMethod<void>('clearBlacklist');
  }

  /// Immediately restarts the whole App process (so a forced update takes effect).
  ///
  /// Uses the `restart_app` package with [RestartMode.process], which on Android
  /// starts a fresh launch activity and then terminates the current process
  /// (`exit(0)`). This true cold restart is required so the patched `libapp.so`
  /// and assets are reloaded on the next launch. Without the process kill, only
  /// the Flutter engine would be recreated with the old, already-mapped library.
  ///
  /// On non-Android this is a no-op handled upstream by `FlutterPatcher.restart`.
  static Future<void> restartApp() async {
    await Restart.restartApp(mode: RestartMode.process);
  }
}
