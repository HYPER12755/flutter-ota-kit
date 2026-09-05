import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show PatchApplyPhase, PatchApplyProgress;

/// Snapshot of the forced-update progress overlay's visual state.
///
/// Drives every animated value in [OtaProgressOverlay]. The manager updates
/// this via [ValueNotifier] so the widget rebuilds without a setState dance.
class OtaOverlayState {
  final PatchApplyPhase? phase;

  /// Download/verify progress in [0.0, 1.0]. Null when the server does not
  /// provide a content-length.
  final double? fraction;

  /// Server-provided human-readable update message ("New onboarding flow",
  /// "Critical security fix", etc.). May be null/empty.
  final String? message;

  /// True when the install failed; the UI switches to an error variant.
  final bool hasError;

  /// Developer-facing error description shown when [hasError] is true.
  final String? errorText;

  /// Target version (the bundle being installed). Shown as "Updating to 1.0.1".
  final String? targetVersion;

  /// The version currently on disk before the install. Shown as
  /// "1.0.0 → 1.0.1" together with [targetVersion].
  final String? currentVersion;

  /// Optional user-facing error hint shown below [errorText] when the install
  /// fails. Used to tell the user "relaunch the app to retry" / "check your
  /// network" etc. without making the SDK guess the underlying cause.
  final String? errorHint;

  const OtaOverlayState({
    this.phase,
    this.fraction,
    this.message,
    this.hasError = false,
    this.errorText,
    this.targetVersion,
    this.currentVersion,
    this.errorHint,
  });

  /// Returns a new [OtaOverlayState] with the given fields replaced. A
  /// sentinel object is used for [hasError] so the caller can clear it
  /// (passing `false` to switch back to the progress variant after an error).
  OtaOverlayState copyWith({
    PatchApplyPhase? phase,
    double? fraction,
    String? message,
    Object? hasError = _unset,
    String? errorText,
    String? targetVersion,
    String? currentVersion,
    String? errorHint,
  }) {
    return OtaOverlayState(
      phase: phase ?? this.phase,
      fraction: fraction ?? this.fraction,
      message: message ?? this.message,
      hasError: identical(hasError, _unset) ? this.hasError : hasError as bool,
      errorText: errorText ?? this.errorText,
      targetVersion: targetVersion ?? this.targetVersion,
      currentVersion: currentVersion ?? this.currentVersion,
      errorHint: errorHint ?? this.errorHint,
    );
  }
}

/// Sentinel for [OtaOverlayState.copyWith] — allows unsetting booleans.
const Object _unset = Object();

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

/// Default retry hint shown when an error occurs and no override is given.
const String _defaultErrorHint = 'Close the app and reopen to retry.';

/// The visual overlay shown during a forced OTA update.
///
/// Renders a centered card with:
///   * a circular progress ring with the spinner in the center,
///   * the current phase label,
///   * the from→to version transition (when both are known),
///   * the server-provided message,
///   * a slim determinate linear bar (when [OtaOverlayState.fraction] is known),
///   * an error variant with a retry hint.
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
    PatchApplyPhase.verifying: 'Verifying integrity',
    PatchApplyPhase.finalizing: 'Installing patch',
  };

  /// Computes the "from → to" version line, e.g. "1.0.0 → 1.0.1".
  /// Returns null when either side is missing.
  String? _versionTransition(OtaOverlayState s) {
    final from = s.currentVersion;
    final to = s.targetVersion;
    if (from == null || from.isEmpty || to == null || to.isEmpty) return null;
    if (from == to) return to; // skip the arrow if already on this version
    return '$from  →  $to';
  }

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
        final pctText = pct != null
            ? '${(pct.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%'
            : null;
        final accent = s.hasError ? scheme.error : scheme.primary;
        final onSurfaceDim = scheme.onSurface.withValues(alpha: 0.7);
        final ringBg = scheme.onSurface.withValues(alpha: 0.12);
        final versionLine = _versionTransition(s);
        final message = s.message;

        return Semantics(
          label: s.hasError
              ? 'Update failed. ${s.errorText ?? ''}'
              : 'Updating app, ${phaseText.toLowerCase()}. ${pctText ?? ''}',
          liveRegion: true,
          child: Material(
            color: Colors.black54,
            child: Stack(
              children: [
                if (dismissible)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        // The overlay intentionally ignores user dismissal — the
                        // SDK owns the install. The flag exists only so tests
                        // can opt-in.
                      },
                    ),
                  ),
                Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 420),
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: scheme.onSurface.withValues(alpha: 0.06),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 32,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ProgressRing(
                          fraction: pct,
                          color: accent,
                          trackColor: ringBg,
                          hasError: s.hasError,
                          isDownloading: s.phase == PatchApplyPhase.downloading,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          phaseText,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (versionLine != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            versionLine,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: onSurfaceDim,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                        if (message != null && message.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Text(
                            message,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: onSurfaceDim,
                            ),
                          ),
                        ],
                        if (s.hasError) ...[
                          const SizedBox(height: 12),
                          _ErrorBlock(
                            errorText: s.errorText,
                            hint: s.errorHint ?? _defaultErrorHint,
                            errorColor: scheme.error,
                            hintColor: onSurfaceDim,
                            bodyStyle: theme.textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 18),
                        if (pctText != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              pctText,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 8,
                            backgroundColor: ringBg,
                            valueColor: AlwaysStoppedAnimation(accent),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Circular progress ring with the spinner rendered inside. Falls back to
/// a rotating braille spinner when [fraction] is unknown.
class _ProgressRing extends StatelessWidget {
  final double? fraction;
  final Color color;
  final Color trackColor;
  final bool hasError;
  final bool isDownloading;

  const _ProgressRing({
    required this.fraction,
    required this.color,
    required this.trackColor,
    required this.hasError,
    required this.isDownloading,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      height: 88,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(88, 88),
            painter: _RingPainter(
              fraction: fraction,
              color: color,
              trackColor: trackColor,
            ),
          ),
          if (isDownloading || fraction == null)
            _DotSpinner(color: color)
          else
            Icon(
              hasError ? Icons.error_outline : Icons.check_rounded,
              color: color,
              size: 32,
            ),
        ],
      ),
    );
  }
}

/// Renders the ring background + the determinate progress arc.
class _RingPainter extends CustomPainter {
  final double? fraction;
  final Color color;
  final Color trackColor;

  _RingPainter({
    required this.fraction,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = 6.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - stroke) / 2;

    final track = Paint()
      ..color = trackColor
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    final f = fraction;
    if (f == null) return;
    final progress = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final sweep = (f.clamp(0.0, 1.0)) * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      progress,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
}

/// Braille spinner widget — kept for the indeterminate phase (no progress
/// yet known) and as the inner glyph while downloading.
class _DotSpinner extends StatefulWidget {
  final Color color;
  const _DotSpinner({required this.color});

  @override
  State<_DotSpinner> createState() => _DotSpinnerState();
}

class _DotSpinnerState extends State<_DotSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
            vsync: this,
            duration: Duration(milliseconds: 80 * _brailleSpinner.length),
          )
          ..addListener(_tick)
          ..repeat();
  }

  void _tick() {
    if (!mounted) return;
    setState(() => _index = (_index + 1) % _brailleSpinner.length);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    _brailleSpinner[_index],
    style: TextStyle(
      fontSize: 26,
      height: 1,
      fontWeight: FontWeight.bold,
      color: widget.color,
      fontFamily: 'monospace',
    ),
  );
}

/// Error block: red message on top, retry hint on bottom.
class _ErrorBlock extends StatelessWidget {
  final String? errorText;
  final String hint;
  final Color errorColor;
  final Color hintColor;
  final TextStyle? bodyStyle;

  const _ErrorBlock({
    required this.errorText,
    required this.hint,
    required this.errorColor,
    required this.hintColor,
    required this.bodyStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: errorColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: errorColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (errorText != null && errorText!.isNotEmpty)
            Text(errorText!, style: bodyStyle?.copyWith(color: errorColor)),
          const SizedBox(height: 4),
          Text(hint, style: bodyStyle?.copyWith(color: hintColor)),
        ],
      ),
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
  final ValueNotifier<OtaOverlayState> _state = ValueNotifier(
    const OtaOverlayState(),
  );
  OverlayEntry? _entry;
  bool _disposed = false;

  /// Optional resolver used as a fallback when no [OverlayState] has been
  /// registered (e.g. the app provided [FlutterPatcher.navigatorKey] instead of
  /// wrapping with [FlutterOtaApp]). Wired by the SDK entrypoint.
  OverlayState? Function()? _resolver;

  /// How long the error state is shown before the overlay is removed. Long
  /// enough to read the message + retry hint.
  static const Duration errorDwell = Duration(seconds: 6);

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
  OtaOverlayHandle? begin({
    String? message,
    String? targetVersion,
    String? currentVersion,
    String? errorHint,
  }) {
    if (_disposed) return null;
    final overlay = _overlayState ?? _resolver?.call();
    if (overlay == null) return null;
    _state.value = OtaOverlayState(
      message: message,
      targetVersion: targetVersion,
      currentVersion: currentVersion,
      errorHint: errorHint,
    );
    _entry = OverlayEntry(builder: (_) => OtaProgressOverlay(state: _state));
    overlay.insert(_entry!);
    return OtaOverlayHandle._(this);
  }

  void _update(PatchApplyProgress progress) {
    if (_disposed || _entry == null) return;
    _state.value = _state.value.copyWith(
      phase: progress.phase,
      fraction: progress.fraction,
    );
  }

  void _end({bool hasError = false, String? errorText}) {
    if (_disposed || _entry == null) return;
    _state.value = _state.value.copyWith(
      hasError: hasError,
      errorText: errorText,
    );
    // Let the error state paint briefly, then remove. Use a mounted check via
    // the OverlayEntry so we don't try to remove a disposed entry.
    final entry = _entry;
    Future.delayed(hasError ? errorDwell : Duration.zero, () {
      if (_disposed) return;
      entry?.remove();
      if (identical(_entry, entry)) _entry = null;
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
