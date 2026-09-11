import 'dart:async';
import 'dart:math' as math;

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
  final String? targetVersion;
  final String? currentVersion;
  final String? errorHint;
  final String? bundleHash;
  final String? gitCommit;
  final String? commitMessage;
  final String? channel;
  final String? platform;
  final int? bytesPerSec;
  final List<LogLine> logs;
  final bool canRetry;

  /// Which step index is currently active (0-based). Steps that are done
  /// get a green checkmark; the active step gets the braille spinner.
  final int activeStep;

  const OtaOverlayState({
    this.phase,
    this.fraction,
    this.message,
    this.hasError = false,
    this.errorText,
    this.targetVersion,
    this.currentVersion,
    this.errorHint,
    this.bundleHash,
    this.gitCommit,
    this.commitMessage,
    this.channel,
    this.platform,
    this.bytesPerSec,
    this.logs = const [],
    this.canRetry = false,
    this.activeStep = 0,
  });

  OtaOverlayState copyWith({
    PatchApplyPhase? phase,
    double? fraction,
    String? message,
    Object? hasError = _unset,
    String? errorText,
    String? targetVersion,
    String? currentVersion,
    String? errorHint,
    String? bundleHash,
    String? gitCommit,
    String? channel,
    String? platform,
    int? bytesPerSec,
    List<LogLine>? logs,
    bool? canRetry,
    int? activeStep,
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
      bundleHash: bundleHash ?? this.bundleHash,
      gitCommit: gitCommit ?? this.gitCommit,
      commitMessage: commitMessage ?? this.commitMessage,
      channel: channel ?? this.channel,
      platform: platform ?? this.platform,
      bytesPerSec: bytesPerSec ?? this.bytesPerSec,
      logs: logs ?? this.logs,
      canRetry: canRetry ?? this.canRetry,
      activeStep: activeStep ?? this.activeStep,
    );
  }
}

/// A single terminal log line with color tag.
class LogLine {
  final String color;
  final String text;

  const LogLine(this.color, this.text);
}

const Object _unset = Object();

/// The 5 steps shown during a forced update.
const List<String> _stepLabels = [
  'Initializing update',
  'Downloading update',
  'Verifying hash',
  'Applying patch',
  'Finalizing',
];

/// Returns the display label for step [i]. On error, step 3 shows
/// "Skipping patch" instead of "Applying patch".
String _stepLabel(int i, bool hasError) {
  if (hasError && i == 3) return 'Skipping patch ✗';
  return _stepLabels[i];
}

/// Full-screen terminal-style forced-update overlay.
///
/// Top half: 5-step progress with braille spinner / checkmarks.
/// Bottom half: scrollable terminal log box.
class OtaProgressOverlay extends StatefulWidget {
  final ValueNotifier<OtaOverlayState> state;
  final bool dismissible;

  const OtaProgressOverlay({
    super.key,
    required this.state,
    this.dismissible = false,
  });

  @override
  State<OtaProgressOverlay> createState() => _OtaProgressOverlayState();
}

class _OtaProgressOverlayState extends State<OtaProgressOverlay> {
  int _spinnerIndex = 0;
  Timer? _spinnerTimer;

  static const _braille = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];

  @override
  void initState() {
    super.initState();
    _spinnerTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!mounted) return;
      setState(() => _spinnerIndex = (_spinnerIndex + 1) % _braille.length);
    });
  }

  @override
  void dispose() {
    _spinnerTimer?.cancel();
    super.dispose();
  }

  static const Map<String, Color> _logColors = {
    'green': Color(0xFF3FB950),
    'red': Color(0xFFF85149),
    'yellow': Color(0xFFD29922),
    'gray': Color(0xFF8B949E),
    'white': Color(0xFFC9D1D9),
    'cyan': Color(0xFF58A6FF),
    'success': Color(0xFF79C0FF),
  };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OtaOverlayState>(
      valueListenable: widget.state,
      builder: (context, s, _) {
        final spinner = _braille[_spinnerIndex];
        final pct = s.fraction;
        final pctText = pct != null
            ? '${(pct.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%'
            : '';

        return Material(
          color: const Color(0xFF0d1117),
          child: SafeArea(
            child: Column(
              children: [
                // ─── Top half: steps ───
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title
                        Center(
                          child: Text(
                            s.hasError ? 'Update failed' : 'Updating app',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFC9D1D9),
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Version line
                        if (s.currentVersion != null &&
                            s.targetVersion != null)
                          Center(
                            child: Text(
                              '${s.currentVersion}  →  ${s.targetVersion}',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 14,
                                color: Color(0xFF58A6FF),
                              ),
                            ),
                          ),
                        const SizedBox(height: 32),
                        // Steps
                        ...List.generate(_stepLabels.length, (i) {
                          final done = i < s.activeStep;
                          final active = i == s.activeStep && !s.hasError;
                          final failed = i == s.activeStep && s.hasError;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 24,
                                  child: done
                                      ? const Icon(Icons.check_rounded,
                                          size: 18,
                                          color: Color(0xFF79C0FF))
                                      : active
                                          ? Text(
                                              spinner,
                                              style: const TextStyle(
                                                fontFamily: 'monospace',
                                                fontSize: 16,
                                                color: Color(0xFF58A6FF),
                                              ),
                                            )
                                          : failed
                                              ? const Icon(Icons.close_rounded,
                                                  size: 18,
                                                  color: Color(0xFFF85149))
                                              : Text(
                                                  '${i + 1}',
                                                  style: const TextStyle(
                                                    fontFamily: 'monospace',
                                                    fontSize: 14,
                                                    color: Color(0xFF484F58),
                                                  ),
                                                ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _stepLabel(i, s.hasError),
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 14,
                                    color: done
                                        ? const Color(0xFF79C0FF)
                                        : active
                                            ? const Color(0xFFC9D1D9)
                                            : failed
                                                ? const Color(0xFFF85149)
                                                : const Color(0xFF484F58),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                // ─── Braille progress bar ───
                if (pct != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      children: [
                        _BrailleProgressBar(fraction: pct),
                        const SizedBox(height: 6),
                        Text(
                          pctText,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Color(0xFF8B949E),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                // ─── Bottom half: terminal log ───
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF30363D)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Terminal header
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: const BoxDecoration(
                            color: Color(0xFF21262D),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(10),
                              topRight: Radius.circular(10),
                            ),
                          ),
                          child: Row(
                            children: [
                              _dot(const Color(0xFFF85149)),
                              const SizedBox(width: 6),
                              _dot(const Color(0xFFD29922)),
                              const SizedBox(width: 6),
                              _dot(const Color(0xFF3FB950)),
                              const SizedBox(width: 12),
                              const Text(
                                'ota-log',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: Color(0xFF8B949E),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Log lines
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: _TerminalLog(
                              logs: s.logs,
                              logColors: _logColors,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Retry button (error only)
                if (s.hasError && s.canRetry)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: TextButton(
                      onPressed: () {},
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF58A6FF),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 12),
                        side: const BorderSide(color: Color(0xFF30363D)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        '[ Retry ]',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 48),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dot(Color color) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// Braille-character progress bar with animated spinner at the leading edge.
///
/// Smoothly interpolates over ~4 seconds so the bar visually catches up
/// to the actual download percentage.
class _BrailleProgressBar extends StatefulWidget {
  final double fraction;
  const _BrailleProgressBar({required this.fraction});

  @override
  State<_BrailleProgressBar> createState() => _BrailleProgressBarState();
}

class _BrailleProgressBarState extends State<_BrailleProgressBar> {
  int _spinIdx = 0;
  Timer? _spinTimer;
  double _displayFraction = 0;
  DateTime? _lastUpdate;

  static const _spinner = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];

  @override
  void initState() {
    super.initState();
    _displayFraction = widget.fraction;
    _lastUpdate = DateTime.now();
    _spinTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      setState(() {
        _spinIdx = (_spinIdx + 1) % _spinner.length;

        // Smooth interpolation: reach target in ~4 seconds
        // Use time-based lerp for consistent speed regardless of tick rate
        final now = DateTime.now();
        final dt = _lastUpdate != null
            ? now.difference(_lastUpdate!).inMilliseconds / 1000.0
            : 0.05;
        _lastUpdate = now;

        final diff = widget.fraction - _displayFraction;
        if (diff > 0.001) {
          // Lerp ~25% of remaining distance per frame → ~4s to reach 99%
          final speed = diff * (1 - math.pow(0.75, dt * 20));
          _displayFraction = (_displayFraction + speed).clamp(0.0, 1.0);
        } else {
          _displayFraction = widget.fraction;
        }
      });
    });
  }

  @override
  void didUpdateWidget(covariant _BrailleProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _spinTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const total = 30;
    final filled = (_displayFraction.clamp(0.0, 1.0) * total).floor();
    final empty = total - filled - 1;
    final spinChar = _spinner[_spinIdx];

    return Text(
      '${'⣿' * filled}$spinChar${'⠀' * empty}',
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 14,
        color: Color(0xFF58A6FF),
        letterSpacing: 0,
      ),
    );
  }
}

/// Scrollable terminal log view — no prefix, auto-scrolls to bottom.
class _TerminalLog extends StatefulWidget {
  final List<LogLine> logs;
  final Map<String, Color> logColors;

  const _TerminalLog({required this.logs, required this.logColors});

  @override
  State<_TerminalLog> createState() => _TerminalLogState();
}

class _TerminalLogState extends State<_TerminalLog> {
  final _controller = ScrollController();

  @override
  void didUpdateWidget(covariant _TerminalLog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.logs.length > oldWidget.logs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller.hasClients) {
          _controller.animateTo(
            _controller.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _controller,
      itemCount: widget.logs.length,
      itemBuilder: (context, i) {
        final line = widget.logs[i];
        final color = widget.logColors[line.color] ?? widget.logColors['gray']!;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            line.text,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: color,
            ),
          ),
        );
      },
    );
  }
}

/// Drives the forced-update progress overlay from SDK code.
class OtaOverlayManager {
  OtaOverlayManager._();

  static final OtaOverlayManager instance = OtaOverlayManager._();

  OverlayState? _overlayState;
  final ValueNotifier<OtaOverlayState> _state = ValueNotifier(
    const OtaOverlayState(),
  );
  OverlayEntry? _entry;
  bool _disposed = false;
  DateTime? _startTime;

  OverlayState? Function()? _resolver;

  /// Minimum time the overlay stays visible (7 seconds).
  static const Duration _minDuration = Duration(seconds: 7);

  /// Dwell time after patch is applied before restart.
  static const Duration _successDwell = Duration(seconds: 2);

  static const Duration errorDwell = Duration(seconds: 8);

  void setResolver(OverlayState? Function()? resolver) => _resolver = resolver;

  void register(OverlayState state) => _overlayState = state;

  void unregister(OverlayState state) {
    if (_overlayState == state) _overlayState = null;
  }

  OtaOverlayHandle? begin({
    String? message,
    String? commitMessage,
    String? targetVersion,
    String? currentVersion,
    String? errorHint,
    String? bundleHash,
    String? gitCommit,
    String? channel,
    String? platform,
  }) {
    if (_disposed) return null;
    final overlay = _overlayState ?? _resolver?.call();
    if (overlay == null) return null;

    _startTime = DateTime.now();

    final logs = <LogLine>[
      if (channel != null) LogLine('gray', 'channel  $channel'),
      if (platform != null) LogLine('gray', 'platform $platform'),
      if (bundleHash != null) LogLine('gray', 'hash     $bundleHash'),
      if (gitCommit != null) LogLine('gray', 'commit   $gitCommit'),
      if (commitMessage != null && commitMessage.isNotEmpty)
        LogLine('cyan', 'msg      $commitMessage'),
      if (message != null && message.isNotEmpty)
        LogLine('white', 'deploy   $message'),
    ];

    _state.value = OtaOverlayState(
      message: message,
      commitMessage: commitMessage,
      targetVersion: targetVersion,
      currentVersion: currentVersion,
      errorHint: errorHint,
      bundleHash: bundleHash,
      gitCommit: gitCommit,
      channel: channel,
      platform: platform,
      logs: logs,
      activeStep: 0,
    );
    _entry = OverlayEntry(builder: (_) => OtaProgressOverlay(state: _state));
    overlay.insert(_entry!);
    return OtaOverlayHandle._(this);
  }

  void _log(String color, String text) {
    if (_disposed) return;
    final current = _state.value;
    _state.value = current.copyWith(
      logs: [...current.logs, LogLine(color, text)],
    );
  }

  /// Map phase to step index.
  int _phaseToStep(PatchApplyPhase? phase) {
    switch (phase) {
      case PatchApplyPhase.downloading:
        return 1;
      case PatchApplyPhase.verifying:
        return 2;
      case PatchApplyPhase.finalizing:
        return 3;
      case null:
        return 0;
    }
  }

  void _update(PatchApplyProgress progress) {
    if (_disposed || _entry == null) return;
    final s = _state.value;
    final pct = progress.fraction;
    final pctText = pct != null
        ? '${(pct.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%'
        : '';

    final newStep = _phaseToStep(progress.phase);

    // Log phase transitions with staggered delays
    if (s.phase != progress.phase) {
      switch (progress.phase) {
        case PatchApplyPhase.downloading:
          _log('gray', 'status   connecting...');
          _delayedLog(300, 'gray', 'status   fetching metadata...');
          _delayedLog(700, 'cyan', 'resolve  download url');
          _delayedLog(1100, 'gray', 'status   downloading...');
          break;
        case PatchApplyPhase.verifying:
          _log('cyan', 'verify   checking hash...');
          _delayedLog(400, 'cyan', 'verify   checking signature...');
          _delayedLog(800, 'success', 'verify   passed ✓');
          break;
        case PatchApplyPhase.finalizing:
          _log('gray', 'status   staging files...');
          _delayedLog(500, 'gray', 'status   installing...');
          _delayedLog(1000, 'gray', 'status   finalizing...');
          break;
      }
    }

    // Log download progress with size
    if (progress.phase == PatchApplyPhase.downloading &&
        pctText.isNotEmpty &&
        progress.totalBytes > 0) {
      final sizeMB = (progress.totalBytes / 1048576).toStringAsFixed(1);
      _log('gray', 'data     ${sizeMB}MB  $pctText');
    }

    _state.value = _state.value.copyWith(
      phase: progress.phase,
      fraction: progress.fraction,
      activeStep: newStep,
    );
  }

  /// Log with a delay for staged feel.
  void _delayedLog(int ms, String color, String text) {
    Future.delayed(Duration(milliseconds: ms), () {
      if (_disposed) return;
      _log(color, text);
    });
  }

  void _end({bool hasError = false, String? errorText}) {
    if (_disposed || _entry == null) return;
    if (hasError) {
      _log('red', 'error    ${errorText ?? 'unknown'}');
      _log('yellow', 'hint     close and reopen to retry');
    } else {
      _log('success', 'done     patch installed ✓');
      _delayedLog(300, 'cyan', 'status   restarting...');
    }

    // Calculate remaining time to enforce minimum duration
    final elapsed = _startTime != null
        ? DateTime.now().difference(_startTime!)
        : _minDuration;
    final remaining = _minDuration - elapsed;
    final delay = remaining.isNegative ? Duration.zero : remaining;

    _state.value = _state.value.copyWith(
      hasError: hasError,
      errorText: errorText,
      canRetry: hasError,
      activeStep: hasError ? _state.value.activeStep : 4,
    );

    final entry = _entry;
    final dwell = hasError ? errorDwell : _successDwell + delay;
    Future.delayed(dwell, () {
      if (_disposed) return;
      entry?.remove();
      if (identical(_entry, entry)) _entry = null;
    });
  }

  /// Shows a toast notification on the forced-update overlay when a rollback occurs.
  void showRollbackToast({
    required String message,
    required String previousVersion,
  }) {
    if (_disposed) return;
    final overlay = _overlayState ?? _resolver?.call();
    if (overlay == null) return;

    // Create a temporary toast overlay on top of existing overlay
    final toastEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 100,
        left: 24,
        right: 24,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        'Restored: $previousVersion',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(toastEntry);
    Future.delayed(const Duration(seconds: 4), () {
      if (!_disposed) toastEntry.remove();
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
