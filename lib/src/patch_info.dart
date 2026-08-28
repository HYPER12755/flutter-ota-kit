// Re-exported from `flutter_patcher_core` (the canonical, framework-agnostic
// home for the data model). The device SDK previously defined these here; they
// now live in core so the server client can produce `PatchInfo` without pulling
// in the Flutter plugin.
export 'package:flutter_patcher_core/flutter_patcher_core.dart'
    show
        PatchApplyError,
        PatchApplyPhase,
        PatchApplyProgress,
        PatchApplyResult,
        PatchCheckResult,
        PatchInfo;
