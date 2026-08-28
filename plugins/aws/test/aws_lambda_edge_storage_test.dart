import 'dart:convert' show base64, base64Decode, utf8;
import 'dart:math' show Random;
import 'dart:typed_data' show Uint8List;

import 'package:asn1lib/asn1lib.dart';
import 'package:flutter_patcher_aws/flutter_patcher_aws.dart'
    show
        AwsLambdaEdgeStorageConfig,
        cloudfrontSignedUrl,
        s3LambdaEdgeStorage,
        verifyCloudfrontSignedUrl;
import 'package:flutter_patcher_plugin_core/flutter_patcher_plugin_core.dart'
    show RuntimeStorageProfile;
import 'package:pointycastle/export.dart'
    show
        FortunaRandom,
        KeyParameter,
        ParametersWithRandom,
        RSAKeyGenerator,
        RSAKeyGeneratorParameters,
        RSAPrivateKey,
        RSAPublicKey;
import 'package:test/test.dart';

import 'mock_aws_s3_client.dart' show MockAwsS3Client, Store;

List<int> _b64urlDecode(String s) {
  final normalized = s.replaceAll('-', '+').replaceAll('_', '/');
  final padded = normalized.padRight(
    normalized.length + (4 - normalized.length % 4) % 4,
    '=',
  );
  return base64Decode(padded);
}

String _wrapPem(String label, String b64) {
  final chunks = <String>[];
  for (var i = 0; i < b64.length; i += 64) {
    chunks.add(b64.substring(i, i + 64 > b64.length ? b64.length : i + 64));
  }
  return '-----BEGIN $label-----\n${chunks.join('\n')}\n-----END $label-----\n';
}

String _encodePrivatePkcs1(RSAPrivateKey k, RSAPublicKey pub) {
  final p = k.p!;
  final q = k.q!;
  final d = k.privateExponent!;
  final dP = d % (p - BigInt.one);
  final dQ = d % (q - BigInt.one);
  final qInv = q.modInverse(p);
  final seq = ASN1Sequence();
  seq.add(ASN1Integer(BigInt.zero));
  seq.add(ASN1Integer(k.modulus!));
  seq.add(ASN1Integer(pub.exponent!));
  seq.add(ASN1Integer(d));
  seq.add(ASN1Integer(p));
  seq.add(ASN1Integer(q));
  seq.add(ASN1Integer(dP));
  seq.add(ASN1Integer(dQ));
  seq.add(ASN1Integer(qInv));
  return _wrapPem('RSA PRIVATE KEY', base64.encode(seq.encodedBytes));
}

String _encodePublic(RSAPublicKey pub) {
  final keySeq = ASN1Sequence();
  keySeq.add(ASN1Integer(pub.modulus!));
  keySeq.add(ASN1Integer(pub.exponent!));
  final spki = ASN1Sequence();
  final alg = ASN1Sequence();
  alg.add(ASN1ObjectIdentifier.fromComponents([1, 2, 840, 113549, 1, 1, 1]));
  alg.add(ASN1Null());
  spki.add(alg);
  spki.add(ASN1BitString(keySeq.encodedBytes));
  return _wrapPem('PUBLIC KEY', base64.encode(spki.encodedBytes));
}

(String, String) _generateKeyPair() {
  final rng = FortunaRandom();
  final seedSource = Random.secure();
  rng.seed(
    KeyParameter(
      Uint8List.fromList(
        List<int>.generate(32, (_) => seedSource.nextInt(256)),
      ),
    ),
  );
  final kg = RSAKeyGenerator()
    ..init(
      ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 12),
        rng,
      ),
    );
  final pair = kg.generateKeyPair();
  final priv = pair.privateKey as RSAPrivateKey;
  final pub = pair.publicKey as RSAPublicKey;
  return (_encodePrivatePkcs1(priv, pub), _encodePublic(pub));
}

AwsLambdaEdgeStorageConfig _edgeConfig(
  Store store,
  String privatePem, {
  String? publicBaseUrl,
  Future<String> Function()? publicBaseUrlResolver,
}) =>
    AwsLambdaEdgeStorageConfig(
      bucketName: 'test-bucket',
      region: 'us-east-1',
      accessKeyId: 'ak',
      secretAccessKey: 'sk',
      keyPairId: 'KP123',
      publicBaseUrl: publicBaseUrl,
      publicBaseUrlResolver: publicBaseUrlResolver,
      getPrivateKey: () async => privatePem,
      clientFactory: (_) => MockAwsS3Client(store),
    );

void main() {
  group('aws cloudfront signed url', () {
    final (privatePem, publicPem) = _generateKeyPair();

    test('cloudfrontSignedUrl round-trips and verifies', () {
      const url = 'https://cdn.example.com/bundles/x.zip';
      final signed = cloudfrontSignedUrl(
        url: url,
        keyPairId: 'KP123',
        privateKeyPem: privatePem,
        dateLessThan: DateTime.now().add(const Duration(days: 365)),
      );
      expect(signed, contains('Policy='));
      expect(signed, contains('Signature='));
      expect(signed, contains('Key-Pair-Id=KP123'));
      expect(
        verifyCloudfrontSignedUrl(signedUrl: signed, publicKeyPem: publicPem),
        isTrue,
      );

      final uri = Uri.parse(signed);
      final policyJson = utf8.decode(_b64urlDecode(uri.queryParameters['Policy']!));
      expect(policyJson, contains(url));
    });

    test('s3LambdaEdgeStorage signs s3 download urls', () async {
      final store = Store();
      final plugin = s3LambdaEdgeStorage(
        _edgeConfig(store, privatePem, publicBaseUrl: 'https://cdn.example.com'),
      );
      final RuntimeStorageProfile runtime = plugin.profiles.runtime!;

      final res = await runtime.getDownloadUrl('s3://test-bucket/bundles/x.zip');
      final fileUrl = res['fileUrl']!;
      expect(fileUrl, contains('Key-Pair-Id=KP123'));
      expect(
        verifyCloudfrontSignedUrl(signedUrl: fileUrl, publicKeyPem: publicPem),
        isTrue,
      );

      final uri = Uri.parse(fileUrl);
      final policy = utf8.decode(_b64urlDecode(uri.queryParameters['Policy']!));
      expect(policy, contains('https://cdn.example.com/bundles/x.zip'));
    });

    test('s3LambdaEdgeStorage resolves publicBaseUrl via function', () async {
      final store = Store();
      final plugin = s3LambdaEdgeStorage(
        _edgeConfig(
          store,
          privatePem,
          publicBaseUrlResolver: () async => 'https://edge.acme.dev',
        ),
      );
      final runtime = plugin.profiles.runtime!;
      final res = await runtime.getDownloadUrl('s3://test-bucket/a.zip');
      expect(
        verifyCloudfrontSignedUrl(
          signedUrl: res['fileUrl']!,
          publicKeyPem: publicPem,
        ),
        isTrue,
      );
      expect(res['fileUrl'], contains('https://edge.acme.dev/a.zip'));
    });

    test('plugin name carries WithCloudFrontSignedUrl suffix', () {
      final store = Store();
      final plugin = s3LambdaEdgeStorage(_edgeConfig(store, privatePem));
      expect(plugin.name, 's3StorageWithCloudFrontSignedUrl');
    });
  });
}
