import 'package:flutter_patcher_core/flutter_patcher_core.dart' show Bundle;

import 'bundle_unit_of_work.dart';
import 'bundle_unit_of_work_store.dart';

/// Resolver interface for looking up bundles within a request context.
abstract class RequestUpdateBundleResolver {
  bool get hasSeededBundles;
  Bundle? peek(String bundleId);
  Future<Bundle?> getById(
    String bundleId,
    Future<Bundle?> Function() loadBundleById,
  );
}

List<Bundle> _toSeeds(List<Bundle?> seeds) =>
    seeds.whereType<Bundle>().toList();

/// Seed bundles into the unit of work for a given context.
void seedRequestUpdateBundles(
  Map<String, Object?>? context,
  List<Bundle?> seeds,
) {
  final unitOfWork = getRequestBundleUnitOfWork(context);
  if (unitOfWork == null) return;
  final nextSeeds = _toSeeds(seeds);
  if (nextSeeds.isEmpty) return;
  unitOfWork.seed(nextSeeds);
}

/// Return the seeded bundles for the given context.
List<Bundle> getRequestUpdateBundleSeeds(Map<String, Object?>? context) {
  return getRequestBundleUnitOfWork(context)?.seededBundles() ?? const [];
}

/// Create a resolver backed by a BundleUnitOfWork.
RequestUpdateBundleResolver createRequestUpdateBundleResolver(
  Map<String, Object?>? context,
) {
  final unitOfWork =
      getRequestBundleUnitOfWork(context) ?? BundleUnitOfWork();
  return _RequestUpdateBundleResolverImpl(unitOfWork);
}

class _RequestUpdateBundleResolverImpl implements RequestUpdateBundleResolver {
  _RequestUpdateBundleResolverImpl(this._unitOfWork);

  final BundleUnitOfWork _unitOfWork;

  @override
  bool get hasSeededBundles => _unitOfWork.hasSeeds();

  @override
  Bundle? peek(String bundleId) => _unitOfWork.peek(bundleId);

  @override
  Future<Bundle?> getById(
    String bundleId,
    Future<Bundle?> Function() loadBundleById,
  ) =>
      _unitOfWork.getById(bundleId, loadBundleById);
}
