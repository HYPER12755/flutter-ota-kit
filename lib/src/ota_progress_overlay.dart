import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show PatchApplyPhase, PatchApplyProgress;

/// Snapshot of the forced-update progress overlay's visual state.
class OtaOverlayState {
  final PatchApplyPhase? phase;
  final double? fraction;
  final String? message;
  final bool hasError;
  final String? errorText;

  const OtaOverlayState({
    this.phase,
    this.fraction,
    this.message,
    this.hasError = false,
    this.errorText,
  });

  OtaOverlayState copyWith({
    PatchApplyPhase? phase,
    double? fraction,
    String? message,
    bool? hasError,
    String? errorText,
  }) {
    return OtaOverlayState(
      phase: phase ?? this.phase,
      fraction: fraction ?? this.fraction,
      message: message ?? this.message,
      hasError: hasError ?? this.hasError,
      errorText: errorText ?? this.errorText,
    );
  }
}

/// Terminal-style rotating dot spinner ([⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]).
const List<String> _brailleSpinner = [
  '⠋',
  '⠙',
  '⠹',
  '⠸',
  '⠼',
  '⠴',
  '⠦',
  '⠧',
  '⠇',
  '⠏',
];

class _DotSpinner extends StatefulWidget {
  final Color color;
  const _DotSpinner({required this.color});

  @override
  State<_DotSpinner> createState() => _DotSpinnerState();
}

class _DotSpinnerState extends State<_DotSpinner> {
  late final Timer _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (mounted) setState(() => _index = (_index + 1) % _brailleSpinner.length);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
        _brailleSpinner[_index],
        style: TextStyle(
          fontSize: 22,
          height: 1,
          fontWeight: FontWeight.bold,
          color: widget.color,
          fontFamily: 'monospace',
        ),
      );
}

/// The visual overlay shown during a forced OTA update.
///
/// Renders a centered card with a terminal-style dot spinner, a determinate
/// slim progress bar (when the server reports a content length), the current
/// phase label + percentage, and the server-provided OTA [message] underneath.
class OtaProgressOverlay extends StatelessWidget {
  final ValueNotifier<OtaOverlayState> state;
  final bool dismissible;

  const OtaProgressOverlay({
    super.key,
    required this.state,
    this.dismissible = false,
  });

  static const Map<PatchApplyPhase, String> _phaseLabel = {
    PatchApplyPhase.downloading: 'Downloading update',
    PatchApplyPhase.verifying: 'Verifying signature',
    PatchApplyPhase.finalizing: 'Installing patch',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ValueListenableBuilder<OtaOverlayState>(
      valueListenable: state,
      builder: (context, s, _) {
        final phaseText = s.hasError
            ? 'Update failed'
            : (s.phase != null ? _phaseLabel[s.phase]! : 'Preparing update');
        final pct = s.fraction;
        final pctText = pct != null ? '${(pct * 100).toStringAsFixed(0)}%' : null;

        return Material(
          color: Colors.black54,
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25), // ignore: deprecated_member_use
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _DotSpinner(color: s.hasError ? scheme.error : scheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          phaseText,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (pctText != null)
                        Text(
                          pctText,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            color: scheme.onSurface.withOpacity(0.7), // ignore: deprecated_member_use
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 6,
                      backgroundColor: scheme.onSurface.withOpacity(0.12), // ignore: deprecated_member_use
                      valueColor: AlwaysStoppedAnimation(
                        s.hasError ? scheme.error : scheme.primary,
                      ),
                    ),
                  ),
                      if (s.message != null && s.message!.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      s.message!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withOpacity(0.7), // ignore: deprecated_member_use
                      ),
                    ),
                  ],
                  if (s.hasError && s.errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      s.errorText!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Drives the forced-update progress overlay from SDK code without requiring the
/// consuming app to build any UI.
///
/// An overlay host must be available for the overlay to appear. The recommended
/// (zero-code) way is to wrap the app in [FlutterOtaApp]; alternatively, assign
/// [FlutterPatcher.navigatorKey] to the app's [MaterialApp.navigatorKey]. If no
/// host is registered, [begin] returns `null` and the SDK silently applies the
/// update (graceful degradation — no crash, just no UI).
class OtaOverlayManager {
  OtaOverlayManager._();

  static final OtaOverlayManager instance = OtaOverlayManager._();

  OverlayState? _overlayState;
  final ValueNotifier<OtaOverlayState> _state =
      ValueNotifier(const OtaOverlayState());
  OverlayEntry? _entry;

  /// Optional resolver used as a fallback when no [OverlayState] has been
  /// registered (e.g. the app provided [FlutterPatcher.navigatorKey] instead of
  /// wrapping with [FlutterOtaApp]). Wired by the SDK entrypoint.
  OverlayState? Function()? _resolver;

  /// Set the fallback overlay resolver (used by [FlutterPatcher.navigatorKey]).
  void setResolver(OverlayState? Function()? resolver) => _resolver = resolver;

  /// Register the overlay host (called by [FlutterOtaApp] or via
  /// [FlutterPatcher.navigatorKey]).
  void register(OverlayState state) => _overlayState = state;

  /// Forget a previously registered host (mirrors [register]).
  void unregister(OverlayState state) {
    if (_overlayState == state) _overlayState = null;
  }

  /// Show the overlay. Returns a handle used to push progress / dismiss it, or
  /// `null` when no overlay host is available.
  OtaOverlayHandle? begin({String? message}) {
    final overlay = _overlayState ?? _resolver?.call();
    if (overlay == null) return null;
    _state.value = OtaOverlayState(message: message);
    _entry = OverlayEntry(
      builder: (_) => OtaProgressOverlay(state: _state),
    );
    overlay.insert(_entry!);
    return OtaOverlayHandle._(this);
  }

  void _update(PatchApplyProgress progress) {
    if (_entry == null) return;
    _state.value = _state.value.copyWith(
      phase: progress.phase,
      fraction: progress.fraction,
    );
  }

  void _end({bool hasError = false, String? errorText}) {
    if (_entry == null) return;
    _state.value = _state.value.copyWith(
      hasError: hasError,
      errorText: errorText,
    );
    // Let the error state paint briefly, then remove.
    Future.delayed(hasError ? const Duration(seconds: 2) : Duration.zero, () {
      _entry?.remove();
      _entry = null;
    });
  }
}

/// Handle returned by [OtaOverlayManager.begin] to update / dismiss the overlay.
class OtaOverlayHandle {
  OtaOverlayHandle._(this._manager);

  final OtaOverlayManager _manager;

  void update(PatchApplyProgress progress) => _manager._update(progress);

  void end({bool hasError = false, String? errorText}) =>
      _manager._end(hasError: hasError, errorText: errorText);
}
