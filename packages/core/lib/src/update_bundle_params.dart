import 'platform.dart';

/// hot-updater `UpdateBundleParams` — device-side parameters sent with
/// update requests.
class UpdateBundleParams {
  final Platform platform;
  final String bundleId;
  final String minBundleId;
  final String channel;
  final String appVersion;
  final String? fingerprintHash;

  const UpdateBundleParams({
    required this.platform,
    required this.bundleId,
    required this.minBundleId,
    required this.channel,
    required this.appVersion,
    required this.fingerprintHash,
  });

  Map<String, dynamic> toJson() => {
    'platform': platform.value,
    'bundleId': bundleId,
    'minBundleId': minBundleId,
    'channel': channel,
    'appVersion': appVersion,
    if (fingerprintHash != null) 'fingerprintHash': fingerprintHash,
  };
}
