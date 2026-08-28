/// Faithful port of hot-updater `packages/core/src/bundleArtifacts.ts`.
///
/// Utility functions for reading and normalizing bundle patch metadata
/// from the flexible `Bundle` / `BundlePatchArtifact` shape.
library;

import 'bundle.dart';
import 'bundle_patch_artifact.dart';

/// Identity — returns the metadata as-is.
/// (TS version strips artifact-specific keys; Dart uses strong types so
/// there is nothing to strip.)
Map<String, Object?>? stripBundleArtifactMetadata(
  Map<String, Object?>? metadata,
) =>
    metadata;

/// Extract `manifestStorageUri` from a bundle, defaulting to null.
String? getManifestStorageUri(Bundle bundle) => bundle.manifestStorageUri;

/// Extract `manifestFileHash` from a bundle, defaulting to null.
String? getManifestFileHash(Bundle bundle) => bundle.manifestFileHash;

/// Extract `assetBaseStorageUri` from a bundle, defaulting to null.
String? getAssetBaseStorageUri(Bundle bundle) => bundle.assetBaseStorageUri;

/// Deduplicate patches by [BundlePatchArtifact.baseBundleId], keeping the
/// first occurrence (by insertion order).
List<BundlePatchArtifact> getBundlePatches(Bundle bundle) {
  final patches = bundle.patches;
  if (patches == null || patches.isEmpty) return const [];

  final seenBaseBundleIds = <String>{};
  return patches.where((patch) {
    if (seenBaseBundleIds.contains(patch.baseBundleId)) return false;
    seenBaseBundleIds.add(patch.baseBundleId);
    return true;
  }).toList();
}
