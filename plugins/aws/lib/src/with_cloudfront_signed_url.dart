import 'package:flutter_patcher_plugin_core/flutter_patcher_plugin_core.dart'
    show
        RuntimeStorageProfile,
        StoragePlugin,
        StoragePluginProfiles;

import 'aws_cloudfront_signer.dart' show cloudfrontSignedUrl;
import 'aws_ssm_client.dart' show AwsSsmClient;

const int _oneYearInSeconds = 60 * 60 * 24 * 365;

/// Configuration for wrapping a storage plugin with CloudFront signed URLs.
///
/// Faithful port of hot-updater `WithCloudFrontSignedUrlOptions` (minus the
/// `TContext` generic, which the Dart runtime profile does not expose).
class WithCloudFrontSignedUrlOptions {
  const WithCloudFrontSignedUrlOptions({
    required this.keyPairId,
    this.publicBaseUrl,
    this.publicBaseUrlResolver,
    this.getPrivateKey,
    this.ssmParameterName,
    this.ssmRegion,
    this.expiresSeconds,
    this.accessKeyId,
    this.secretAccessKey,
    this.sessionToken,
  });

  final String keyPairId;
  final String? publicBaseUrl;
  final Future<String> Function()? publicBaseUrlResolver;
  final Future<String> Function()? getPrivateKey;
  final String? ssmParameterName;
  final String? ssmRegion;
  final int? expiresSeconds;
  final String? accessKeyId;
  final String? secretAccessKey;
  final String? sessionToken;
}

/// Wrap a storage plugin factory so that `s3://` download URLs are rewritten as
/// CloudFront signed URLs. Faithful port of `withCloudFrontSignedUrl.ts`.
StoragePlugin Function() withCloudFrontSignedUrl(
  StoragePlugin Function() storageFactory,
  WithCloudFrontSignedUrlOptions config,
) {
  return () {
    final base = storageFactory();
    final runtime = base.profiles.runtime == null
        ? null
        : _CloudFrontSignedRuntimeProfile(base.profiles.runtime!, config);
    return _CloudFrontSignedStoragePlugin(base, runtime);
  };
}

class _CloudFrontSignedStoragePlugin implements StoragePlugin {
  _CloudFrontSignedStoragePlugin(this._base, this._runtime);

  final StoragePlugin _base;
  final RuntimeStorageProfile? _runtime;

  @override
  String get name => '${_base.name}WithCloudFrontSignedUrl';

  @override
  String get supportedProtocol => _base.supportedProtocol;

  @override
  StoragePluginProfiles get profiles => StoragePluginProfiles(
        node: _base.profiles.node,
        runtime: _runtime,
      );
}

class _CloudFrontSignedRuntimeProfile implements RuntimeStorageProfile {
  _CloudFrontSignedRuntimeProfile(this._base, this._config);

  final RuntimeStorageProfile _base;
  final WithCloudFrontSignedUrlOptions _config;

  @override
  Future<Map<String, String>> getDownloadUrl(String storageUri) async {
    final parsed = Uri.parse(storageUri);
    if (parsed.scheme != 's3') {
      return _base.getDownloadUrl(storageUri);
    }

    final privateKey = await _resolvePrivateKey();
    final publicBaseUrl = await _resolvePublicBaseUrl();
    final url = Uri.parse(publicBaseUrl);
    final signedUrl = cloudfrontSignedUrl(
      url: url.replace(path: parsed.path, query: null).toString(),
      keyPairId: _config.keyPairId,
      privateKeyPem: privateKey,
      dateLessThan: DateTime.now().add(
        Duration(seconds: _config.expiresSeconds ?? _oneYearInSeconds),
      ),
    );
    return {'fileUrl': signedUrl};
  }

  @override
  Future<String?> readText(String storageUri) => _base.readText(storageUri);

  Future<String> _resolvePrivateKey() async {
    if (_config.getPrivateKey != null) return _config.getPrivateKey!();
    if (_config.ssmParameterName != null && _config.ssmRegion != null) {
      final ssm = AwsSsmClient(
        region: _config.ssmRegion!,
        accessKeyId: _config.accessKeyId ?? '',
        secretAccessKey: _config.secretAccessKey ?? '',
        sessionToken: _config.sessionToken,
      );
      return ssm.getParameter(_config.ssmParameterName!);
    }
    throw StateError(
      'withCloudFrontSignedUrl: no private key source configured '
      '(provide getPrivateKey or ssmParameterName/ssmRegion).',
    );
  }

  Future<String> _resolvePublicBaseUrl() async {
    if (_config.publicBaseUrlResolver != null) {
      final value = await _config.publicBaseUrlResolver!();
      if (value.isEmpty) {
        throw StateError('CloudFront publicBaseUrl resolver returned empty URL');
      }
      return value;
    }
    if (_config.publicBaseUrl != null && _config.publicBaseUrl!.isNotEmpty) {
      return _config.publicBaseUrl!;
    }
    throw StateError('CloudFront publicBaseUrl is empty');
  }
}
