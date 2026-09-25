import 'types.dart';

/// Compare a bundle ID field against an expected value with a comparator.
bool _compareValue(String value, String? expected, String comparator) {
  if (expected == null) return true;
  final cmp = value.compareTo(expected);
  switch (comparator) {
    case 'eq':
      return cmp == 0;
    case 'gt':
      return cmp > 0;
    case 'gte':
      return cmp >= 0;
    case 'lt':
      return cmp < 0;
    case 'lte':
      return cmp <= 0;
    default:
      return true;
  }
}

/// Check whether a bundle ID matches the given filter.
bool bundleIdMatchesFilter(String id, DatabaseBundleIdFilter? filter) {
  if (filter == null) return true;
  if (filter.ins != null && !filter.ins!.contains(id)) return false;
  return _compareValue(id, filter.eq, 'eq') &&
      _compareValue(id, filter.gt, 'gt') &&
      _compareValue(id, filter.gte, 'gte') &&
      _compareValue(id, filter.lt, 'lt') &&
      _compareValue(id, filter.lte, 'lte');
}

/// Check whether a bundle matches all fields in a where clause.
bool bundleMatchesQueryWhere(Bundle bundle, DatabaseBundleQueryWhere? where) {
  if (where == null) return true;
  if (where.channel != null && bundle.channel != where.channel) return false;
  if (where.platform != null && bundle.platform != where.platform) return false;
  if (where.enabled != null && bundle.enabled != where.enabled) return false;
  if (!bundleIdMatchesFilter(bundle.id, where.id)) return false;
  if (where.targetAppVersionNotNull == true &&
      bundle.targetAppVersion == null) {
    return false;
  }
  if (where.targetAppVersion != null &&
      bundle.targetAppVersion != where.targetAppVersion) {
    return false;
  }
  if (where.targetAppVersionIn != null &&
      !where.targetAppVersionIn!.contains(bundle.targetAppVersion ?? '')) {
    return false;
  }
  if (where.fingerprintHash != null &&
      bundle.fingerprintHash != where.fingerprintHash) {
    return false;
  }
  return true;
}

/// Sort bundles by ID in the specified direction.
List<Bundle> sortBundles(
  List<Bundle> bundles,
  DatabaseBundleQueryOrder? orderBy,
) {
  final direction = orderBy?.direction ?? 'desc';
  final sorted = List<Bundle>.from(bundles);
  sorted.sort((a, b) {
    final result = a.id.compareTo(b.id);
    return direction == 'asc' ? result : -result;
  });
  return sorted;
}
