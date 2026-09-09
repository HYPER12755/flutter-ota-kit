import 'platform.dart';
import 'strategy.dart';
import 'uuid.dart' show nilUuid;

/// hot-updater `GetBundlesArgs` — update-check request parameters.
///
/// Two variants keyed by [UpdateStrategy]; shared fields defaulted the same
/// way (minBundleId = NIL_UUID, channel = "production").
///
/// Use [AppVersionGetBundlesArgs] for semver-based targeting or
/// [FingerprintGetBundlesArgs] for device-specific targeting.
sealed class GetBundlesArgs {
  /// The update strategy this request uses.
  final UpdateStrategy _updateStrategy;

  /// Target platform (`ios` or `android`).
  final Platform platform;

  /// Currently installed bundle ID.
  final String bundleId;

  /// Minimum bundle ID to consider (for rollback protection).
  final String minBundleId;

  /// Release channel to query (default: `"production"`).
  final String channel;

  /// Optional cohort identifier for server-side rollout decisions.
  final String? cohort;

  const GetBundlesArgs({
    required UpdateStrategy strategy,
    required this.platform,
    required this.bundleId,
    this.minBundleId = nilUuid,
    this.channel = 'production',
    this.cohort,
  }) : _updateStrategy = strategy;

  /// Public accessor for the resolved update strategy.
  UpdateStrategy get updateStrategy => _updateStrategy;

  Map<String, dynamic> toJson() => {
    '_updateStrategy': _updateStrategy.value,
    'platform': platform.value,
    'bundleId': bundleId,
    if (minBundleId != nilUuid) 'minBundleId': minBundleId,
    if (channel != 'production') 'channel': channel,
    if (cohort != null) 'cohort': cohort,
  };
}

/// Update-check args using device fingerprint for targeting.
///
/// The server matches [fingerprintHash] against bundles that have a
/// `targetCohorts` list, enabling device-specific rollouts without
/// exposing device IDs.
class FingerprintGetBundlesArgs extends GetBundlesArgs {
  /// SHA-256 hex of the device fingerprint.
  final String fingerprintHash;

  const FingerprintGetBundlesArgs({
    required super.platform,
    required super.bundleId,
    super.minBundleId,
    super.channel,
    super.cohort,
    required this.fingerprintHash,
  }) : super(strategy: UpdateStrategy.fingerprint);

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'fingerprintHash': fingerprintHash,
  };
}

/// Update-check args using semver range for targeting.
///
/// The server matches [appVersion] against bundles' `targetAppVersion`
/// semver ranges to determine eligibility.
class AppVersionGetBundlesArgs extends GetBundlesArgs {
  /// Current app version (semver string, e.g. `"1.2.3"`).
  final String appVersion;

  const AppVersionGetBundlesArgs({
    required super.platform,
    required super.bundleId,
    super.minBundleId,
    super.channel,
    super.cohort,
    required this.appVersion,
  }) : super(strategy: UpdateStrategy.appVersion);

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'appVersion': appVersion,
  };
}
