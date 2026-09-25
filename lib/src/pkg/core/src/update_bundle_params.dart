import 'platform.dart';

/// hot-updater `UpdateBundleParams` — device-side parameters sent with
/// update requests.
///
/// These parameters are collected by the device SDK and sent to the
/// backend's update-check endpoint to determine which bundle the
/// device should install.
class UpdateBundleParams {
  /// Target platform (`ios` or `android`).
  final Platform platform;

  /// Currently installed bundle ID.
  final String bundleId;

  /// Minimum bundle ID to consider (for rollback protection).
  final String minBundleId;

  /// Release channel to query.
  final String channel;

  /// Current app version (semver string).
  final String appVersion;

  /// Optional device fingerprint hash for targeted rollouts.
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
