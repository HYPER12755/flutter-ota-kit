import 'package:flutter_ota_kit_plugin_core/src/create_storage_plugin.dart';
import 'package:flutter_ota_kit_plugin_core/src/types.dart';
import 'package:test/test.dart';

class _MockNodeProfile implements NodeStorageProfile {
  @override
  Future<Map<String, String>> upload(String key, String filePath) async => {
    'storageUri': 'mock://$key',
  };

  @override
  Future<bool> exists(String storageUri) async => true;

  @override
  Future<void> delete(String storageUri) async {}

  @override
  Future<void> downloadFile(String storageUri, String filePath) async {}

  @override
  Future<List<StorageObject>> listObjects([String? prefix]) async => [];

  @override
  Future<void> deleteObjects(List<String> keys) async {}
}

class _MockRuntimeProfile implements RuntimeStorageProfile {
  @override
  Future<Map<String, String>> getDownloadUrl(String storageUri) async => {
    'url': 'https://example.com/$storageUri',
  };

  @override
  Future<String?> readText(String storageUri) async => 'content';
}

void main() {
  group('createNodeStoragePlugin', () {
    test('creates a storage plugin with node profile', () {
      final factory = createNodeStoragePlugin<String>(
        name: 'testStorage',
        supportedProtocol: 'mock://',
        factory: (config) => _MockNodeProfile(),
      );
      final plugin = factory('cfg');
      expect(plugin.name, 'testStorage');
      expect(plugin.supportedProtocol, 'mock://');
      expect(plugin.profiles.hasNode, isTrue);
      expect(plugin.profiles.hasRuntime, isFalse);
    });

    test('factory is lazy — not called until profile method invoked', () async {
      var called = false;
      final factory = createNodeStoragePlugin<String>(
        name: 'testStorage',
        supportedProtocol: 'mock://',
        factory: (config) {
          called = true;
          return _MockNodeProfile();
        },
      );
      final plugin = factory('cfg');
      expect(called, isFalse);
      // Calling a method on the profile triggers the factory
      await plugin.profiles.node!.exists('uri');
      expect(called, isTrue);
    });

    test('upload calls hook after completion', () async {
      var hookCalled = false;
      final factory = createNodeStoragePlugin<String>(
        name: 'testStorage',
        supportedProtocol: 'mock://',
        factory: (config) => _MockNodeProfile(),
      );
      final plugin = factory(
        'cfg',
        StoragePluginHooks(
          onStorageUploaded: () async {
            hookCalled = true;
          },
        ),
      );
      await plugin.profiles.node!.upload('key', '/path');
      expect(hookCalled, isTrue);
    });

    test('without hook, upload works fine', () async {
      final factory = createNodeStoragePlugin<String>(
        name: 'testStorage',
        supportedProtocol: 'mock://',
        factory: (config) => _MockNodeProfile(),
      );
      final plugin = factory('cfg');
      final result = await plugin.profiles.node!.upload('key', '/path');
      expect(result['storageUri'], 'mock://key');
    });

    test('multiple method calls use same cached underlying profile', () async {
      var callCount = 0;
      final factory = createNodeStoragePlugin<String>(
        name: 'testStorage',
        supportedProtocol: 'mock://',
        factory: (config) {
          callCount++;
          return _MockNodeProfile();
        },
      );
      final plugin = factory('cfg');
      // First method call triggers factory
      await plugin.profiles.node!.exists('uri');
      expect(callCount, 1);
      // Second method call reuses the same cached profile
      await plugin.profiles.node!.exists('uri2');
      expect(callCount, 1);
    });
  });

  group('createRuntimeStoragePlugin', () {
    test('creates a storage plugin with runtime profile', () {
      final factory = createRuntimeStoragePlugin<String>(
        name: 'testRuntime',
        supportedProtocol: 'mock://',
        factory: (config) => _MockRuntimeProfile(),
      );
      final plugin = factory('cfg');
      expect(plugin.name, 'testRuntime');
      expect(plugin.profiles.hasNode, isFalse);
      expect(plugin.profiles.hasRuntime, isTrue);
    });

    test('runtime profile delegates correctly', () async {
      final factory = createRuntimeStoragePlugin<String>(
        name: 'testRuntime',
        supportedProtocol: 'mock://',
        factory: (config) => _MockRuntimeProfile(),
      );
      final plugin = factory('cfg');
      final url = await plugin.profiles.runtime!.getDownloadUrl(
        'mock://file.zip',
      );
      expect(url['url'], contains('file.zip'));
    });
  });

  group('createUniversalStoragePlugin', () {
    test('creates a storage plugin with both profiles', () {
      final factory = createUniversalStoragePlugin<String>(
        name: 'testUniversal',
        supportedProtocol: 'mock://',
        factory: (config) =>
            (node: _MockNodeProfile(), runtime: _MockRuntimeProfile()),
      );
      final plugin = factory('cfg');
      expect(plugin.name, 'testUniversal');
      expect(plugin.profiles.hasNode, isTrue);
      expect(plugin.profiles.hasRuntime, isTrue);
    });

    test('both profiles work independently', () async {
      final factory = createUniversalStoragePlugin<String>(
        name: 'testUniversal',
        supportedProtocol: 'mock://',
        factory: (config) =>
            (node: _MockNodeProfile(), runtime: _MockRuntimeProfile()),
      );
      final plugin = factory('cfg');

      final nodeResult = await plugin.profiles.node!.upload('k', '/p');
      expect(nodeResult, isNotEmpty);

      final runtimeUrl = await plugin.profiles.runtime!.getDownloadUrl(
        'mock://file',
      );
      expect(runtimeUrl, isNotEmpty);
    });

    test('factory is lazy', () async {
      var called = false;
      final factory = createUniversalStoragePlugin<String>(
        name: 'testUniversal',
        supportedProtocol: 'mock://',
        factory: (config) {
          called = true;
          return (node: _MockNodeProfile(), runtime: _MockRuntimeProfile());
        },
      );
      final plugin = factory('cfg');
      expect(called, isFalse);
      // Calling a method on the node profile triggers the factory
      await plugin.profiles.node!.exists('uri');
      expect(called, isTrue);
    });
  });
}
