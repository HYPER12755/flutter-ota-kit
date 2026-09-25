import 'types.dart';

/// Check whether a storage plugin provides a node profile.
bool isNodeStoragePlugin(StoragePlugin plugin) => plugin.profiles.hasNode;

/// Check whether a storage plugin provides a runtime profile.
bool isRuntimeStoragePlugin(StoragePlugin plugin) => plugin.profiles.hasRuntime;

/// Assert that a storage plugin provides a node profile.
void assertNodeStoragePlugin(StoragePlugin plugin) {
  if (!isNodeStoragePlugin(plugin)) {
    throw StateError(
      '${plugin.name} does not implement the node storage profile '
      'for protocol "${plugin.supportedProtocol}".',
    );
  }
}

/// Assert that a storage plugin provides a runtime profile.
void assertRuntimeStoragePlugin(StoragePlugin plugin) {
  if (!isRuntimeStoragePlugin(plugin)) {
    throw StateError(
      '${plugin.name} does not implement the runtime storage profile '
      'for protocol "${plugin.supportedProtocol}".',
    );
  }
}
