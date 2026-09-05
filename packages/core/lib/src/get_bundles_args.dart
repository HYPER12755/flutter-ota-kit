import 'platform.dart';
import 'strategy.dart';
import 'uuid.dart' show nilUuid;

/// hot-updater `GetBundlesArgs` — update-check request parameters.
///
/// Two variants keyed by [UpdateStrategy]; shared fields defaulted the same
/// way (minBundleId = NIL_UUID, channel = "production").
sealed class GetBundlesArgs {
  final UpdateStrategy _updateStrategy;
  final Platform platform;
  final String bundleId;
  final String minBundleId;
  final String channel;

  /// Cohort identifier for server-side rollout decisions.
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

class FingerprintGetBundlesArgs extends GetBundlesArgs {
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

class AppVersionGetBundlesArgs extends GetBundlesArgs {
  /// Current app version (semver).
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
