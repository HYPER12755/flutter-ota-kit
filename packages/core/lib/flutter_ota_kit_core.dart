/// flutter_ota_kit core — Dart translation of hot-updater's packages/core.
///
/// Pure Dart, no Flutter dependency. Modules:
/// - types:    bundle/update data model (platform, status, strategy)
/// - rollout:  deterministic staged-rollout cohort math
/// - uuid:     uuidv7 generation + NIL sentinel
library;

// Data model (one module per concept).
export 'src/platform.dart';
export 'src/status.dart';
export 'src/strategy.dart';
export 'src/metadata.dart';
export 'src/bundle_patch_artifact.dart';
export 'src/changed_asset.dart';
export 'src/bundle.dart';
export 'src/app_update_info.dart';
export 'src/get_bundles_args.dart';
export 'src/update_bundle_params.dart';

// Algorithms.
export 'src/rollout.dart';
export 'src/semver.dart';
export 'src/uuid.dart';

// Bundle artifact helpers.
export 'src/bundle_artifacts.dart';

export 'src/patch_info.dart';
