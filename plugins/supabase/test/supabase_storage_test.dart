import 'dart:io' as io;

import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart';
import 'package:flutter_ota_kit_supabase/flutter_ota_kit_supabase.dart';
import 'package:test/test.dart';

import 'mock_supabase_client.dart';

late Store store;
late FakeStorageBucket bucket;
late SupabaseClientLike client;
late StoragePlugin storage;
late NodeStorageProfile node;
late RuntimeStorageProfile runtime;

void main() {
  setUp(() {
    store = Store();
    bucket = FakeStorageBucket();
    client = createMockSupabaseClient(store: store, bucket: bucket);
    storage = supabaseStorage(
      SupabaseStorageConfig(
        bucketName: 'updates',
        supabaseUrl: 'https://example.supabase.co',
        supabaseAnonKey: 'anon-key',
        clientFactory: (_, __) => client,
      ),
    );
    node = storage.profiles.node!;
    runtime = storage.profiles.runtime!;
  });

  group('supabaseStorage node.exists', () {
    test('returns true for existing, signable objects', () async {
      bucket.existsData = true;
      bucket.signedUrlData = 'https://example.supabase.co/signed-url';
      final result = await node.exists(
        'supabase-storage://updates/assets/sha256/fi/file-hash.png',
      );
      expect(result, isTrue);
      expect(bucket.existsCalls, ['assets/sha256/fi/file-hash.png']);
      expect(bucket.createSignedUrlCalls, ['assets/sha256/fi/file-hash.png']);
    });

    test('returns false when object is missing', () async {
      bucket.existsData = false;
      bucket.existsError = 'Object not found';
      final result = await node.exists(
        'supabase-storage://updates/assets/sha256/fi/file-hash.png',
      );
      expect(result, isFalse);
      expect(bucket.createSignedUrlCalls, isEmpty);
    });

    test('rejects existing objects that are not signable', () async {
      bucket.existsData = true;
      bucket.signedUrlError = 'Object not found';
      await expectLater(
        node.exists(
          'supabase-storage://updates/assets/sha256/fi/file-hash.png',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains(
              'Failed to generate download URL for '
              '"assets/sha256/fi/file-hash.png": Object not found',
            ),
          ),
        ),
      );
      expect(bucket.createSignedUrlCalls, hasLength(1));
    });

    test('rejects a different bucket', () async {
      await expectLater(
        node.exists('supabase-storage://other/assets/sha256/fi/file-hash.png'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Bucket name mismatch: expected "updates"'),
          ),
        ),
      );
      expect(bucket.existsCalls, isEmpty);
    });
  });

  group('supabaseStorage runtime.getDownloadUrl', () {
    test('batches concurrent signed URL requests', () async {
      final paths = List.generate(20, (i) => 'assets/sha256/file-$i.png');
      final results = await Future.wait(
        paths.map(
          (p) => runtime.getDownloadUrl('supabase-storage://updates/$p'),
        ),
      );
      expect(
        results,
        paths
            .map((p) => {'fileUrl': 'https://example.supabase.co/3600/$p'})
            .toList(),
      );
      expect(bucket.createSignedUrlsCalls, hasLength(1));
      expect(bucket.createSignedUrlsCalls.first, paths);
    });

    test('surfaces non-missing signed URL errors', () async {
      bucket.signedUrlError = 'Storage API failed';
      await expectLater(
        runtime.getDownloadUrl(
          'supabase-storage://updates/assets/sha256/fi/file-hash.png',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains(
              'Failed to generate download URL for '
              '"assets/sha256/fi/file-hash.png": Storage API failed',
            ),
          ),
        ),
      );
      expect(bucket.createSignedUrlsCalls, hasLength(1));
    });

    test(
      'decodes percent-encoded object keys before signing and removing',
      () async {
        const uri =
            'supabase-storage://updates/'
            'assets/bootsplash/logo-ios%402x.png';
        final url = await runtime.getDownloadUrl(uri);
        expect(url, {
          'fileUrl':
              'https://example.supabase.co/3600/'
              'assets/bootsplash/logo-ios@2x.png',
        });
        expect(bucket.createSignedUrlsCalls.first, [
          'assets/bootsplash/logo-ios@2x.png',
        ]);

        await node.delete(uri);
        expect(bucket.removeCalls.first, ['assets/bootsplash/logo-ios@2x.png']);
      },
    );
  });

  group('supabaseStorage node.upload', () {
    test('returns storageUri for a signable upload', () async {
      final dir = await io.Directory.systemTemp.createTemp('hu-supabase-');
      final uploadPath = '${dir.path}/bundle.zip';
      await io.File(uploadPath).writeAsString('bundle');
      bucket.uploadData = {'fullPath': 'updates/bundles/bundle.zip'};

      final result = await node.upload('bundles', uploadPath);
      expect(result, {
        'storageUri': 'supabase-storage://updates/bundles/bundle.zip',
      });
      expect(bucket.uploadCalls, ['bundles/bundle.zip']);
      expect(bucket.createSignedUrlCalls, ['bundles/bundle.zip']);

      await dir.delete(recursive: true);
    });
  });
}
