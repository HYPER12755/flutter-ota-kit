import 'package:flutter/widgets.dart';

import 'ota_progress_overlay.dart' show OtaOverlayManager;

/// App-level host that lets [FlutterPatcher] show the forced-update progress
/// overlay without the consuming app writing any UI code.
///
/// Wrap your app once:
///
/// ```dart
/// void main() => runApp(FlutterOtaApp(child: MyApp()));
/// ```
///
/// This makes the SDK's root [OverlayState] available to [OtaOverlayManager] so
/// it can inject the "downloading / verifying / installing" overlay during a
/// forced update. The overlay auto-appears for `shouldForceUpdate` bundles and
/// is removed once the process restarts (or the update fails).
///
/// Set [showUpdateUi] to `false` to disable the built-in overlay entirely (the
/// SDK still applies forced updates, just without the progress UI).
///
/// As an alternative to wrapping, assign [FlutterPatcher.navigatorKey] to your
/// [MaterialApp.navigatorKey]; the overlay manager will fall back to it.
class FlutterOtaApp extends StatefulWidget {
  final Widget child;
  final bool showUpdateUi;

  const FlutterOtaApp({
    super.key,
    required this.child,
    this.showUpdateUi = true,
  });

  @override
  State<FlutterOtaApp> createState() => _FlutterOtaAppState();
}

class _FlutterOtaAppState extends State<FlutterOtaApp> {
  final GlobalKey<OverlayState> _overlayKey = GlobalKey<OverlayState>();

  @override
  void initState() {
    super.initState();
    FlutterPatcherShowUpdateUiBinding.update(widget.showUpdateUi);
  }

  @override
  void didUpdateWidget(covariant FlutterOtaApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showUpdateUi != widget.showUpdateUi) {
      FlutterPatcherShowUpdateUiBinding.update(widget.showUpdateUi);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Root the app in an Overlay so its OverlayState is discoverable by the SDK
    // for injecting the forced-update progress UI. MaterialApp (the typical
    // `child`) nests its own route Overlay inside, which is fully supported.
    return Overlay(
      key: _overlayKey,
      initialEntries: [OverlayEntry(builder: (_) => widget.child)],
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = _overlayKey.currentState;
      if (state != null) OtaOverlayManager.instance.register(state);
    });
  }
}

/// Internal binding between the widget-level [showUpdateUi] flag and the
/// [FlutterPatcher] static flag, kept here so [flutter_ota_kit.dart] does not
/// depend on the overlay widget directly.
class FlutterPatcherShowUpdateUiBinding {
  const FlutterPatcherShowUpdateUiBinding._();

  static void update(bool value) {
    // Imported lazily via the patch function set by the SDK entrypoint.
    applyShowUpdateUi?.call(value);
  }

  static void Function(bool)? applyShowUpdateUi;
}
