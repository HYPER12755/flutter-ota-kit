import 'dart:convert' show jsonDecode, jsonEncode, utf8;
import 'dart:typed_data' show Uint8List;

import 'package:crypto/crypto.dart' show Hmac, sha256;
import 'package:http/http.dart' show Client, Request, Response;

/// Minimal AWS SSM client used to fetch the CloudFront private key from a
/// `SecureString` parameter (faithful to hot-updater's `applySsmRuntimeAwsConfig`
/// + `SSM.getParameter`).
class AwsSsmClient {
  AwsSsmClient({
    required this.region,
    required this.accessKeyId,
    required this.secretAccessKey,
    this.sessionToken,
    Client? http,
  }) : _http = http ?? Client();

  final String region;
  final String accessKeyId;
  final String secretAccessKey;
  final String? sessionToken;
  final Client _http;

  static const String _service = 'ssm';

  Future<String> getParameter(String name) async {
    final uri = Uri.parse('https://ssm.$region.amazonaws.com/');
    final body = utf8.encode(
      jsonEncode({'Name': name, 'WithDecryption': true}),
    );
    final response = await _send('POST', uri, body);
    _assertStatus(response, [200], 'GetParameter');

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final parameter = json['Parameter'] as Map<String, dynamic>?;
    final value = parameter?['Value'] as String?;
    if (value == null || value.isEmpty) {
      throw StateError('SSM parameter "$name" returned no value');
    }

    // The stored value is a JSON document containing the private key.
    final parsed = jsonDecode(value) as Map<String, dynamic>;
    final privateKey = parsed['privateKey'] as String?;
    if (privateKey == null || privateKey.isEmpty) {
      throw StateError('SSM parameter "$name" missing "privateKey"');
    }
    return privateKey;
  }

  Map<String, String> _authHeaders(String method, Uri uri, List<int> body) {
    final now = DateTime.now().toUtc();
    final amzDate = _amzDate(now);
    final dateStamp = amzDate.substring(0, 8);
    final scope = '$dateStamp/$region/$_service/aws4_request';
    final payloadHash = _hashHex(body);

    final canonicalHeaders = 'host:${uri.host}\n'
        'x-amz-content-sha256:$payloadHash\n'
        'x-amz-date:$amzDate\n'
        '${sessionToken != null ? 'x-amz-security-token:$sessionToken\n' : ''}'
        'x-amz-target:AmazonSSM.GetParameter\n';
    final signedHeaders = sessionToken != null
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
      'x-amz-target': 'AmazonSSM.GetParameter',
      'Content-Type': 'application/x-amz-json-1.1',
      'Authorization':
          'AWS4-HMAC-SHA256 Credential=$accessKeyId/$scope, '
          'SignedHeaders=$signedHeaders, Signature=$signature',
    };
    if (sessionToken != null) headers['x-amz-security-token'] = sessionToken!;
    return headers;
  }

  Future<Response> _send(String method, Uri uri, List<int> body) async {
    final request = Request(method, uri);
    request.headers.addAll(_authHeaders(method, uri, body));
    request.bodyBytes = body;
    final streamed = await _http.send(request);
    return await Response.fromStream(streamed);
  }

  List<int> _signingKey(String dateStamp) {
    var key = utf8.encode('AWS4$secretAccessKey');
    key = _hmac(key, dateStamp);
    key = _hmac(key, region);
    key = _hmac(key, _service);
    key = _hmac(key, 'aws4_request');
    return key;
  }

  String _stringToSign(String amzDate, String scope, String canonicalRequest) =>
      'AWS4-HMAC-SHA256\n$amzDate\n$scope\n${_hashHex(utf8.encode(canonicalRequest))}';

  static String _amzDate(DateTime utc) =>
      '${utc.toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z';

  static Uint8List _hmac(List<int> key, String data) =>
      Hmac(sha256, key).convert(utf8.encode(data)).bytes as Uint8List;

  static String _hashHex(List<int> data) =>
      _toHex(sha256.convert(data).bytes);

  static String _toHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static void _assertStatus(Response response, List<int> ok, String operation) {
    if (!ok.contains(response.statusCode)) {
      throw Exception(
        'SSM $operation failed (${response.statusCode}): ${response.body}',
      );
    }
  }
}
