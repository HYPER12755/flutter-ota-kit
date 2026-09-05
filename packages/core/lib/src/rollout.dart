/// Dart translation of hot-updater `packages/core/src/rollout.ts`.
///
/// Deterministic staged-rollout cohort math. Numeric cohorts are 1..1000;
/// each bundle gets a per-bundle deterministic shuffle so expanding a rollout
/// never drops devices that were already included.
library;

const int numericCohortSize = 1000;
const int defaultRolloutCohortCount = numericCohortSize;
const int maxCohortLength = 64;
const String invalidCohortErrorMessage =
    'Invalid cohort. Use 1-1000 or a lowercase slug without spaces, '
    'up to $maxCohortLength characters.';

final RegExp _digitsOnly = RegExp(r'^\d+$');
final RegExp _customCohortPattern = RegExp(r'^[a-z0-9-]+$');

int? _parseNumericCohortValue(String cohort) {
  if (!_digitsOnly.hasMatch(cohort)) {
    return null;
  }
  final parsed = int.tryParse(cohort);
  if (parsed == null || parsed < 1 || parsed > numericCohortSize) {
    return null;
  }
  return parsed;
}

int _positiveMod(int value, int modulus) =>
    ((value % modulus) + modulus) % modulus;

/// Java-style 32-bit signed rolling string hash (`(h<<5) - h + c`, truncated).
int _hashString(String value) {
  var hash = 0;
  for (var i = 0; i < value.length; i++) {
    final char = value.codeUnitAt(i);
    hash = _toSigned32((hash << 5) - hash + char);
  }
  return hash;
}

int _toSigned32(int v) {
  v &= 0xFFFFFFFF;
  return v >= 0x80000000 ? v - 0x100000000 : v;
}

int _gcd(int a, int b) {
  var x = a.abs();
  var y = b.abs();
  while (y != 0) {
    final next = x % y;
    x = y;
    y = next;
  }
  return x;
}

int _modularInverse(int value, int modulus) {
  var t = 0;
  var newT = 1;
  var r = modulus;
  var newR = _positiveMod(value, modulus);
  while (newR != 0) {
    final quotient = r ~/ newR;
    final tmpT = t - quotient * newT;
    t = newT;
    newT = tmpT;
    final tmpR = r - quotient * newR;
    r = newR;
    newR = tmpR;
  }
  if (r > 1) {
    throw ArgumentError('No modular inverse for $value mod $modulus');
  }
  return _positiveMod(t, modulus);
}

({int multiplier, int offset, int inverseMultiplier}) _rolloutShuffleParameters(
  String bundleId,
) {
  var multiplier = _positiveMod(_hashString('$bundleId:multiplier'), 997);
  if (multiplier == 0) {
    multiplier = 1;
  }
  while (_gcd(multiplier, numericCohortSize) != 1) {
    multiplier = _positiveMod(multiplier + 1, numericCohortSize);
    if (multiplier == 0) {
      multiplier = 1;
    }
  }
  final offset = _positiveMod(
    _hashString('$bundleId:offset'),
    numericCohortSize,
  );
  return (
    multiplier: multiplier,
    offset: offset,
    inverseMultiplier: _modularInverse(multiplier, numericCohortSize),
  );
}

/// Clamps a rollout percentage to 0..1000 (per-mille). Null means 100%.
int normalizeRolloutCohortCount(int? rolloutCohortCount) {
  if (rolloutCohortCount == null) {
    return defaultRolloutCohortCount;
  }
  if (rolloutCohortCount <= 0) {
    return 0;
  }
  if (rolloutCohortCount >= numericCohortSize) {
    return numericCohortSize;
  }
  return rolloutCohortCount.floor();
}

String normalizeCohortValue(String cohort) {
  final normalized = cohort.trim().toLowerCase();
  final numeric = _parseNumericCohortValue(normalized);
  if (numeric != null) {
    return '$numeric';
  }
  return normalized;
}

int? getNumericCohortValue(String cohort) =>
    _parseNumericCohortValue(normalizeCohortValue(cohort));

bool isNumericCohort(String cohort) => getNumericCohortValue(cohort) != null;

bool isCustomCohort(String cohort) {
  final normalized = normalizeCohortValue(cohort);
  return normalized.isNotEmpty &&
      normalized.length <= maxCohortLength &&
      !_digitsOnly.hasMatch(normalized) &&
      _customCohortPattern.hasMatch(normalized);
}

bool isValidCohort(String cohort) {
  final normalized = normalizeCohortValue(cohort);
  return isNumericCohort(normalized) || isCustomCohort(normalized);
}

/// Default cohort derived from a device identifier (ANDROID_ID etc.).
String getDefaultNumericCohort(String identifier) {
  final cohortValue =
      _positiveMod(_hashString(identifier), numericCohortSize) + 1;
  return '$cohortValue';
}

int getNumericCohortRolloutPosition(String bundleId, int cohortValue) {
  if (cohortValue < 1 || cohortValue > numericCohortSize) {
    throw ArgumentError('Invalid numeric cohort: $cohortValue');
  }
  final params = _rolloutShuffleParameters(bundleId);
  final zeroBasedCohort = cohortValue - 1;
  return _positiveMod(
    params.inverseMultiplier * (zeroBasedCohort - params.offset),
    numericCohortSize,
  );
}

List<int> getRolledOutNumericCohorts(String bundleId, int? rolloutCohortCount) {
  final normalized = normalizeRolloutCohortCount(rolloutCohortCount);
  if (normalized <= 0) {
    return [];
  }
  return List.generate(numericCohortSize, (index) => index + 1)
      .where(
        (cohortValue) =>
            normalized >= numericCohortSize ||
            getNumericCohortRolloutPosition(bundleId, cohortValue) < normalized,
      )
      .toList();
}

/// Mirrors hot-updater semantics exactly:
/// - explicit target_cohorts match always wins (even at 100%/excluded cohorts)
/// - no cohort provided: eligible only at full rollout
/// - custom (non-numeric) cohorts are ineligible for percentage rollouts
bool isCohortEligibleForUpdate(
  String bundleId,
  String? cohort,
  int? rolloutCohortCount,
  List<String>? targetCohorts,
) {
  final normalizedCohort = cohort == null ? null : normalizeCohortValue(cohort);
  final normalizedTargets =
      targetCohorts?.map(normalizeCohortValue).toList() ?? <String>[];

  if (normalizedCohort != null &&
      normalizedTargets.contains(normalizedCohort)) {
    return true;
  }

  final normalizedRollout = normalizeRolloutCohortCount(rolloutCohortCount);
  if (normalizedRollout <= 0) {
    return false;
  }
  if (normalizedCohort == null) {
    return normalizedRollout >= numericCohortSize;
  }

  final numericCohort = getNumericCohortValue(normalizedCohort);
  if (numericCohort == null) {
    return false;
  }
  if (normalizedRollout >= numericCohortSize) {
    return true;
  }
  return getNumericCohortRolloutPosition(bundleId, numericCohort) <
      normalizedRollout;
}
