import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ota_kit/src/pkg/core/flutter_ota_kit_core.dart'
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

  /// Bytes downloaded so far (downloading phase only).
  final int bytesReceived;

  /// Total payload size in bytes, or 0 when unknown.
  final int totalBytes;

  final List<LogLine> logs;
  final bool canRetry;

  /// True once the patch is installed and the app is about to cold-restart.
  /// Drives the final "restarting" phase label + the completed steps list.
  final bool restarting;

  /// Which step index is currently active (0-based). Steps that are done
  /// get a check; the active step gets the braille spinner.
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
    this.bytesReceived = 0,
    this.totalBytes = 0,
    this.logs = const [],
    this.canRetry = false,
    this.restarting = false,
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
    int? bytesReceived,
    int? totalBytes,
    List<LogLine>? logs,
    bool? canRetry,
    bool? restarting,
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
      bytesReceived: bytesReceived ?? this.bytesReceived,
      totalBytes: totalBytes ?? this.totalBytes,
      logs: logs ?? this.logs,
      canRetry: canRetry ?? this.canRetry,
      restarting: restarting ?? this.restarting,
      activeStep: activeStep ?? this.activeStep,
    );
  }
}

/// A single terminal log line with a color tag and an optional left-column tag.
///
/// [text] is the message. If it contains a leading token separated by 2+
/// spaces (e.g. `'verify   passed ✓'`), the overlay renders the first token
/// in the accent color and the rest in the body color, preserving the
/// aligned key/value look. Plain lines render whole in [color].
class LogLine {
  final String color;
  final String text;

  const LogLine(this.color, this.text);
}

const Object _unset = Object();

/// GitHub-dark inspired palette for the terminal overlay.
class _C {
  static const bg = Color(0xFF0B0F14);
  static const panel = Color(0xFF11161D);
  static const inner = Color(0xFF0E141B);
  static const head = Color(0xFF161C24);
  static const border = Color(0xFF232A34);
  static const sep = Color(0xFF1B222B);
  static const logBg = Color(0xFF0A0E13);
  static const green = Color(0xFF3FB950);
  static const blue = Color(0xFF58A6FF);
  static const cyan = Color(0xFF56D4DD);
  static const yellow = Color(0xFFD29922);
  static const red = Color(0xFFF85149);
  static const text = Color(0xFFC9D1D9);
  static const dim = Color(0xFF7D8794);
  static const faint = Color(0xFF484F58);
}

const String _mono = 'monospace';

/// The 5 steps shown during a forced update.
const List<String> _stepLabels = [
  'Initialize',
  'Download bundle',
  'Verify hash + signature',
  'Install patch',
  'Finalize & restart',
];

/// Named color -> swatch, used to resolve [LogLine.color].
const Map<String, Color> _logColors = {
  'green': _C.green,
  'red': _C.red,
  'yellow': _C.yellow,
  'gray': _C.dim,
  'white': _C.text,
  'cyan': _C.cyan,
  'success': _C.blue,
};

/// Full-screen, structured terminal-style forced-update overlay.
///
/// Sections, top to bottom:
///  - Title bar (traffic lights + status pill)
///  - META (channel / version / bundle / size)
///  - STEPS (per-phase status list)
///  - PROGRESS (monospace bar + speed / eta / phase)
///  - LOG (scrolling colored feed)
///  - Footer (deploy message, or error hint + retry)
class OtaProgressOverlay extends StatefulWidget {
  final ValueNotifier<OtaOverlayState> state;
  final bool dismissible;

  /// Called when the user taps the footer `[ retry ]` button in the error
  /// state. When null, the button is shown only if [OtaOverlayState.canRetry].
  final VoidCallback? onRetry;

  const OtaProgressOverlay({
    super.key,
    required this.state,
    this.dismissible = false,
    this.onRetry,
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

  String _pct(double? f) =>
      f == null ? '--%' : '${(f.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%';

  String _mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OtaOverlayState>(
      valueListenable: widget.state,
      builder: (context, s, _) {
        return Material(
          color: _C.bg,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                decoration: BoxDecoration(
                  color: _C.panel,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _C.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _titleBar(s),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sectionLabel('META'),
                            const SizedBox(height: 8),
                            _metaBlock(s),
                            const SizedBox(height: 18),
                            _sectionLabel('STEPS'),
                            const SizedBox(height: 8),
                            _stepsBlock(s),
                            const SizedBox(height: 18),
                            _sectionLabel('PROGRESS'),
                            const SizedBox(height: 8),
                            _progressBlock(s),
                            const SizedBox(height: 18),
                            _sectionLabel('LOG'),
                            const SizedBox(height: 8),
                            _logBlock(s),
                          ],
                        ),
                      ),
                    ),
                    _footer(s),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Title bar ─────────────────────────────────────────────────────────
  Widget _titleBar(OtaOverlayState s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: const BoxDecoration(
          color: _C.head,
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          border: Border(bottom: BorderSide(color: _C.border)),
        ),
        child: Row(
          children: [
            _dot(_C.red),
            const SizedBox(width: 6),
            _dot(_C.yellow),
            const SizedBox(width: 6),
            _dot(_C.green),
            const SizedBox(width: 12),
            const Flexible(
              child: Text(
                'flutter-ota · forced update',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: _C.text, fontFamily: _mono, fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            _pill(
              s.hasError ? 'FAILED' : 'RUNNING',
              s.hasError ? _C.red : _C.green,
            ),
          ],
        ),
      );

  // ── META ──────────────────────────────────────────────────────────────
  Widget _metaBlock(OtaOverlayState s) {
    final rows = <List<String>>[
      if (s.channel != null) ['channel', s.channel!],
      if (s.currentVersion != null && s.targetVersion != null)
        ['version', '${s.currentVersion}  →  ${s.targetVersion}']
      else if (s.targetVersion != null)
        ['version', s.targetVersion!],
      if (s.bundleHash != null) ['bundle', s.bundleHash!],
      if (s.totalBytes > 0) ['size', _mb(s.totalBytes)],
    ];
    if (rows.isEmpty) rows.add(['status', 'preparing…']);
    return _panelBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(fontFamily: _mono, fontSize: 13),
                  children: [
                    TextSpan(
                        text: '${r[0].padRight(9)} ',
                        style: const TextStyle(color: _C.dim)),
                    TextSpan(
                        text: r[1],
                        style: TextStyle(
                            color: r[0] == 'version' ? _C.blue : _C.text)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── STEPS ─────────────────────────────────────────────────────────────
  Widget _stepsBlock(OtaOverlayState s) {
    final spinner = _braille[_spinnerIndex];
    // When restarting, every step is complete. Otherwise the active index is
    // clamped into range so an out-of-bounds activeStep can never leave the
    // list looking stuck or skip the visible progression.
    final int activeIndex = s.restarting
        ? _stepLabels.length
        : s.activeStep.clamp(0, _stepLabels.length - 1);

    return _panelBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(_stepLabels.length, (i) {
          final done = i < activeIndex;
          final active = i == activeIndex && !s.hasError && !s.restarting;
          final failed = i == activeIndex && s.hasError;
          final pending = i > activeIndex;

          final Color color = failed
              ? _C.red
              : done
                  ? _C.green
                  : active
                      ? _C.blue
                      : _C.faint;

          final String glyph = failed
              ? '✗'
              : done
                  ? '✓'
                  : active
                      ? spinner
                      : '·';

          // Only the downloading step shows a percentage. Verify / install /
          // finalize have no meaningful fraction, so they show a live "working"
          // spinner instead of a frozen number — nothing looks hung.
          final String status;
          if (failed) {
            status = 'error';
          } else if (done) {
            status = 'done';
          } else if (active) {
            final showPct = s.phase == PatchApplyPhase.downloading &&
                s.fraction != null;
            status = showPct ? _pct(s.fraction) : 'working $spinner';
          } else {
            status = 'wait';
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: Text(glyph,
                      style: TextStyle(
                          color: color, fontFamily: _mono, fontSize: 14)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _stepLabels[i],
                    style: TextStyle(
                      color: pending ? _C.faint : _C.text,
                      fontFamily: _mono,
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                Text(
                  status,
                  style: TextStyle(
                    color: color,
                    fontFamily: _mono,
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── PROGRESS ──────────────────────────────────────────────────────────
  Widget _progressBlock(OtaOverlayState s) {
    final speed = (s.bytesPerSec != null && s.bytesPerSec! > 0)
        ? '${(s.bytesPerSec! / 1048576).toStringAsFixed(1)} MB/s'
        : '—';
    String eta = '—';
    if (s.bytesPerSec != null &&
        s.bytesPerSec! > 0 &&
        s.totalBytes > s.bytesReceived) {
      final secs = ((s.totalBytes - s.bytesReceived) / s.bytesPerSec!).ceil();
      eta = secs >= 60 ? '${(secs / 60).ceil()}m' : '${secs}s';
    }
    final phase = s.hasError
        ? 'halted'
        : (s.restarting ? 'restarting' : (s.phase?.name ?? 'preparing'));

    // A determinate fraction is only meaningful while downloading with a known
    // Content-Length. Verifying / finalizing / unknown-size downloads render an
    // indeterminate (sliding) bar so nothing ever looks stuck at 0%.
    final bool determinate = !s.hasError &&
        s.phase == PatchApplyPhase.downloading &&
        s.fraction != null;
    final double? frac = s.hasError
        ? (s.fraction ?? 0)
        : (determinate ? s.fraction : null);

    return _panelBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The bar is a real widget (never wraps), and animates smoothly
              // between values instead of snapping.
              Expanded(
                child: _ProgressBar(
                  fraction: frac,
                  color: s.hasError ? _C.red : _C.blue,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 44,
                child: Text(
                  determinate ? _pct(s.fraction) : '',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontFamily: _mono,
                    fontSize: 13,
                    color: _C.text,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _stat('speed', speed),
              _stat('eta', eta),
              _stat('phase', phase),
            ],
          ),
        ],
      ),
    );
  }

  // ── LOG ───────────────────────────────────────────────────────────────
  Widget _logBlock(OtaOverlayState s) {
    return Container(
      height: 132,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _C.logBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _C.sep),
      ),
      child: _TerminalLog(logs: s.logs),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────
  Widget _footer(OtaOverlayState s) {
    final showRetry = s.hasError && (widget.onRetry != null || s.canRetry);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: _C.head,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
        border: Border(top: BorderSide(color: _C.border)),
      ),
      child: s.hasError
          ? Row(
              children: [
                Expanded(
                  child: Text(
                    s.errorHint ?? 'Close the app and reopen to retry.',
                    style: const TextStyle(
                        color: _C.dim, fontFamily: _mono, fontSize: 12),
                  ),
                ),
                if (showRetry)
                  GestureDetector(
                    onTap: widget.onRetry,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: _C.border),
                      ),
                      child: const Text('[ retry ]',
                          style: TextStyle(
                              color: _C.blue,
                              fontFamily: _mono,
                              fontSize: 13)),
                    ),
                  ),
              ],
            )
          : Row(
              children: [
                const Text('›',
                    style: TextStyle(
                        color: _C.green, fontFamily: _mono, fontSize: 13)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (s.message != null && s.message!.isNotEmpty)
                        ? s.message!
                        : 'Applying update, please keep the app open…',
                    style: const TextStyle(
                        color: _C.dim, fontFamily: _mono, fontSize: 12),
                  ),
                ),
              ],
            ),
    );
  }

  // ── helpers ─────────────────────────────────────────────────────────
  Widget _sectionLabel(String t) => Row(
        children: [
          Text(t,
              style: const TextStyle(
                color: _C.dim,
                fontFamily: _mono,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              )),
          const SizedBox(width: 10),
          const Expanded(child: Divider(color: _C.sep, height: 1)),
        ],
      );

  Widget _panelBox({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _C.inner,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _C.sep),
        ),
        child: child,
      );

  Widget _stat(String k, String v) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k,
                style: const TextStyle(
                    color: _C.faint, fontFamily: _mono, fontSize: 10)),
            const SizedBox(height: 2),
            Text(v,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: _C.text, fontFamily: _mono, fontSize: 12)),
          ],
        ),
      );

  Widget _dot(Color c) => Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );

  Widget _pill(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: c.withValues(alpha: 0.5)),
        ),
        child: Text(t,
            style: TextStyle(
                color: c,
                fontFamily: _mono,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5)),
      );
}

/// A single-line progress bar that never wraps.
///
/// - When [fraction] is non-null it's a determinate bar that animates smoothly
///   between values (no snapping / jumping).
/// - When [fraction] is null it's an indeterminate sliding bar, so
///   verify/install/finalize (which have no meaningful percentage) never look
///   frozen at 0%.
///
/// It's a real painted widget with a fixed height inside an [Expanded], so it
/// always stays on one line regardless of width — unlike the old
/// character-string bar, which wrapped when it didn't fit.
class _ProgressBar extends StatefulWidget {
  final double? fraction;
  final Color color;

  const _ProgressBar({required this.fraction, required this.color});

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _indeterminate = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  // Smoothed determinate value so the bar eases toward the target instead of
  // snapping. Monotonic — it never visually goes backwards.
  double _shown = 0;

  @override
  void initState() {
    super.initState();
    _shown = widget.fraction ?? 0;
    if (widget.fraction == null) _indeterminate.repeat();
  }

  @override
  void didUpdateWidget(covariant _ProgressBar old) {
    super.didUpdateWidget(old);
    if (widget.fraction == null) {
      if (!_indeterminate.isAnimating) _indeterminate.repeat();
    } else {
      if (_indeterminate.isAnimating) _indeterminate.stop();
      final target = widget.fraction!.clamp(0.0, 1.0);
      if (target >= _shown) _shown = target; // forward-only
    }
  }

  @override
  void dispose() {
    _indeterminate.dispose();
    super.dispose();
  }

  static const _height = 8.0;
  static const _track = Color(0xFF161C24);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: _height,
        child: ColoredBox(
          color: _track,
          child: widget.fraction == null
              ? _indeterminateBar()
              : _determinateBar(),
        ),
      ),
    );
  }

  Widget _determinateBar() {
    return LayoutBuilder(
      builder: (context, c) => TweenAnimationBuilder<double>(
        // Ease toward the smoothed target; short duration keeps it responsive
        // but never snappy.
        tween: Tween(end: _shown),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        builder: (context, v, _) => Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: (c.maxWidth * v.clamp(0.0, 1.0)),
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
      ),
    );
  }

  Widget _indeterminateBar() {
    return LayoutBuilder(
      builder: (context, c) => AnimatedBuilder(
        animation: _indeterminate,
        builder: (context, _) {
          const segment = 0.35; // 35% wide moving segment
          final t = _indeterminate.value; // 0..1
          final left = (t * (1 + segment)) - segment; // slides in from the left
          return Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(
                left: (left.clamp(0.0, 1.0)) * c.maxWidth,
              ),
              child: Container(
                width: segment * c.maxWidth,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Scrollable terminal log view — auto-scrolls to bottom on new lines.
///
/// A line whose text has a leading token followed by 2+ spaces is rendered
/// with the token in its tag color and the remainder in the body color.
class _TerminalLog extends StatefulWidget {
  final List<LogLine> logs;

  const _TerminalLog({required this.logs});

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
    final logs = widget.logs.isEmpty
        ? const [LogLine('gray', 'status   waiting for events…')]
        : widget.logs;
    return ListView.builder(
      controller: _controller,
      itemCount: logs.length,
      itemBuilder: (context, i) {
        final line = logs[i];
        final color = _logColors[line.color] ?? _C.dim;

        // Split "tag   rest" (2+ spaces) into an accent tag + body.
        final match = RegExp(r'^(\S+)(\s{2,})(.*)$').firstMatch(line.text);
        final Widget content;
        if (match != null) {
          content = RichText(
            text: TextSpan(
              style: const TextStyle(fontFamily: _mono, fontSize: 12),
              children: [
                TextSpan(
                    text: '${match.group(1)!.padRight(8)} ',
                    style: TextStyle(color: color)),
                TextSpan(
                    text: match.group(3),
                    style: const TextStyle(color: _C.text)),
              ],
            ),
          );
        } else {
          content = Text(
            line.text,
            style: TextStyle(
                fontFamily: _mono, fontSize: 12, color: color),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: content,
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

  // Download-speed tracking.
  int _lastBytes = 0;
  DateTime? _lastBytesAt;

  /// Last 10%-bucket we emitted a "download NN%" log line for, to throttle the
  /// feed. -1 = none yet.
  int _lastLoggedPctBucket = -1;

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
    _lastBytes = 0;
    _lastBytesAt = null;
    _lastLoggedPctBucket = -1;

    final logs = <LogLine>[
      if (channel != null) LogLine('gray', 'channel  $channel'),
      if (platform != null) LogLine('gray', 'platform $platform'),
      if (bundleHash != null) LogLine('gray', 'bundle   $bundleHash'),
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
    final next = [...current.logs, LogLine(color, text)];
    // Cap the feed so a long session can't grow it without bound.
    const maxLines = 200;
    final capped = next.length > maxLines
        ? next.sublist(next.length - maxLines)
        : next;
    _state.value = current.copyWith(logs: capped);
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

    // Step index derived from phase, but forced to move only forward so an
    // out-of-order or duplicate native event can never make the steps jump
    // backwards or flicker.
    final phaseStep = _phaseToStep(progress.phase);
    final newStep = phaseStep < s.activeStep ? s.activeStep : phaseStep;

    // Compute a smoothed download speed from byte deltas. A single sample can
    // spike wildly (buffered reads), so we blend with the previous value.
    int? bytesPerSec = s.bytesPerSec;
    if (progress.phase == PatchApplyPhase.downloading &&
        progress.bytesReceived > 0) {
      final now = DateTime.now();
      if (_lastBytesAt != null && progress.bytesReceived > _lastBytes) {
        final dt = now.difference(_lastBytesAt!).inMilliseconds / 1000.0;
        if (dt > 0.05) {
          final sample =
              ((progress.bytesReceived - _lastBytes) / dt).round();
          // Exponential moving average → the speed/ETA read-out stops jumping.
          bytesPerSec = bytesPerSec == null || bytesPerSec == 0
              ? sample
              : (bytesPerSec * 0.6 + sample * 0.4).round();
          _lastBytes = progress.bytesReceived;
          _lastBytesAt = now;
        }
      } else {
        _lastBytes = progress.bytesReceived;
        _lastBytesAt = now;
      }
    }

    // Log phase transitions once, with staggered detail lines.
    if (s.phase != progress.phase) {
      switch (progress.phase) {
        case PatchApplyPhase.downloading:
          _log('gray', 'status   connecting…');
          _delayedLog(300, 'gray', 'status   fetching metadata…');
          _delayedLog(700, 'cyan', 'resolve  download url');
          _delayedLog(1100, 'gray', 'status   downloading…');
          break;
        case PatchApplyPhase.verifying:
          _log('cyan', 'verify   checking hash…');
          _delayedLog(400, 'cyan', 'verify   checking signature…');
          _delayedLog(800, 'success', 'verify   passed ✓');
          break;
        case PatchApplyPhase.finalizing:
          _log('gray', 'status   staging files…');
          _delayedLog(500, 'gray', 'status   installing…');
          _delayedLog(1000, 'gray', 'status   finalizing…');
          break;
      }
    }

    // Throttle the "download NN%" log so a fast download doesn't spam dozens of
    // lines (which made the feed scroll frantically). One line per ~10%.
    if (progress.phase == PatchApplyPhase.downloading &&
        pctText.isNotEmpty &&
        progress.totalBytes > 0) {
      final bucket = ((progress.fraction ?? 0) * 10).floor();
      if (bucket != _lastLoggedPctBucket) {
        _lastLoggedPctBucket = bucket;
        final sizeMB = (progress.totalBytes / 1048576).toStringAsFixed(1);
        _log('gray', 'download ${sizeMB}MB  $pctText');
      }
    }

    _state.value = _state.value.copyWith(
      phase: progress.phase,
      fraction: progress.fraction,
      bytesReceived: progress.bytesReceived,
      totalBytes: progress.totalBytes > 0 ? progress.totalBytes : null,
      bytesPerSec: bytesPerSec,
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
      _log('yellow', 'action   rolling back to base apk');
    } else {
      _log('success', 'done     patch installed ✓');
      _delayedLog(300, 'cyan', 'status   restarting…');
    }

    // Calculate remaining time to enforce minimum duration.
    final elapsed = _startTime != null
        ? DateTime.now().difference(_startTime!)
        : _minDuration;
    final remaining = _minDuration - elapsed;
    final delay = remaining.isNegative ? Duration.zero : remaining;

    // On success mark ALL steps complete + flag restarting, so the steps list
    // finishes cleanly (every ✓, phase = "restarting") instead of freezing on
    // whatever step the last native progress event happened to leave active.
    _state.value = _state.value.copyWith(
      hasError: hasError,
      errorText: errorText,
      canRetry: hasError,
      restarting: !hasError,
      fraction: hasError ? null : 1.0,
      activeStep: hasError ? _state.value.activeStep : _stepLabels.length,
    );

    final entry = _entry;
    final dwell = hasError ? errorDwell : _successDwell + delay;
    Future.delayed(dwell, () {
      if (_disposed) return;
      entry?.remove();
      if (identical(_entry, entry)) _entry = null;
    });
  }

  /// Shows a toast notification on the forced-update overlay when a rollback
  /// occurs.
  void showRollbackToast({
    required String message,
    required String previousVersion,
  }) {
    if (_disposed) return;
    final overlay = _overlayState ?? _resolver?.call();
    if (overlay == null) return;

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

/// Handle returned by [OtaOverlayManager.begin] to update / dismiss the
/// overlay.
class OtaOverlayHandle {
  OtaOverlayHandle._(this._manager);

  final OtaOverlayManager _manager;

  void update(PatchApplyProgress progress) => _manager._update(progress);

  void end({bool hasError = false, String? errorText}) =>
      _manager._end(hasError: hasError, errorText: errorText);
}
