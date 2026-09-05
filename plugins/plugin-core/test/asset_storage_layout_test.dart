import 'package:flutter_ota_kit_plugin_core/src/asset_storage_layout.dart';
import 'package:flutter_ota_kit_plugin_core/src/bundle_storage_layout.dart';
import 'package:flutter_ota_kit_plugin_core/src/legacy_asset_storage_layout.dart';
import 'package:test/test.dart';

void main() {
  group('assetStorageLayout', () {
    group('getAssetStorageLayout', () {
      test('classifies /assets roots as content-addressed storage', () {
        expect(
          getAssetStorageLayout('s3://bucket/assets'),
          'content-addressed',
        );
        expect(
          getAssetStorageLayout('s3://bucket/releases/assets/'),
          'content-addressed',
        );
      });

      test(
        'classifies non-/assets roots as legacy per-bundle file storage',
        () {
          expect(
            getAssetStorageLayout('s3://bucket/releases/bundle-id/files'),
            'legacy-files',
          );
        },
      );
    });

    group('getManifestAssetStoragePath', () {
      test('resolves content-addressed manifest assets by file hash', () {
        expect(
          getManifestAssetStoragePath(
            assetBaseStorageUri: 's3://bucket/assets',
            assetPath: 'index.ios.bundle.br',
            fileHash: 'abcdef',
          ),
          'sha256/ab/abcdef.br',
        );
      });

      test('resolves legacy manifest assets by manifest-relative path', () {
        expect(
          getManifestAssetStoragePath(
            assetBaseStorageUri: 's3://bucket/releases/bundle-id/files',
            assetPath: 'assets/logo.png',
            fileHash: 'abcdef',
          ),
          'assets/logo.png',
        );
      });
    });

    group('createStorageUriWithRelativePath', () {
      test('creates escaped child storage uris', () {
        expect(
          createStorageUriWithRelativePath(
            baseStorageUri: 's3://bucket/releases/assets/',
            relativePath: 'assets/icon one.png',
          ),
          's3://bucket/releases/assets/assets/icon%20one.png',
        );
      });
    });

    group('resolveManifestAssetStorageUri', () {
      test('resolves manifest asset storage uris through the layout', () {
        expect(
          resolveManifestAssetStorageUri(
            assetBaseStorageUri: 's3://bucket/assets',
            assetPath: 'assets/logo.png',
            fileHash: 'abcdef',
          ),
          's3://bucket/assets/sha256/ab/abcdef.png',
        );
      });
    });

    group('isBrotliManifestAssetPath', () {
      test('matches index.*.bundle paths', () {
        expect(isBrotliManifestAssetPath('index.ios.bundle'), isTrue);
        expect(
          isBrotliManifestAssetPath('nested/index.android.bundle'),
          isTrue,
        );
      });

      test('rejects non-index bundle paths', () {
        expect(isBrotliManifestAssetPath('main.ios.bundle'), isFalse);
      });
    });

    group('getManifestAssetDownloadPath', () {
      test('appends .br to index bundle paths', () {
        expect(
          getManifestAssetDownloadPath('index.ios.bundle'),
          'index.ios.bundle.br',
        );
        expect(
          getManifestAssetDownloadPath('nested/index.android.bundle'),
          'nested/index.android.bundle.br',
        );
      });

      test('passes through non-index bundle paths', () {
        expect(
          getManifestAssetDownloadPath('main.ios.bundle'),
          'main.ios.bundle',
        );
      });
    });
  });

  group('bundleStorageLayout', () {
    group('createBundleStorageKey', () {
      test('stores new bundle artifacts below the bundles namespace', () {
        expect(createBundleStorageKey('bundle-id'), 'bundles/bundle-id');
        expect(
          createBundleStorageKey('bundle-id', ['patches', 'base-id']),
          'bundles/bundle-id/patches/base-id',
        );
      });
    });

    group('createStorageRootUriWithPath', () {
      test('derives the shared storage root from bundle URIs', () {
        expect(
          createStorageRootUriWithPath(
            's3://bucket/releases/bundles/bundle-id/manifest.json',
            'bundle-id',
            'assets',
          ),
          's3://bucket/releases/assets',
        );
      });

      test('rejects storage URIs that do not contain the bundle id', () {
        expect(
          () => createStorageRootUriWithPath(
            'https://uploads.example.com/object',
            'bundle-id',
            'assets',
          ),
          throwsA(isA<StateError>()),
        );
      });

      test('preserves encoded storage root segments', () {
        expect(
          createStorageRootUriWithPath(
            's3://bucket/release%20files/bundles/bundle-id/manifest.json',
            'bundle-id',
            'assets/sha256',
          ),
          's3://bucket/release%20files/assets/sha256',
        );
      });
    });
  });

  group('legacyAssetStorageLayout', () {
    test('getLegacyManifestAssetStoragePath returns assetPath unchanged', () {
      expect(
        getLegacyManifestAssetStoragePath(assetPath: 'assets/logo.png'),
        'assets/logo.png',
      );
    });
  });
}
