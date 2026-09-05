import 'package:flutter_ota_kit_postgres/flutter_ota_kit_postgres.dart';
import 'package:test/test.dart';

void main() {
  group('Postgres storage runtime', () {
    test('getDownloadUrl throws a clear error when no servingBaseUrl is set',
        () async {
      final storage = postgresStorage(
        PostgresStorageConfig(
          db: PostgresConfig(
            host: 'mock',
            database: 'mock',
            username: 'u',
            password: 'p',
          ),
          // servingBaseUrl intentionally omitted.
        ),
      );
      final node = storage.profiles.node!;
      // Use a dummy storageUri just to exercise the runtime path.
      expect(
        () => storage.profiles.runtime!
            .getDownloadUrl('postgres://bundles/abc/zip'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('servingBaseUrl'),
          ),
        ),
      );
      // The node profile must still work because it goes through the DB.
      expect(node, isNotNull);
    });

    test('getDownloadUrl builds an http url when servingBaseUrl is set',
        () async {
      final storage = postgresStorage(
        PostgresStorageConfig(
          db: PostgresConfig(
            host: 'mock',
            database: 'mock',
            username: 'u',
            password: 'p',
          ),
          servingBaseUrl: 'https://cdn.example.com',
        ),
      );
      final url = (await storage.profiles.runtime!
              .getDownloadUrl('postgres://bundles/abc/zip'))['fileUrl'];
      expect(url, 'https://cdn.example.com/bundles/abc/zip');
    });
  });
}
