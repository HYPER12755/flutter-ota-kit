import 'types.dart';

/// Create a deploy/CLI/console storage plugin (node profile only).
StoragePlugin Function(TConfig config, [StoragePluginHooks? hooks])
createNodeStoragePlugin<TConfig>({
  required String name,
  required String supportedProtocol,
  required NodeStorageProfile Function(TConfig config) factory,
}) {
  return (TConfig config, [StoragePluginHooks? hooks]) {
    NodeStorageProfile? cached;
    NodeStorageProfile getProfile() {
      cached ??= factory(config);
      return cached!;
    }

    return _ProfiledStoragePlugin(
      name: name,
      supportedProtocol: supportedProtocol,
      nodeProfile: _WrappedNodeProfile(getProfile, hooks),
    );
  };
}

/// Create an update-check runtime storage plugin.
StoragePlugin Function(TConfig config, [StoragePluginHooks? hooks])
createRuntimeStoragePlugin<TConfig>({
  required String name,
  required String supportedProtocol,
  required RuntimeStorageProfile Function(TConfig config) factory,
}) {
  return (TConfig config, [StoragePluginHooks? hooks]) {
    RuntimeStorageProfile? cached;
    RuntimeStorageProfile getProfile() {
      cached ??= factory(config);
      return cached!;
    }

    return _ProfiledStoragePlugin(
      name: name,
      supportedProtocol: supportedProtocol,
      runtimeProfile: getProfile,
    );
  };
}

/// Create a storage plugin supporting both node and runtime profiles.
StoragePlugin Function(TConfig config, [StoragePluginHooks? hooks])
createUniversalStoragePlugin<TConfig>({
  required String name,
  required String supportedProtocol,
  required ({NodeStorageProfile node, RuntimeStorageProfile runtime}) Function(
    TConfig config,
  )
  factory,
}) {
  return (TConfig config, [StoragePluginHooks? hooks]) {
    ({NodeStorageProfile node, RuntimeStorageProfile runtime})? cached;
    ({NodeStorageProfile node, RuntimeStorageProfile runtime}) getProfiles() {
      cached ??= factory(config);
      return cached!;
    }

    return _ProfiledStoragePlugin(
      name: name,
      supportedProtocol: supportedProtocol,
      nodeProfile: _WrappedNodeProfile(() => getProfiles().node, hooks),
      runtimeProfile: () => getProfiles().runtime,
    );
  };
}

/// Wraps a node profile's upload with hook callback.
class _WrappedNodeProfile implements NodeStorageProfile {
  _WrappedNodeProfile(this._delegate, this._hooks);

  final NodeStorageProfile Function() _delegate;
  final StoragePluginHooks? _hooks;

  NodeStorageProfile get _node => _delegate();

  @override
  Future<Map<String, String>> upload(String key, String filePath) async {
    final result = await _node.upload(key, filePath);
    final cb = _hooks?.onStorageUploaded;
    if (cb != null) await cb();
    return result;
  }

  @override
  Future<bool> exists(String storageUri) => _node.exists(storageUri);

  @override
  Future<void> delete(String storageUri) => _node.delete(storageUri);

  @override
  Future<void> downloadFile(String storageUri, String filePath) =>
      _node.downloadFile(storageUri, filePath);

  @override
  Future<List<StorageObject>> listObjects([String? prefix]) =>
      _node.listObjects(prefix);

  @override
  Future<void> deleteObjects(List<String> keys) => _node.deleteObjects(keys);
}

/// Storage plugin with lazy profile resolution.
class _ProfiledStoragePlugin implements StoragePlugin {
  _ProfiledStoragePlugin({
    required this.name,
    required this.supportedProtocol,
    this.nodeProfile,
    this.runtimeProfile,
  });

  @override
  final String name;
  @override
  final String supportedProtocol;
  final NodeStorageProfile? nodeProfile;
  final RuntimeStorageProfile Function()? runtimeProfile;

  @override
  StoragePluginProfiles get profiles =>
      StoragePluginProfiles(node: nodeProfile, runtime: runtimeProfile?.call());
}
