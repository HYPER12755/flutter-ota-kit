// flutter_ota_kit_aws example
//
// `flutter_ota_kit_aws` provides AWS S3 storage + S3/DynamoDB database
// plugins for `flutter_ota_kit`. The typical setup uses S3 for both
// (storing a `bundles.json` manifest plus patch blobs), with optional
// CloudFront for signed URLs and faster edge delivery.
//
// Most apps don't import this package directly; they wire it through
// `flutter_ota_kit.configureAws(...)` in their app boot path. This file
// shows the low-level config types in case you're writing a custom
// server or a CLI extension.
//
// Run: `dart run example/main.dart`

import 'package:flutter_ota_kit_aws/flutter_ota_kit_aws.dart';

void main() {
  // ── 1. S3 storage config (for storing patch blobs). ──────────────
  // `bucketName` + `region` are required. `accessKeyId` and
  // `secretAccessKey` are read-write credentials; in production use an
  // IAM role with the minimum required permissions.
  final s3Config = AwsS3StorageConfig(
    bucketName: 'flutter-ota-bundles',
    region: 'us-east-1',
    accessKeyId: 'AKIA...',
    secretAccessKey: 'wJal...',
    basePath: 'bundles',
  );
  print('S3 bucket: ${s3Config.bucketName} (${s3Config.region})');
  print('Base path: ${s3Config.basePath}');

  // ── 2. S3 database config (for storing the bundles manifest). ───
  // The "database" plugin reads/writes a `bundles.json` manifest in
  // the same S3 bucket. `cloudfrontDistributionId` enables signed URL
  // serving for the patch downloads.
  final dbConfig = S3DatabaseConfig(
    bucketName: 'flutter-ota-bundles',
    region: 'us-east-1',
    accessKeyId: 'AKIA...',
    secretAccessKey: 'wJal...',
    cloudfrontDistributionId: 'E1ABC2DEF3GHIJ',
  );
  print('S3 DB bucket: ${dbConfig.bucketName}');
  print('CloudFront distribution: ${dbConfig.cloudfrontDistributionId}');

  // ── 3. CloudFront URL signing (for time-limited download URLs). ──
  // `cloudfrontSignedUrl` produces a URL valid for `expiresInSeconds`
  // (default 1 hour). The signing key is a private RSA key in PEM
  // format — never ship it in a Flutter app.
  // final key = parseRsaPrivateKeyPem(
  //   File('cloudfront-private-key.pem').readAsStringSync(),
  // );
  // final signedUrl = cloudfrontSignedUrl(
  //   url: 'https://d1abc2def3ghij.cloudfront.net/patch.zip',
  //   privateKey: key,
  //   keyPairId: 'APKA...',
  //   expiresInSeconds: 600,
  // );
  // print('Signed URL: $signedUrl');
}
