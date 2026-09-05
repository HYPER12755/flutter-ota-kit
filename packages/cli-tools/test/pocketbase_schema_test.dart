import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_ota_kit_cli/flutter_ota_kit_cli.dart';
import 'package:test/test.dart';

/// Minimal in-process HTTP server that simulates a PocketBase admin API.
class _MockPocketBase {
  _MockPocketBase._(this._server, this.baseUrl);

  final HttpServer _server;
  final String baseUrl;
  final List<String> createdCollections = [];
  List<String> existingCollections = const ['admins'];
  bool authCalled = false;
  String? lastAuthEmail;

  static Future<_MockPocketBase> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final mock = _MockPocketBase._(server, 'http://127.0.0.1:${server.port}');
    server.listen(mock._handle);
    return mock;
  }

  Future<void> stop() async {
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    if (path == '/api/admins/auth-with-password') {
      authCalled = true;
      final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
      lastAuthEmail = body['identity'] as String?;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'token': 'mock-token'}));
      await req.response.close();
      return;
    }
    if (path == '/api/collections' && req.method == 'GET') {
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode({
          'items': [
            for (final n in existingCollections) {'name': n},
          ],
        }),
      );
      await req.response.close();
      return;
    }
    if (path == '/api/collections' && req.method == 'POST') {
      final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
      createdCollections.add(body['name'] as String? ?? '?');
      req.response.statusCode = 200;
      req.response.write(jsonEncode({'id': 'mock'}));
      await req.response.close();
      return;
    }
    req.response.statusCode = 404;
    await req.response.close();
  }
}

void main() {
  late _MockPocketBase mock;
  setUp(() async {
    mock = await _MockPocketBase.start();
  });
  tearDown(() async {
    await mock.stop();
  });

  test(
    'schema installer creates the three collections on a fresh PB',
    () async {
      final installer = PocketBaseSchemaInstaller(
        url: mock.baseUrl,
        adminEmail: 'admin@x.com',
        adminPassword: 'secret',
      );
      final result = await installer.install();
      expect(mock.authCalled, isTrue);
      expect(mock.lastAuthEmail, 'admin@x.com');
      expect(result.created, containsAll(['bundles', 'channels', 'audit_log']));
      expect(result.skipped, isEmpty);
      expect(
        mock.createdCollections,
        containsAll(['bundles', 'channels', 'audit_log']),
      );
    },
  );

  test('schema installer skips collections that already exist', () async {
    mock.existingCollections = ['bundles', 'channels', 'audit_log'];
    final installer = PocketBaseSchemaInstaller(
      url: mock.baseUrl,
      adminEmail: 'admin@x.com',
      adminPassword: 'secret',
    );
    final result = await installer.install();
    expect(result.skipped, containsAll(['bundles', 'channels', 'audit_log']));
    expect(result.created, isEmpty);
    expect(mock.createdCollections, isEmpty);
  });
}
