import 'package:flutter/widgets.dart';

/// App-level host that lets [FlutterPatcher] show the forced-update progress
/// overlay without the consuming app writing any UI code.
///
/// Wrap your app once:
///
/// ```dart
/// void main() => runApp(FlutterOtaApp(child: MyApp()));
/// ```
///
/// The overlay is injected via [MaterialApp.navigatorKey] — your [MaterialApp]
/// must use [FlutterPatcher.navigatorKey]:
///
/// ```dart
/// MaterialApp(
///   navigatorKey: FlutterPatcher.navigatorKey,
///   ...
/// )
/// ```
///
/// Set [showUpdateUi] to `false` to disable the built-in overlay entirely (the
/// SDK still applies forced updates, just without the progress UI).
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
  Widget build(BuildContext context) => widget.child;
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
