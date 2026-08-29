// Re-exported from `flutter_ota_kit_core` (the canonical, framework-agnostic
// home for the data model). The device SDK previously defined these here; they
// now live in core so the server client can produce `PatchInfo` without pulling
// in the Flutter plugin.
export 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show
        PatchApplyError,
        PatchApplyPhase,
        PatchApplyProgress,
        PatchApplyResult,
        PatchCheckResult,
        PatchInfo;
