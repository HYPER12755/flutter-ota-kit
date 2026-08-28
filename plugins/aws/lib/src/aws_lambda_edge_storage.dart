import 'package:flutter_patcher_plugin_core/flutter_patcher_plugin_core.dart'
    show StoragePlugin, StoragePluginHooks;

import 'aws_config.dart' show AwsS3StorageConfig;
import 'aws_storage.dart' show s3Storage;
import 'with_cloudfront_signed_url.dart'
    show WithCloudFrontSignedUrlOptions, withCloudFrontSignedUrl;

/// Configuration for the AWS Lambda@Edge S3 storage plugin.
///
/// Combines `S3StorageConfig` (credentials/bucket) with the CloudFront signed
/// URL options. Faithful port of hot-updater `AwsLambdaEdgeStorageConfig`.
class AwsLambdaEdgeStorageConfig extends AwsS3StorageConfig {
  AwsLambdaEdgeStorageConfig({
    required super.bucketName,
    required super.region,
    required super.accessKeyId,
    required super.secretAccessKey,
    super.basePath,
    super.endpoint,
    super.sessionToken,
    super.clientFactory,
    required this.keyPairId,
    this.publicBaseUrl,
    this.publicBaseUrlResolver,
    this.getPrivateKey,
    this.ssmParameterName,
    this.ssmRegion,
    this.expiresSeconds,
  });

  final String keyPairId;
  final String? publicBaseUrl;
  final Future<String> Function()? publicBaseUrlResolver;
  final Future<String> Function()? getPrivateKey;
  final String? ssmParameterName;
  final String? ssmRegion;
  final int? expiresSeconds;

  WithCloudFrontSignedUrlOptions toSignedUrlOptions() =>
      WithCloudFrontSignedUrlOptions(
        keyPairId: keyPairId,
        publicBaseUrl: publicBaseUrl,
        publicBaseUrlResolver: publicBaseUrlResolver,
        getPrivateKey: getPrivateKey,
        ssmParameterName: ssmParameterName,
        ssmRegion: ssmRegion,
        expiresSeconds: expiresSeconds,
        accessKeyId: accessKeyId,
        secretAccessKey: secretAccessKey,
        sessionToken: sessionToken,
      );
}

/// AWS Lambda@Edge S3 storage plugin: S3 storage whose `s3://` download URLs
/// are rewritten as CloudFront signed URLs. Faithful port of
/// `s3LambdaEdgeStorage.ts` / `awsLambdaEdgeStorage.ts`.
StoragePlugin s3LambdaEdgeStorage(
  AwsLambdaEdgeStorageConfig config, [
  StoragePluginHooks? hooks,
]) =>
    withCloudFrontSignedUrl(
      () => s3Storage(config, hooks),
      config.toSignedUrlOptions(),
    )();

/// Alias matching hot-updater's `awsLambdaEdgeStorage` export.
StoragePlugin awsLambdaEdgeStorage(
  AwsLambdaEdgeStorageConfig config, [
  StoragePluginHooks? hooks,
]) =>
    s3LambdaEdgeStorage(config, hooks);
