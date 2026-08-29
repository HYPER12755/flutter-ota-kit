import 'dart:convert' show base64Decode, base64Encode, jsonEncode, utf8;
import 'dart:typed_data' show Uint8List;

import 'package:asn1lib/asn1lib.dart';
import 'package:pointycastle/export.dart'
    show
        PrivateKeyParameter,
        PublicKeyParameter,
        RSAPrivateKey,
        RSAPublicKey,
        RSASignature,
        RSASigner,
        SHA1Digest;

/// ASN.1 DigestInfo prefix for SHA1, used by pointycastle's PKCS#1 v1.5 signer.
const String _sha1DigestIdentifierHex = '3021300906052b0e03021a05000414';

String _base64UrlNoPad(List<int> bytes) =>
    base64Encode(bytes).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');

/// Parse a PEM-encoded RSA private key (PKCS#1 `RSA PRIVATE KEY` or PKCS#8
/// `PRIVATE KEY`) into a [RSAPrivateKey].
RSAPrivateKey parseRsaPrivateKeyPem(String pem) {
  final lines = pem
      .split('\n')
      .where((l) => l.isNotEmpty && !l.startsWith('-----'))
      .join('');
  final der = base64DecodeToBytes(lines);
  final seq = ASN1Parser(der).nextObject() as ASN1Sequence;

  late final ASN1Sequence keySeq;
  if (seq.elements.length == 3) {
    // PKCS#8: SEQUENCE { version, AlgorithmIdentifier, BIT STRING }
    final bitString = seq.elements[2] as ASN1BitString;
    keySeq = ASN1Parser(bitString.contentBytes()).nextObject() as ASN1Sequence;
  } else {
    // PKCS#1: RSAPrivateKey ::= SEQUENCE { version, n, e, d, p, q, dP, dQ, qInv }
    keySeq = seq;
  }

  final modulus = (keySeq.elements[1] as ASN1Integer).valueAsBigInteger;
  final privateExponent = (keySeq.elements[3] as ASN1Integer).valueAsBigInteger;
  final p = (keySeq.elements[4] as ASN1Integer).valueAsBigInteger;
  final q = (keySeq.elements[5] as ASN1Integer).valueAsBigInteger;
  return RSAPrivateKey(modulus, privateExponent, p, q);
}

Uint8List base64DecodeToBytes(String s) => _base64Decode(s);

Uint8List _base64Decode(String s) {
  final normalized = s.replaceAll('-', '+').replaceAll('_', '/');
  final padded = normalized.padRight(
    normalized.length + (4 - normalized.length % 4) % 4,
    '=',
  );
  return base64Decode(padded);
}

/// Build a CloudFront signed URL (custom policy, RSA-SHA1) for [url].
///
/// Faithful port of `@aws-sdk/cloudfront-signer`'s `getSignedUrl`.
String cloudfrontSignedUrl({
  required String url,
  required String keyPairId,
  required String privateKeyPem,
  required DateTime dateLessThan,
}) {
  final privateKey = parseRsaPrivateKeyPem(privateKeyPem);

  final policy = jsonEncode({
    'Statement': [
      {
        'Resource': url,
        'Condition': {
          'DateLessThan': {
            'AWS:EpochTime': dateLessThan.millisecondsSinceEpoch ~/ 1000,
          },
        },
      },
    ],
  });
  final policyBytes = utf8.encode(policy);
  final policyB64 = _base64UrlNoPad(policyBytes);

  final signer = RSASigner(SHA1Digest(), _sha1DigestIdentifierHex);
  signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
  final signature = signer.generateSignature(Uint8List.fromList(policyBytes)).bytes;
  final signatureB64 = _base64UrlNoPad(signature);

  return '$url?Policy=$policyB64&Signature=$signatureB64'
      '&Key-Pair-Id=$keyPairId';
}

/// Verify a CloudFront signed URL's signature against [publicKeyPem] (test seam).
bool verifyCloudfrontSignedUrl({
  required String signedUrl,
  required String publicKeyPem,
}) {
  final uri = Uri.parse(signedUrl);
  final policy = uri.queryParameters['Policy'];
  final signature = uri.queryParameters['Signature'];
  if (policy == null || signature == null) return false;

  final policyBytes = _base64Decode(policy);
  final sigBytes = _base64Decode(signature);

  final pub = parseRsaPublicKeyPem(publicKeyPem);
  final signer = RSASigner(SHA1Digest(), _sha1DigestIdentifierHex);
  signer.init(false, PublicKeyParameter<RSAPublicKey>(pub));
  return signer.verifySignature(
    Uint8List.fromList(policyBytes),
    RSASignature(Uint8List.fromList(sigBytes)),
  );
}

/// Parse a PEM-encoded RSA public key into [RSAPublicKey].
RSAPublicKey parseRsaPublicKeyPem(String pem) {
  final lines = pem
      .split('\n')
      .where((l) => l.isNotEmpty && !l.startsWith('-----'))
      .join('');
  final der = base64DecodeToBytes(lines);
  final seq = ASN1Parser(der).nextObject() as ASN1Sequence;
  // SubjectPublicKeyInfo: SEQUENCE { AlgorithmIdentifier, BIT STRING }
  final bitString = seq.elements[1] as ASN1BitString;
  final key = ASN1Parser(bitString.contentBytes()).nextObject() as ASN1Sequence;
  final modulus = (key.elements[0] as ASN1Integer).valueAsBigInteger;
  final exponent = (key.elements[1] as ASN1Integer).valueAsBigInteger;
  return RSAPublicKey(modulus, exponent);
}
