import 'dart:convert' show utf8;
import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:crypto/crypto.dart' show Hmac, sha256;
import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart'
    show StorageObject;
import 'package:http/http.dart' show Client, Request, Response;

import 'aws_config.dart' show AwsS3StorageConfig;

/// A thin S3 client for AWS S3.
///
/// Mirrors the subset of `@aws-sdk/client-s3` used by hot-updater's
/// `s3Storage.ts`: delete / put / head / get objects, listing, multi-delete,
/// and presigned GET URLs. Requests are signed with AWS Signature V4
/// (service `s3`, virtual-hosted addressing).
abstract class AwsS3ClientLike {
  const AwsS3ClientLike();

  Future<void> deleteObject(String key);

  Future<void> deleteObjects(List<String> keys);

  Future<void> putObject(String key, List<int> body, String contentType);

  Future<bool> headObject(String key);

  Future<List<int>> getObjectAsBytes(String key);

  Future<String> getObjectAsString(String key);

  Future<String> getPresignedUrl(String key, {int expiresIn = 3600});

  Future<List<StorageObject>> listObjects([String? prefix]);
}

/// Real AWS S3 client backed by `package:http` + AWS SigV4 signing.
class AwsS3Client implements AwsS3ClientLike {
  AwsS3Client(this.config, {Client? http}) : _http = http ?? Client();

  final AwsS3StorageConfig config;
  final Client _http;

  static const String _service = 's3';

  Uri get _baseUri {
    final host =
        config.endpoint ??
        'https://${config.bucketName}.s3.${config.region}.amazonaws.com';
    return Uri.parse(host);
  }

  Uri _objectUri(String key) => _baseUri.replace(path: '/$key');

  @override
  Future<void> deleteObject(String key) async {
    final response = await _send('DELETE', _objectUri(key), body: null);
    _assertStatus(response, [200, 204], 'deleteObject');
  }

  @override
  Future<void> deleteObjects(List<String> keys) async {
    for (var offset = 0; offset < keys.length; offset += 1000) {
      final batch = keys.skip(offset).take(1000).toList();
      if (batch.isEmpty) continue;

      final xml = StringBuffer()
        ..write('<?xml version="1.0" encoding="UTF-8"?>')
        ..write('<Delete><Quiet>true</Quiet>');
      for (final key in batch) {
        xml.write('<Object><Key>${_xmlEscape(key)}</Key></Object>');
      }
      xml.write('</Delete>');

      final response = await _send(
        'POST',
        _baseUri.replace(path: '/', queryParameters: {'delete': ''}),
        body: utf8.encode(xml.toString()),
        extraHeaders: {'Content-Type': 'application/xml'},
      );
      _assertStatus(response, [200], 'deleteObjects');
    }
  }

  @override
  Future<void> putObject(String key, List<int> body, String contentType) async {
    final response = await _send(
      'PUT',
      _objectUri(key),
      body: body,
      extraHeaders: {
        'Content-Type': contentType,
        'Cache-Control': 'max-age=31536000',
      },
    );
    _assertStatus(response, [200], 'putObject');
  }

  @override
  Future<bool> headObject(String key) async {
    final uri = _objectUri(key);
    final request = Request('HEAD', uri)
      ..headers.addAll(_authHeaders('HEAD', uri, null));
    final response = await _http.send(request);
    if (response.statusCode == 404) return false;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('S3 HeadObject failed (${response.statusCode})');
    }
    return true;
  }

  @override
  Future<List<int>> getObjectAsBytes(String key) async {
    final response = await _send('GET', _objectUri(key), body: null);
    _assertStatus(response, [200], 'getObjectAsBytes');
    return response.bodyBytes;
  }

  @override
  Future<String> getObjectAsString(String key) async {
    final bytes = await getObjectAsBytes(key);
    return utf8.decode(bytes);
  }

  @override
  Future<String> getPresignedUrl(String key, {int expiresIn = 3600}) async {
    final uri = _objectUri(key);
    final now = DateTime.now().toUtc();
    final amzDate = _amzDate(now);
    final dateStamp = amzDate.substring(0, 8);
    final scope = '$dateStamp/${config.region}/$_service/aws4_request';

    final tokenParam = config.sessionToken != null
        ? {'X-Amz-Security-Token': _uriEncode(config.sessionToken!)}
        : <String, String>{};

    final params = {
      'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
      'X-Amz-Credential': '${config.accessKeyId}/$scope',
      'X-Amz-Date': amzDate,
      'X-Amz-Expires': '$expiresIn',
      'X-Amz-SignedHeaders': 'host',

      ...tokenParam,
    };
    final canonicalQuery =
        params.entries
            .map((e) => '${_uriEncode(e.key)}=${_uriEncode(e.value)}')
            .toList()
          ..sort();
    final queryString = canonicalQuery.join('&');

    const payloadHash = 'UNSIGNED-PAYLOAD';
    final canonicalHeaders = 'host:${uri.host}\n';
    final canonicalRequest =
        'GET\n${uri.path}\n$queryString\n$canonicalHeaders\nhost\n$payloadHash';
    final stringToSign = _stringToSign(amzDate, scope, canonicalRequest);
    final signingKey = _signingKey(dateStamp, config.region);
    final signature = _toHex(_hmac(signingKey, stringToSign));
    return '${uri.scheme}://${uri.host}${uri.path}?$queryString'
        '&X-Amz-Signature=$signature';
  }

  @override
  Future<List<StorageObject>> listObjects([String? prefix]) async {
    final listUri = _baseUri.replace(
      path: '/',
      queryParameters: {
        'list-type': '2',
        if (prefix != null && prefix.isNotEmpty) 'prefix': prefix,
      },
    );
    final response = await _send('GET', listUri, body: null);
    _assertStatus(response, [200], 'listObjects');
    return _parseListObjects(response.body);
  }

  // --- signing helpers -------------------------------------------------------

  Map<String, String> _authHeaders(String method, Uri uri, List<int>? body) {
    final now = DateTime.now().toUtc();
    final amzDate = _amzDate(now);
    final dateStamp = amzDate.substring(0, 8);
    final scope = '$dateStamp/${config.region}/$_service/aws4_request';
    final payloadHash = body == null ? _hashHex(const []) : _hashHex(body);

    final canonicalHeaders =
        'host:${uri.host}\n'
        'x-amz-content-sha256:$payloadHash\n'
        'x-amz-date:$amzDate\n'
        '${config.sessionToken != null ? 'x-amz-security-token:${config.sessionToken}\n' : ''}';
    final signedHeaders = config.sessionToken != null
        ? 'host;x-amz-content-sha256;x-amz-date;x-amz-security-token'
        : 'host;x-amz-content-sha256;x-amz-date';

    final canonicalRequest =
        '$method\n${uri.path}\n'
        '\n$canonicalHeaders$signedHeaders\n$payloadHash';
    final stringToSign = _stringToSign(amzDate, scope, canonicalRequest);
    final signingKey = _signingKey(dateStamp, config.region);
    final signature = _toHex(_hmac(signingKey, stringToSign));

    final headers = {
      'x-amz-date': amzDate,
      'x-amz-content-sha256': payloadHash,
      'Authorization':
          'AWS4-HMAC-SHA256 Credential=${config.accessKeyId}/$scope, '
          'SignedHeaders=$signedHeaders, Signature=$signature',
    };
    if (config.sessionToken != null) {
      headers['x-amz-security-token'] = config.sessionToken!;
    }
    return headers;
  }

  Future<Response> _send(
    String method,
    Uri uri, {
    required List<int>? body,
    Map<String, String>? extraHeaders,
  }) async {
    final request = Request(method, uri);
    request.headers.addAll(_authHeaders(method, uri, body));
    if (extraHeaders != null) request.headers.addAll(extraHeaders);
    if (body != null) request.bodyBytes = body;
    final streamed = await _http.send(request);
    return await Response.fromStream(streamed);
  }

  List<StorageObject> _parseListObjects(String xml) {
    final objects = <StorageObject>[];
    final contents = _allMatches(
      xml,
      RegExp(r'<Contents>([\s\S]*?)</Contents>'),
    );
    for (final block in contents) {
      final key = _tag(block, 'Key');
      final size = int.tryParse(_tag(block, 'Size') ?? '');
      final lastModified = _tag(block, 'LastModified');
      if (key == null) continue;
      objects.add(
        StorageObject(
          key: key,
          storageUri: 's3://${config.bucketName}/$key',
          size: size ?? 0,
          lastModifiedAt: lastModified == null
              ? null
              : DateTime.tryParse(lastModified),
        ),
      );
    }
    return objects;
  }

  // --- low-level sigv4 primitives --------------------------------------------

  List<int> _signingKey(String dateStamp, String region) {
    var key = utf8.encode('AWS4${config.secretAccessKey}');
    key = _hmac(key, dateStamp);
    key = _hmac(key, region);
    key = _hmac(key, _service);
    key = _hmac(key, 'aws4_request');
    return key;
  }

  String _stringToSign(String amzDate, String scope, String canonicalRequest) =>
      'AWS4-HMAC-SHA256\n$amzDate\n$scope\n${_hashHex(utf8.encode(canonicalRequest))}';

  // --- static utilities ------------------------------------------------------

  static String _amzDate(DateTime utc) =>
      '${utc.toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z';

  static String _uriEncode(String value) => Uri.encodeQueryComponent(value);

  static String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static Uint8List _hmac(List<int> key, String data) =>
      Hmac(sha256, key).convert(utf8.encode(data)).bytes as Uint8List;

  static String _hashHex(List<int> data) => _toHex(sha256.convert(data).bytes);

  static String _toHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static List<String> _allMatches(String input, RegExp regex) =>
      regex.allMatches(input).map((m) => m.group(1)!).toList();

  static String? _tag(String block, String name) {
    final m = RegExp('<$name>([\\s\\S]*?)</$name>').firstMatch(block);
    return m?.group(1);
  }

  static void _assertStatus(Response response, List<int> ok, String operation) {
    if (!ok.contains(response.statusCode)) {
      throw Exception(
        'S3 $operation failed (${response.statusCode}): ${response.body}',
      );
    }
  }
}

/// Read a local file's bytes (node profile helper).
Future<List<int>> readFileBytes(String filePath) =>
    File(filePath).readAsBytes();

/// Write bytes to a local file, creating parent directories.
Future<void> writeFileBytes(String filePath, List<int> bytes) async {
  final file = File(filePath);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
}
