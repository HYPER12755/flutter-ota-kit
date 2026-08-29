import 'dart:convert' show utf8;
import 'dart:typed_data' show Uint8List;

import 'package:crypto/crypto.dart' show Hmac, sha256;
import 'package:http/http.dart' show Client, Request, Response;

const String _cloudfrontService = 'cloudfront';
const String _cloudfrontRegion = 'us-east-1';
const String _cloudfrontApiBase = 'https://cloudfront.amazonaws.com';

/// Configuration for the CloudFront invalidation client.
class AwsCloudFrontConfig {
  const AwsCloudFrontConfig({
    required this.accessKeyId,
    required this.secretAccessKey,
    this.sessionToken,
  });

  final String accessKeyId;
  final String secretAccessKey;
  final String? sessionToken;
}

/// CloudFront cache-invalidation client (mirrors the subset of
/// `@aws-sdk/client-cloudfront` used by hot-updater's `s3Database.ts`).
abstract class AwsCloudFrontClientLike {
  const AwsCloudFrontClientLike();

  Future<void> createInvalidation(
    String distributionId,
    List<String> paths, {
    bool shouldWait = false,
  });
}

/// Real CloudFront client backed by `package:http` + AWS SigV4 signing
/// (service `cloudfront`, global region `us-east-1`).
class AwsCloudFrontClient implements AwsCloudFrontClientLike {
  AwsCloudFrontClient(this.config, {Client? http}) : _http = http ?? Client();

  final AwsCloudFrontConfig config;
  final Client _http;

  static const Duration _pollInterval = Duration(seconds: 2);
  static const Duration _timeout = Duration(minutes: 5);

  @override
  Future<void> createInvalidation(
    String distributionId,
    List<String> paths, {
    bool shouldWait = false,
  }) async {
    if (paths.isEmpty) return;

    final timestamp = DateTime.now();
    final callerReference = 'invalidation-${timestamp.millisecondsSinceEpoch}';
    final body = _buildInvalidationXml(callerReference, paths);
    final uri = Uri.parse(
      '$_cloudfrontApiBase/2020-05-31/distribution/$distributionId/invalidation',
    );

    try {
      final response = await _send('POST', uri, utf8.encode(body));
      _assertStatus(response, [200, 201], 'CreateInvalidation');

      if (!shouldWait) return;

      final invalidationId = _extractInvalidationId(response.body);
      if (invalidationId == null) {
        throw StateError('CloudFront invalidation response missing Id');
      }
      if (response.body.contains('<Status>Completed</Status>')) return;

      final deadline = DateTime.now().add(_timeout);
      while (DateTime.now().isBefore(deadline)) {
        await Future.delayed(_pollInterval);
        final statusResp = await _send(
          'GET',
          Uri.parse(
            '$_cloudfrontApiBase/2020-05-31/distribution/$distributionId/'
            'invalidation/$invalidationId',
          ),
          null,
        );
        if (statusResp.body.contains('<Status>Completed</Status>')) return;
      }
      throw StateError(
        'Timed out waiting for CloudFront invalidation $invalidationId',
      );
    } catch (error) {
      if (shouldWait) rethrow;
      // When not waiting, surface invalidation failures as warnings and
      // continue (mirrors hot-updater's s3Database behaviour).
      // ignore: avoid_print
      print(
        '[flutter_ota_kit/aws] CloudFront invalidation failed for '
        '$distributionId; continuing without cache invalidation: $error',
      );
    }
  }

  String _buildInvalidationXml(String callerReference, List<String> paths) {
    final items = paths
        .map((p) => '    <Path>${_xmlEscape(p)}</Path>')
        .join('\n');
    return '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<InvalidationBatch xmlns="http://cloudfront.amazonaws.com/doc/2020-05-31/">\n'
        '  <CallerReference>$callerReference</CallerReference>\n'
        '  <Paths>\n'
        '    <Quantity>${paths.length}</Quantity>\n'
        '    <Items>\n$items\n    </Items>\n'
        '  </Paths>\n'
        '</InvalidationBatch>';
  }

  String? _extractInvalidationId(String xml) {
    final m = RegExp(r'<Id>([^<]+)</Id>').firstMatch(xml);
    return m?.group(1);
  }

  Map<String, String> _authHeaders(
    String method,
    Uri uri,
    List<int>? body,
  ) {
    final now = DateTime.now().toUtc();
    final amzDate = _amzDate(now);
    final dateStamp = amzDate.substring(0, 8);
    final scope =
        '$dateStamp/$_cloudfrontRegion/$_cloudfrontService/aws4_request';
    final payloadHash = body == null ? _hashHex(const []) : _hashHex(body);

    final canonicalHeaders = 'host:${uri.host}\n'
        'x-amz-content-sha256:$payloadHash\n'
        'x-amz-date:$amzDate\n'
        '${config.sessionToken != null ? 'x-amz-security-token:${config.sessionToken}\n' : ''}';
    final signedHeaders = config.sessionToken != null
        ? 'host;x-amz-content-sha256;x-amz-date;x-amz-security-token'
        : 'host;x-amz-content-sha256;x-amz-date';

    final canonicalRequest = '$method\n${uri.path}\n'
        '\n$canonicalHeaders$signedHeaders\n$payloadHash';
    final stringToSign = _stringToSign(amzDate, scope, canonicalRequest);
    final signingKey = _signingKey(dateStamp);
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

  Future<Response> _send(String method, Uri uri, List<int>? body) async {
    final request = Request(method, uri);
    request.headers.addAll(_authHeaders(method, uri, body));
    request.headers['Content-Type'] = 'application/xml';
    if (body != null) request.bodyBytes = body;
    final streamed = await _http.send(request);
    return await Response.fromStream(streamed);
  }

  List<int> _signingKey(String dateStamp) {
    var key = utf8.encode('AWS4${config.secretAccessKey}');
    key = _hmac(key, dateStamp);
    key = _hmac(key, _cloudfrontRegion);
    key = _hmac(key, _cloudfrontService);
    key = _hmac(key, 'aws4_request');
    return key;
  }

  String _stringToSign(String amzDate, String scope, String canonicalRequest) =>
      'AWS4-HMAC-SHA256\n$amzDate\n$scope\n${_hashHex(utf8.encode(canonicalRequest))}';

  static String _amzDate(DateTime utc) =>
      '${utc.toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z';

  static String _xmlEscape(String value) =>
      value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  static Uint8List _hmac(List<int> key, String data) =>
      Hmac(sha256, key).convert(utf8.encode(data)).bytes as Uint8List;

  static String _hashHex(List<int> data) =>
      _toHex(sha256.convert(data).bytes);

  static String _toHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static void _assertStatus(
    Response response,
    List<int> ok,
    String operation,
  ) {
    if (!ok.contains(response.statusCode)) {
      throw Exception(
        'CloudFront $operation failed (${response.statusCode}): ${response.body}',
      );
    }
  }
}
