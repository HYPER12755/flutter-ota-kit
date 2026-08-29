import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart';

/// Build an [UpdateInfo] response from a [Bundle] and an [UpdateStatus].
UpdateInfo _makeResponse(Bundle bundle, UpdateStatus status) {
  return UpdateInfo(
    id: bundle.id,
    message: bundle.message,
    shouldForceUpdate: status == UpdateStatus.rollback
        ? true
        : bundle.shouldForceUpdate,
    status: status,
    storageUri: bundle.storageUri,
    fileHash: bundle.fileHash,
  );
}

/// Whether [bundle] is eligible for the user in [cohort].
bool _isEligibleUpdateCandidate(Bundle bundle, String? cohort) {
  return isCohortEligibleForUpdate(
    bundle.id,
    cohort,
    bundle.rolloutCohortCount,
    bundle.targetCohorts,
  );
}

/// Find the bundle with the largest ID that is newer than [bundleId]
/// and cohort-eligible.
Bundle? _findLatestEligibleUpdateCandidate(
  List<Bundle> bundles,
  String bundleId,
  String? cohort,
) {
  Bundle? updateCandidate;

  for (final bundle in bundles) {
    if (bundle.id.compareTo(bundleId) > 0 &&
        _isEligibleUpdateCandidate(bundle, cohort) &&
        (updateCandidate == null ||
            bundle.id.compareTo(updateCandidate.id) > 0)) {
      updateCandidate = bundle;
    }
  }

  return updateCandidate;
}

/// Default rollback response for init bundles (id = nilUuid).
const UpdateInfo _initBundleRollbackUpdateInfo = UpdateInfo(
  message: null,
  id: '00000000-0000-0000-0000-000000000000',
  shouldForceUpdate: true,
  status: UpdateStatus.rollback,
  storageUri: null,
  fileHash: null,
);

/// Resolve update info using the app-version strategy.
Future<UpdateInfo?> _appVersionStrategy(
  List<Bundle> bundles,
  AppVersionGetBundlesArgs args,
) async {
  final channel = args.channel;
  final minBundleId = args.minBundleId;
  final platform = args.platform;
  final appVersion = args.appVersion;
  final bundleId = args.bundleId;
  final cohort = args.cohort;

  final candidateBundles = <Bundle>[];

  for (final b in bundles) {
    if (b.platform != platform ||
        b.channel != channel ||
        b.targetAppVersion == null ||
        !semverSatisfies(b.targetAppVersion!, appVersion) ||
        !b.enabled ||
        (minBundleId.isNotEmpty && b.id.compareTo(minBundleId) < 0)) {
      continue;
    }
    candidateBundles.add(b);
  }

  if (candidateBundles.isEmpty) {
    if (bundleId == nilUuid ||
        (minBundleId.isNotEmpty && bundleId.compareTo(minBundleId) <= 0)) {
      return null;
    }
    return _initBundleRollbackUpdateInfo;
  }

  Bundle? rollbackCandidate;
  Bundle? currentBundle;

  for (final b in candidateBundles) {
    if (b.id == bundleId) {
      currentBundle = b;
    } else if (bundleId != nilUuid && b.id.compareTo(bundleId) < 0) {
      if (rollbackCandidate == null ||
          b.id.compareTo(rollbackCandidate.id) > 0) {
        rollbackCandidate = b;
      }
    }
  }

  final updateCandidate = _findLatestEligibleUpdateCandidate(
    candidateBundles,
    bundleId,
    cohort,
  );
  final currentBundleEligible =
      currentBundle != null &&
      _isEligibleUpdateCandidate(currentBundle, cohort);

  if (bundleId == nilUuid) {
    if (updateCandidate != null) {
      return _makeResponse(updateCandidate, UpdateStatus.update);
    }
    return null;
  }

  if (currentBundleEligible) {
    if (updateCandidate != null) {
      return _makeResponse(updateCandidate, UpdateStatus.update);
    }
    return null;
  }

  if (updateCandidate != null) {
    return _makeResponse(updateCandidate, UpdateStatus.update);
  }
  if (rollbackCandidate != null) {
    return _makeResponse(rollbackCandidate, UpdateStatus.rollback);
  }

  if (minBundleId.isNotEmpty && bundleId.compareTo(minBundleId) <= 0) {
    return null;
  }
  return _initBundleRollbackUpdateInfo;
}

/// Resolve update info using the fingerprint strategy.
Future<UpdateInfo?> _fingerprintStrategy(
  List<Bundle> bundles,
  FingerprintGetBundlesArgs args,
) async {
  final channel = args.channel;
  final minBundleId = args.minBundleId;
  final platform = args.platform;
  final fingerprintHash = args.fingerprintHash;
  final bundleId = args.bundleId;
  final cohort = args.cohort;

  final candidateBundles = <Bundle>[];

  for (final b in bundles) {
    if (b.platform != platform ||
        b.channel != channel ||
        b.fingerprintHash == null ||
        b.fingerprintHash != fingerprintHash ||
        !b.enabled ||
        (minBundleId.isNotEmpty && b.id.compareTo(minBundleId) < 0)) {
      continue;
    }
    candidateBundles.add(b);
  }

  if (candidateBundles.isEmpty) {
    if (bundleId == nilUuid ||
        (minBundleId.isNotEmpty && bundleId.compareTo(minBundleId) <= 0)) {
      return null;
    }
    return _initBundleRollbackUpdateInfo;
  }

  Bundle? rollbackCandidate;
  Bundle? currentBundle;

  for (final b in candidateBundles) {
    if (b.id == bundleId) {
      currentBundle = b;
    } else if (bundleId != nilUuid && b.id.compareTo(bundleId) < 0) {
      if (rollbackCandidate == null ||
          b.id.compareTo(rollbackCandidate.id) > 0) {
        rollbackCandidate = b;
      }
    }
  }

  final updateCandidate = _findLatestEligibleUpdateCandidate(
    candidateBundles,
    bundleId,
    cohort,
  );
  final currentBundleEligible =
      currentBundle != null &&
      _isEligibleUpdateCandidate(currentBundle, cohort);

  if (bundleId == nilUuid) {
    if (updateCandidate != null) {
      return _makeResponse(updateCandidate, UpdateStatus.update);
    }
    return null;
  }

  if (currentBundleEligible) {
    if (updateCandidate != null) {
      return _makeResponse(updateCandidate, UpdateStatus.update);
    }
    return null;
  }

  if (updateCandidate != null) {
    return _makeResponse(updateCandidate, UpdateStatus.update);
  }
  if (rollbackCandidate != null) {
    return _makeResponse(rollbackCandidate, UpdateStatus.rollback);
  }

  if (minBundleId.isNotEmpty && bundleId.compareTo(minBundleId) <= 0) {
    return null;
  }
  return _initBundleRollbackUpdateInfo;
}

/// Resolve update information from a list of candidate bundles.
///
/// Dispatches to [AppVersionGetBundlesArgs] or [FingerprintGetBundlesArgs]
/// strategy based on [args].
Future<UpdateInfo?> getUpdateInfo(
  List<Bundle> bundles,
  GetBundlesArgs args,
) async {
  if (args is AppVersionGetBundlesArgs) {
    return _appVersionStrategy(bundles, args);
  }
  if (args is FingerprintGetBundlesArgs) {
    return _fingerprintStrategy(bundles, args);
  }
  return null;
}
