import 'package:flutter_patcher_core/flutter_patcher_core.dart'
    show AppUpdateAvailableInfo, Bundle, GetBundlesArgs;
import 'package:flutter_patcher_plugin_core/flutter_patcher_plugin_core.dart'
    show
        DatabaseBundleQueryOptions,
        DatabasePlugin,
        Paginated,
        StoragePlugin;

import 'server_types.dart' show HandlerAPI, HandlerBadRequestError;

/// Build the [HandlerAPI] from a database plugin and an optional storage
/// plugin. The storage runtime profile is used to resolve `fileUrl` /
/// `manifestUrl` for available updates.
HandlerAPI createHandlerAPI(DatabasePlugin database, StoragePlugin? storage) =>
    _PluginHandlerAPI(database, storage);

class _PluginHandlerAPI implements HandlerAPI {
  _PluginHandlerAPI(this._database, this._storage);

  final DatabasePlugin _database;
  final StoragePlugin? _storage;

  @override
  Future<AppUpdateAvailableInfo?> getAppUpdateInfo(GetBundlesArgs args) async {
    final update = await _database.getUpdateInfo(args);
    if (update == null) return null;

    final bundle = await _database.getBundleById(update.id);
    final storageUri = update.storageUri ?? bundle?.storageUri;
    final fileUrl =
        storageUri != null ? await _resolveFileUrl(storageUri) : null;
    final manifestUrl = bundle?.manifestStorageUri != null
        ? await _resolveFileUrl(bundle!.manifestStorageUri!)
        : null;

    return AppUpdateAvailableInfo(
      id: update.id,
      shouldForceUpdate: update.shouldForceUpdate,
      message: update.message,
      status: update.status,
      fileUrl: fileUrl,
      fileHash: update.fileHash,
      signature: bundle?.metadata?.signature,
      manifestUrl: manifestUrl,
      manifestFileHash: bundle?.manifestFileHash,
      changedAssets: null,
    );
  }

  Future<String?> _resolveFileUrl(String uri) async {
    final runtime = _storage?.profiles.runtime;
    if (runtime == null) return null;
    final res = await runtime.getDownloadUrl(uri);
    return res['fileUrl'];
  }

  @override
  Future<Bundle?> getBundleById(String id) => _database.getBundleById(id);

  @override
  Future<Paginated<List<Bundle>>> getBundles(
    DatabaseBundleQueryOptions options,
  ) =>
      _database.getBundles(options);

  @override
  Future<void> insertBundle(Bundle bundle) async {
    await _database.appendBundle(bundle);
    await _database.commitBundle();
  }

  @override
  Future<void> updateBundleById(
    String id,
    Map<String, Object?> patch,
  ) async {
    await _database.updateBundle(id, patch);
    await _database.commitBundle();
  }

  @override
  Future<void> deleteBundleById(String id) async {
    final bundle = await _database.getBundleById(id);
    if (bundle == null) {
      throw HandlerBadRequestError('Bundle not found: $id');
    }
    await _database.deleteBundle(bundle);
    await _database.commitBundle();
  }

  @override
  Future<List<String>> getChannels() => _database.getChannels();
}
