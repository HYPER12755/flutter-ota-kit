import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show Bundle, GetBundlesArgs, UpdateInfo, nilUuid;

import 'get_update_info.dart' show getUpdateInfo;
import 'request_update_bundle_state.dart' show seedRequestUpdateBundles;

/// Options for [resolveUpdateInfoFromBundles].
class ResolveUpdateInfoFromBundlesOptions {
  const ResolveUpdateInfoFromBundlesOptions({
    required this.args,
    required this.bundles,
    this.context,
  });

  final GetBundlesArgs args;
  final List<Bundle> bundles;
  final Map<String, Object?>? context;
}

Bundle? _findSeedBundle(List<Bundle> bundles, String bundleId) {
  for (final bundle in bundles) {
    if (bundle.id == bundleId) return bundle;
  }
  return null;
}

/// Resolve update information from pre-loaded bundles and seed the
/// request unit of work with the matched bundles.
Future<UpdateInfo?> resolveUpdateInfoFromBundles(
  ResolveUpdateInfoFromBundlesOptions options,
) async {
  final info = await getUpdateInfo(options.bundles, options.args);
  if (info == null) return null;

  seedRequestUpdateBundles(options.context, [
    _findSeedBundle(options.bundles, info.id),
    options.args.bundleId == nilUuid
        ? null
        : _findSeedBundle(options.bundles, options.args.bundleId),
  ]);

  return info;
}
