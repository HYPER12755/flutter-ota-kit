import 'package:flutter_patcher_core/flutter_patcher_core.dart'
    show AppUpdateAvailableInfo, Bundle, GetBundlesArgs;
import 'package:flutter_patcher_plugin_core/flutter_patcher_plugin_core.dart'
    show DatabaseBundleQueryOptions, Paginated;
import 'package:shelf/shelf.dart' show Handler;

import 'hot_updater_api.dart' show createHandlerAPI;
import 'server_handler.dart' show createHandler;
import 'server_types.dart' show HandlerAPI, HotUpdaterAPI, ServerOptions;

/// Create a runnable Hot Updater server API from a database plugin and
/// optional storage plugin(s). Faithful port of hot-updater
/// `createHotUpdater.ts` / `createHotUpdaterCore.ts` (minus the Node-only
/// Prisma/Drizzle schema-readiness adapters, which are unnecessary for our
/// plugin-based architecture).
HotUpdaterAPI createHotUpdater(ServerOptions options) {
  final storage = options.storages
      .where((s) => s.profiles.node != null && s.profiles.runtime != null)
      .firstOrNull;
  final api = createHandlerAPI(options.database, storage);
  final handler = createHandler(
    api,
    basePath: options.basePath,
    routes: options.routes,
    storage: storage,
  );
  return _HotUpdaterAPI(
    basePath: options.basePath,
    adapterName: options.database.name,
    handler: handler,
    api: api,
  );
}

class _HotUpdaterAPI implements HotUpdaterAPI {
  _HotUpdaterAPI({
    required this.basePath,
    required this.adapterName,
    required this.handler,
    required HandlerAPI api,
  }) : _api = api;

  @override
  final String basePath;
  @override
  final String adapterName;
  @override
  final Handler handler;
  final HandlerAPI _api;

  @override
  Future<AppUpdateAvailableInfo?> getAppUpdateInfo(GetBundlesArgs args) =>
      _api.getAppUpdateInfo(args);

  @override
  Future<Bundle?> getBundleById(String id) => _api.getBundleById(id);

  @override
  Future<Paginated<List<Bundle>>> getBundles(
    DatabaseBundleQueryOptions options,
  ) =>
      _api.getBundles(options);

  @override
  Future<void> insertBundle(Bundle bundle) => _api.insertBundle(bundle);

  @override
  Future<void> updateBundleById(String id, Map<String, Object?> patch) =>
      _api.updateBundleById(id, patch);

  @override
  Future<void> deleteBundleById(String id) => _api.deleteBundleById(id);

  @override
  Future<List<String>> getChannels() => _api.getChannels();
}
