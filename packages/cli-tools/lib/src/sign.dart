import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Verify an Ed25519 signature over [message].
///
/// [publicKeyBase64] may be either a raw 32-byte Ed25519 public key or the
/// X.509 SubjectPublicKeyInfo (SPKI) form expected by the Android device SDK.
Future<bool> ed25519Verify(
  List<int> message,
  String signatureBase64,
  String publicKeyBase64,
) async {
  var pkBytes = base64Decode(publicKeyBase64);
  // Strip the X.509 SPKI prefix (12 bytes) if present so [SimplePublicKey]
  // receives the raw 32-byte key.
  if (pkBytes.length == 44 && _startsWith(pkBytes, _ed25519SpkiPrefix)) {
    pkBytes = pkBytes.sublist(_ed25519SpkiPrefix.length);
  }
  final public = SimplePublicKey(pkBytes, type: KeyPairType.ed25519);
  final sig = Signature(base64Decode(signatureBase64), publicKey: public);
  return Ed25519().verify(message, signature: sig);
}

/// The 12-byte DER prefix of an Ed25519 X.509 SubjectPublicKeyInfo.
const List<int> _ed25519SpkiPrefix = <int>[
  0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00,
];

bool _startsWith(List<int> bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

/// Generate a fresh Ed25519 keypair, returning (privateSeedB64, publicB64).
///
/// The returned public key is the X.509 SubjectPublicKeyInfo (SPKI) base64
/// form, which is exactly what the Android device SDK expects
/// (`SignatureVerifier.verifyEd25519` decodes X.509).
Future<(String, String)> generateEd25519KeyPair() async {
  final keyPair = await Ed25519().newKeyPair();
  final private = await keyPair.extractPrivateKeyBytes();
  final rawPublic = (await keyPair.extractPublicKey()).bytes;
  final spki = <int>[
    ..._ed25519SpkiPrefix,
    ...rawPublic,
  ];
  return (base64Encode(private), base64Encode(spki));
}

/// Sign [message] with an Ed25519 private seed (base64, 32 bytes).
Future<String> ed25519Sign(List<int> message, String privateKeyBase64) async {
  final seed = base64Decode(privateKeyBase64);
  final keyPair = await Ed25519().newKeyPairFromSeed(seed);
  final signature = await Ed25519().sign(message, keyPair: keyPair);
  return base64Encode(signature.bytes);
}
