import 'bundle_unit_of_work.dart';

/// Per-context Unit of Work store.
///
/// Uses a plain Map instead of WeakMap (Dart has no WeakMap).
/// Context objects are long-lived request maps so normal Map is fine.
final Map<Object, BundleUnitOfWork> _requestUnitOfWorks = {};

/// Check if a context object is eligible for UoW tracking.
bool isUnitOfWorkContext(Object? value) =>
    value is Object && value is Map<String, Object?>;

/// Retrieve or lazily create a BundleUnitOfWork for the given context.
BundleUnitOfWork? getRequestBundleUnitOfWork(Object? context) {
  if (!isUnitOfWorkContext(context)) return null;
  return _requestUnitOfWorks.putIfAbsent(context!, () => BundleUnitOfWork());
}

/// Remove all UoW entries (for testing/cleanup).
void clearUnitOfWorkStore() => _requestUnitOfWorks.clear();
