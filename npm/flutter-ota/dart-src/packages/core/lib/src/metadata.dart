/// Bundle metadata — hot-updater `BundleMetadata` (snake_case on the wire).
library;

class BundleMetadata {
  final String? appVersion;

  /// Ed25519 (base64) signature over the artifact's MD5 hex string. Stored here
  /// (rather than a dedicated column) so it round-trips through every backend's
  /// JSON `metadata` column without a schema migration. The device SDK reads
  /// this to verify the patch (see [AppUpdateAvailableInfo.signature]).
  final String? signature;

  const BundleMetadata({this.appVersion, this.signature});

  factory BundleMetadata.fromJson(Map<String, dynamic> j) => BundleMetadata(
        appVersion: j['app_version'] as String?,
        signature: j['signature'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'app_version': appVersion,
        if (signature != null) 'signature': signature,
      };

  @override
  bool operator ==(Object o) =>
      o is BundleMetadata && o.appVersion == appVersion && o.signature == signature;

  @override
  int get hashCode => Object.hash(appVersion, signature);
}
