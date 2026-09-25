import 'query_bundles.dart';
import 'types.dart';

/// Change operation tracked by the unit of work.
enum BundleChangeOperation { insert, update, delete }

/// A recorded bundle change with optional before-snapshot.
class BundleChange {
  const BundleChange({required this.operation, required this.data});

  final BundleChangeOperation operation;
  final Bundle data;
}

class _TrackedBundleChange {
  _TrackedBundleChange({
    required this.operation,
    required this.data,
    required this.before,
  });

  BundleChangeOperation operation;
  Bundle data;
  Bundle? before;
}

/// Discriminated union for in-memory entry store.
sealed class _BundleEntry {
  const _BundleEntry();
}

class _PresentEntry extends _BundleEntry {
  const _PresentEntry(this.bundle);
  final Bundle bundle;
}

class _DeletedEntry extends _BundleEntry {
  const _DeletedEntry(this.bundle);
  final Bundle bundle;
}

class _MissingEntry extends _BundleEntry {
  const _MissingEntry();
}

/// Result of peeking at a tracked change.
sealed class TrackedBundleValue {
  const TrackedBundleValue();
}

class TrackedBundleFound extends TrackedBundleValue {
  const TrackedBundleFound(this.value);
  final Bundle? value;
}

class TrackedBundleNotFound extends TrackedBundleValue {
  const TrackedBundleNotFound();
}

/// In-memory change tracker for a set of bundles.
///
/// Provides deduped async loads, insert/update/delete tracking, and overlay
/// logic for paginated query results.
///
/// Faithful port of hot-updater `bundleUnitOfWork.ts`.
class BundleUnitOfWork {
  final _entries = <String, _BundleEntry>{};
  final _pendingLoads = <String, Future<Bundle?>>{};
  final _changes = <String, _TrackedBundleChange>{};
  final _seededIds = <String>{};

  /// Pre-populate entries from seed bundles.
  void seed(List<Bundle?> seeds) {
    for (final seed in seeds) {
      if (seed == null) continue;
      _seededIds.add(seed.id);
      if (!_changes.containsKey(seed.id)) {
        _entries[seed.id] = _PresentEntry(seed);
      }
    }
  }

  bool hasSeeds() => _seededIds.isNotEmpty;

  List<Bundle> seededBundles() {
    final bundles = <Bundle>[];
    for (final id in _seededIds) {
      final entry = _entries[id];
      if (entry is _PresentEntry) {
        bundles.add(entry.bundle);
      }
    }
    return bundles;
  }

  /// Synchronous peek at a bundle by ID from the in-memory store.
  Bundle? peek(String bundleId) {
    final entry = _entries[bundleId];
    return entry is _PresentEntry ? entry.bundle : null;
  }

  /// Check if a bundle has a pending tracked change.
  TrackedBundleValue peekChanged(String bundleId) {
    if (!_changes.containsKey(bundleId)) {
      return const TrackedBundleNotFound();
    }
    final entry = _entries[bundleId];
    return TrackedBundleFound(entry is _PresentEntry ? entry.bundle : null);
  }

  /// Deduped async lookup: returns cached entry, coalesces concurrent loads,
  /// and stores the result for future peeks.
  Future<Bundle?> getById(
    String bundleId,
    Future<Bundle?> Function() loadBundleById,
  ) async {
    final entry = _entries[bundleId];
    if (entry != null) {
      return entry is _PresentEntry ? entry.bundle : null;
    }

    final pending = _pendingLoads[bundleId];
    if (pending != null) return pending;

    final load = loadBundleById().then<Bundle?>(
      (bundle) {
        _pendingLoads.remove(bundleId);
        final currentEntry = _entries[bundleId];
        if (currentEntry != null) {
          return currentEntry is _PresentEntry ? currentEntry.bundle : null;
        }
        _entries[bundleId] = bundle != null
            ? _PresentEntry(bundle)
            : const _MissingEntry();
        return bundle;
      },
      onError: (Object error) {
        _pendingLoads.remove(bundleId);
        throw error;
      },
    );
    _pendingLoads[bundleId] = load;
    return load;
  }

  /// Merge in-memory changes over a database query result, filter by where,
  /// sort, and slice to limit.
  List<Bundle> overlayList(
    List<Bundle> bundles, {
    required int limit,
    required DatabaseBundleQueryWhere? where,
    required DatabaseBundleQueryOrder? orderBy,
  }) {
    final dataById = <String, Bundle>{};

    for (final bundle in bundles) {
      final entry = _entries[bundle.id];
      if (entry is _DeletedEntry) continue;
      if (entry is _PresentEntry) {
        if (bundleMatchesQueryWhere(entry.bundle, where)) {
          dataById[entry.bundle.id] = entry.bundle;
        }
        continue;
      }
      _entries[bundle.id] = _PresentEntry(bundle);
      dataById[bundle.id] = bundle;
    }

    for (final change in _changes.values) {
      if (change.operation == BundleChangeOperation.delete ||
          change.operation == BundleChangeOperation.insert) {
        dataById.remove(change.data.id);
        continue;
      }
      if (bundleMatchesQueryWhere(change.data, where)) {
        dataById[change.data.id] = change.data;
      } else {
        dataById.remove(change.data.id);
      }
    }

    return sortBundles(dataById.values.toList(), orderBy).take(limit).toList();
  }

  void markInsert(Bundle bundle) {
    _entries[bundle.id] = _PresentEntry(bundle);
    _changes[bundle.id] = _TrackedBundleChange(
      operation: BundleChangeOperation.insert,
      data: bundle,
      before: null,
    );
  }

  void markUpdate(Bundle bundle) {
    final prev = _changes[bundle.id];
    final prevEntry = _entries[bundle.id];
    final op = prev?.operation ?? BundleChangeOperation.update;
    _entries[bundle.id] = _PresentEntry(bundle);
    _changes[bundle.id] = _TrackedBundleChange(
      operation: op,
      data: bundle,
      before:
          prev?.before ??
          (prevEntry is _PresentEntry ? prevEntry.bundle : null),
    );
  }

  void markDelete(Bundle bundle) {
    final prev = _changes[bundle.id];
    final prevEntry = _entries[bundle.id];
    _entries[bundle.id] = _DeletedEntry(bundle);
    _changes[bundle.id] = _TrackedBundleChange(
      operation: BundleChangeOperation.delete,
      data: bundle,
      before:
          prev?.before ??
          (prevEntry is _PresentEntry ? prevEntry.bundle : bundle),
    );
  }

  List<BundleChange> changedSets() {
    return _changes.values
        .map((c) => BundleChange(operation: c.operation, data: c.data))
        .toList();
  }

  bool hasChanges() => _changes.isNotEmpty;

  int listFetchExtraCount() {
    return _changes.values
        .where(
          (c) =>
              c.operation == BundleChangeOperation.update ||
              c.operation == BundleChangeOperation.delete,
        )
        .length;
  }

  int totalDelta(DatabaseBundleQueryWhere? where) {
    var total = 0;
    for (final change in _changes.values) {
      if (change.operation == BundleChangeOperation.insert) continue;
      final matchedBefore =
          change.before != null &&
          bundleMatchesQueryWhere(change.before!, where);
      final matchesAfter =
          change.operation == BundleChangeOperation.update &&
          bundleMatchesQueryWhere(change.data, where);
      if (matchedBefore && !matchesAfter) {
        total -= 1;
      } else if (!matchedBefore && matchesAfter) {
        total += 1;
      }
    }
    return total;
  }

  void clear() {
    _entries.clear();
    _pendingLoads.clear();
    _changes.clear();
    _seededIds.clear();
  }
}
