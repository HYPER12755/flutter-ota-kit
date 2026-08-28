import 'package:flutter_patcher_core/flutter_patcher_core.dart'
    show AppUpdateAvailableInfo, Bundle, GetBundlesArgs;
import 'package:flutter_patcher_plugin_core/flutter_patcher_plugin_core.dart'
    show DatabaseBundleQueryOptions, DatabasePlugin, Paginated, StoragePlugin;
import 'package:shelf/shelf.dart' show Handler;

/// Controls which route groups are mounted (faithful to hot-updater
/// `HandlerRoutes`).
class HandlerRoutes {
  const HandlerRoutes({
    this.updateCheck = true,
    this.bundles = false,
    this.storage = false,
  });

  final bool updateCheck;
  final bool bundles;
  final bool storage;
}

/// Narrow API surface the handler needs from a database plugin
/// (plus storage-resolved `fileUrl`). Mirrors hot-updater `HandlerAPI`.
abstract class HandlerAPI {
  Future<AppUpdateAvailableInfo?> getAppUpdateInfo(GetBundlesArgs args);
  Future<Bundle?> getBundleById(String id);
  Future<Paginated<List<Bundle>>> getBundles(
    DatabaseBundleQueryOptions options,
  );
  Future<void> insertBundle(Bundle bundle);
  Future<void> updateBundleById(String id, Map<String, Object?> patch);
  Future<void> deleteBundleById(String id);
  Future<List<String>> getChannels();
}

/// Runtime Hot Updater API — a [HandlerAPI] plus the mounted [handler].
abstract class HotUpdaterAPI implements HandlerAPI {
  Handler get handler;
  String get basePath;
  String get adapterName;
}

/// Options for [createHotUpdater].
class ServerOptions {
  const ServerOptions({
    required this.database,
    this.storages = const [],
    this.basePath = '/api',
    this.routes,
  });

  final DatabasePlugin database;
  final List<StoragePlugin> storages;
  final String basePath;
  final HandlerRoutes? routes;
}

/// Thrown for client (4xx) errors; the handler maps it to HTTP 400.
class HandlerBadRequestError extends Error {
  HandlerBadRequestError(this.message);

  final String message;
}
