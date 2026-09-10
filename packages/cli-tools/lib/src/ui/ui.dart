library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

/// Terminal UI toolkit for the flutter-ota CLI.
///
/// Provides colored text, banners, bordered boxes, step logs, spinners,
/// thin progress bars, and column-aligned tables.
///
/// Everything degrades gracefully to plain text when stdout is not a TTY
/// or the `NO_COLOR` env var is set.

// ── ANSI codes ───────────────────────────────────────────────────────────────

const _kReset = '\x1b[0m';
const _kRed = '\x1b[31m';
const _kGreen = '\x1b[32m';
const _kYellow = '\x1b[33m';
const _kBlue = '\x1b[34m';
const _kMagenta = '\x1b[35m';
const _kCyan = '\x1b[36m';
const _kGray = '\x1b[90m';
const _kBold = '\x1b[1m';

const List<String> _frames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];

// ── TTY detection ────────────────────────────────────────────────────────────

bool get _noColor {
  final v = Platform.environment['NO_COLOR'];
  return v != null && v.isNotEmpty;
}

bool get _colorOn =>
    !_noColor && stdout.hasTerminal && stdout.supportsAnsiEscapes;

// ── Color helpers ────────────────────────────────────────────────────────────

String _c(String code, String s) => _colorOn ? '$code$s$_kReset' : s;

String red(String s) => _c(_kRed, s);
String green(String s) => _c(_kGreen, s);
String yellow(String s) => _c(_kYellow, s);
String blue(String s) => _c(_kBlue, s);
String magenta(String s) => _c(_kMagenta, s);
String cyan(String s) => _c(_kCyan, s);
String gray(String s) => _c(_kGray, s);
String dim(String s) => _c(_kGray, s);
String bold(String s) => _c(_kBold, s);

// ── Terminal width ───────────────────────────────────────────────────────────

int get _cols {
  if (stdout.hasTerminal) return stdout.terminalColumns;
  final envCols = Platform.environment['COLUMNS'];
  if (envCols != null) {
    final parsed = int.tryParse(envCols);
    if (parsed != null && parsed > 0) return parsed;
  }
  return 80;
}

// ── Visible width (ANSI-aware) ──────────────────────────────────────────────

final _ansi = RegExp('\x1b\\[[0-9;]*m');

int _dispWidth(String s) => s.replaceAll(_ansi, '').length;

void _echo(String s) => stdout.writeln(s);

// ── Key-value pair ───────────────────────────────────────────────────────────

/// `key  value` laid out in a fixed 18-char column (visible-width aware).
/// Long values are truncated with `…` to prevent box overflow.
String kv(String k, String v) {
  final pad = math.max(0, 18 - _dispWidth(k));
  final maxVal = math.max(0, _cols - 24 - _dispWidth(k));
  final display = maxVal > 0 && _dispWidth(v) > maxVal
      ? '${_cut(v, maxVal - 1)}…'
      : v;
  return '${dim(k)}${' ' * pad}  $display';
}

// ── Banner ───────────────────────────────────────────────────────────────────

void banner(String name) {
  _echo('');
  _echo(
    '  ${cyan('▶')} ${cyan(bold('flutter-ota'))} ${dim('·')} ${bold(name)}',
  );
  final sepLen = math.max(20, math.min(_cols - 4, 72));
  _echo('  ${dim('─' * sepLen)}');
}

// ── Single-line status ──────────────────────────────────────────────────────

void step(String msg) => _echo('  ${green('✓')} $msg');
void warn(String msg) => _echo('  ${yellow('⚠')} ${yellow(msg)}');
void err(String msg) => _echo('  ${red('✗')} ${red(msg)}');
void info(String msg) => _echo('  ${blue('ℹ')} $msg');
void active(String msg) => _echo('  ${cyan('⠹')} $msg');

// ── Spinner ──────────────────────────────────────────────────────────────────

/// Run [task] while showing a live spinner; replaces the line with a
/// `${green('✓')} done` summary when finished (or `✗` on error).
Future<T> spinner<T>(
  Future<T> Function() task,
  String label, {
  String? done,
}) async {
  if (!_colorOn) {
    _echo('  ${dim('•')} $label');
    final r = await task();
    _echo('  ${green('✓')} ${done ?? label}');
    return r;
  }
  var i = 0;
  final sw = Stopwatch()..start();
  final timer = Timer.periodic(const Duration(milliseconds: 80), (_) {
    i = (i + 1) % _frames.length;
    stdout.write('\r\x1b[K  ${cyan(_frames[i])} $label');
  });
  try {
    final r = await task();
    // Keep spinner visible for at least 400ms so fast ops are readable.
    final elapsed = sw.elapsedMilliseconds;
    if (elapsed < 400)
      await Future.delayed(Duration(milliseconds: 400 - elapsed));
    timer.cancel();
    sw.stop();
    stdout.write('\r\x1b[K  ${green('✓')} ${done ?? label}\n');
    return r;
  } catch (e) {
    timer.cancel();
    stdout.write('\r\x1b[K  ${red('✗')} $label\n');
    rethrow;
  }
}

// ── Word wrap ────────────────────────────────────────────────────────────────

List<String> _wrap(String text, int inner) {
  if (text.isEmpty) return [''];
  final result = <String>[];
  for (final raw in text.split('\n')) {
    if (_dispWidth(raw) <= inner) {
      result.add(raw);
      continue;
    }
    var line = '';
    for (final word in raw.split(' ')) {
      if (word.isEmpty) continue;
      if (line.isEmpty) {
        if (_dispWidth(word) <= inner) {
          line = word;
        } else {
          var rem = word;
          while (_dispWidth(rem) > inner) {
            final cut = _cut(rem, inner);
            result.add(cut);
            rem = rem.substring(cut.length);
          }
          line = rem;
        }
      } else if (_dispWidth(line) + 1 + _dispWidth(word) <= inner) {
        line += ' $word';
      } else {
        result.add(line);
        line = word.length <= inner ? word : _splitLong(word, inner, result);
      }
    }
    result.add(line);
  }
  return result;
}

String _cut(String s, int inner) {
  final buf = StringBuffer();
  for (final ch in s.runes) {
    if (buf.length + 1 > inner) break;
    buf.writeCharCode(ch);
  }
  return buf.toString();
}

String _splitLong(String word, int inner, List<String> out) {
  var rem = word;
  while (_dispWidth(rem) > inner) {
    if (_dispWidth(rem) <= inner + 2) {
      // Truncate with … instead of hard-breaking mid-word.
      out.add('${_cut(rem, inner - 1)}…');
      return '';
    }
    final cut = _cut(rem, inner);
    out.add(cut);
    rem = rem.substring(cut.length);
  }
  return rem;
}

// ── Box ──────────────────────────────────────────────────────────────────────

/// Mathematically precise box width: single formula for both title and content.
int _boxWidth(List<String> lines, String title) {
  var longest = 0;
  for (final l in lines) {
    for (final w in l.split('\n')) {
      longest = math.max(longest, _dispWidth(w));
    }
  }
  final titleNeeded = _dispWidth(title) + 4;
  final contentNeeded = longest + 4;
  final target = math.max(titleNeeded, math.max(contentNeeded, 40));
  return math.max(math.min(_cols - 1, target), 20);
}

/// Bordered box with a centered title; auto-sizes to the terminal and wraps
/// long content so the right/left edges always stay aligned.
void box(String title, List<String> lines) {
  final width = _boxWidth(lines, title);
  final inner = width - 4;

  // Wrap content to fit inner width.
  final wrapped = <String>[];
  for (final l in lines) {
    if (l.isEmpty) {
      wrapped.add('');
    } else {
      wrapped.addAll(_wrap(l, inner));
    }
  }

  // Title centered in top border.
  final titleText = ' $title ';
  final tVisible = _dispWidth(titleText);
  final totalDashes = width - 2 - tVisible;
  final leftDashes = math.max(1, totalDashes ~/ 2);
  final rightDashes = totalDashes - leftDashes;

  _echo('┌${'─' * leftDashes}$titleText${'─' * rightDashes}┐');
  for (final l in wrapped) {
    final pad = math.max(0, inner - _dispWidth(l));
    _echo('│ $l${' ' * pad} │');
  }
  _echo('└${'─' * (width - 2)}┘');
}

// ── Steps ────────────────────────────────────────────────────────────────────

/// Multi-step progress tracker with uv-style clean output.
///
/// Each step prints a single line: `✓ label` (done), `✗ label` (failed),
/// or `· label` (skipped). After all steps, call [summary] to print a
/// boxed summary with counts and elapsed time.
///
/// Example:
/// ```dart
/// final s = Steps('migrate · supabase');
/// s.success('Applied 20250103_init.sql');
/// s.skip('Skipped 20251014_0.21.0.sql');
/// s.summary(); // prints "2 applied · 1 skipped · 0 errors · 245ms"
/// ```
class Steps {
  Steps(this.title) : _sw = Stopwatch()..start();

  final String title;
  final Stopwatch _sw;
  int _done = 0;
  int _failed = 0;
  int _skipped = 0;

  /// Whether any step has failed.
  bool get hasErrors => _failed > 0;

  /// Step completed successfully.
  void success(String label) {
    _done++;
    _echo('  ${green('✓')} $label');
  }

  /// Step failed.
  void fail(String label) {
    _failed++;
    _echo('  ${red('✗')} $label');
  }

  /// Step skipped (e.g. already applied).
  void skip(String label) {
    _skipped++;
    _echo('  ${dim('·')} $label');
  }

  /// Print summary. Always inline — no box for a single line of text.
  void summary() {
    _sw.stop();
    final ms = _sw.elapsedMilliseconds;
    final time = ms >= 1000 ? '${(ms / 1000).toStringAsFixed(1)}s' : '${ms}ms';
    final parts = <String>[];
    if (_done > 0) parts.add('${_done} completed');
    if (_skipped > 0) parts.add('${_skipped} skipped');
    if (_failed > 0) {
      parts.add('${red('${_failed} error${_failed > 1 ? 's' : ''}')}');
    }
    if (parts.isEmpty) parts.add('no steps');
    parts.add(time);
    _echo('  ${dim(parts.join('  ·  '))}');
  }

  /// Run a step that shows a spinner while working, then marks it
  /// success/fail/skip based on the result. This is the recommended way to
  /// show multi-phase work where each phase has a distinct label the user
  /// can understand.
  ///
  /// Example:
  /// ```dart
  /// final s = Steps('deploy');
  /// final zipped = await s.run('Zipping source', () async {
  ///   return await zipDir(source);
  /// });
  /// final uploaded = await s.run('Uploading to storage', () async {
  ///   return await backend.putObject(bucket, zipped);
  /// });
  /// await s.run('Registering bundle', () async {
  ///   return await backend.insertBundle(...);
  /// });
  /// s.summary();
  /// ```
  Future<T> run<T>(String label, Future<T> Function() task) async {
    if (!_colorOn) {
      _echo('  ${dim('•')} $label');
      try {
        final r = await task();
        _done++;
        _echo('  ${green('✓')} $label');
        return r;
      } catch (e) {
        _failed++;
        _echo('  ${red('✗')} $label');
        rethrow;
      }
    }
    var i = 0;
    final sw = Stopwatch()..start();
    final timer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      i = (i + 1) % _frames.length;
      stdout.write('\r\x1b[K  ${cyan(_frames[i])} $label');
    });
    try {
      final r = await task();
      final elapsed = sw.elapsedMilliseconds;
      if (elapsed < 200) {
        await Future.delayed(Duration(milliseconds: 200 - elapsed));
      }
      timer.cancel();
      sw.stop();
      stdout.write('\r\x1b[K  ${green('✓')} $label\n');
      _done++;
      return r;
    } catch (e) {
      timer.cancel();
      stdout.write('\r\x1b[K  ${red('✗')} $label\n');
      _failed++;
      rethrow;
    }
  }

  Timer? _activeTimer;
  int _activeIdx = 0;
  String? _activeLabel;

  /// Print an "active" phase line (⠹ label) that will be replaced in-place
  /// by the next call to [startActive] or finalized by [completeActive].
  /// Use this when a long-running operation reports multiple internal phases
  /// via a callback (e.g. `DeployOptions.onPhase`).
  void startActive(String label) {
    _activeLabel = label;
    if (!_colorOn) {
      _echo('  ${dim('•')} $label');
      return;
    }
    _activeIdx = 0;
    _activeTimer?.cancel();
    _activeTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      _activeIdx = (_activeIdx + 1) % _frames.length;
      stdout.write('\r\x1b[K  ${cyan(_frames[_activeIdx])} $label');
    });
  }

  /// Finalize the current active line. If [success] is true (default) the
  /// line becomes `✓ label` and counts toward `_done`. If false, it becomes
  /// `✗ label` and counts toward `_failed`. Call this when the long-running
  /// operation finishes.
  void completeActive({bool success = true}) {
    final label = _activeLabel;
    if (label == null) return;
    _activeTimer?.cancel();
    _activeTimer = null;
    _activeLabel = null;
    if (_colorOn) {
      stdout.write('\r\x1b[K  ${success ? green('✓') : red('✗')} $label\n');
    }
    if (success) {
      _done++;
    } else {
      _failed++;
    }
  }
}

// ── Progress Bar (thin, single-line) ────────────────────────────────────────

/// Braille single-line progress bar with spinner, label, bar, and time.
///
/// Renders as: `⠹ Label  ⣿⣿⣿⣀⣀⣀ 50%`
/// On finish: `✓ Label in 1.3s`
class ProgressBar {
  ProgressBar(this.total, this.label);

  int total;
  String label;
  int _current = 0;
  int _spin = 0;
  bool _closed = false;
  final Stopwatch _sw = Stopwatch()..start();
  late String _label = label;

  void update(int current, [String? newLabel]) {
    _current = current;
    if (newLabel != null) _label = newLabel;
    _draw();
    if (total > 0 && _current >= total) _finish();
  }

  void _draw() {
    if (_closed) return;
    if (!_colorOn) {
      _echo('  $_label: $_current/$total');
      return;
    }

    final pct = total > 0 ? (_current / total).clamp(0.0, 1.0) : 1.0;

    // Braille bar: width scales to terminal, max 20 chars.
    final barW = math.min(20, math.max(8, _cols - 40));
    final filled = (barW * pct).round();
    final empty = barW - filled;
    final bar = '${yellow('⣿' * filled)}${gray('⣀' * empty)}';

    _spin = (_spin + 1) % _frames.length;
    final pctStr = '${(pct * 100).round()}%'.padLeft(4);

    stdout.write('\r\x1b[K  ${cyan(_frames[_spin])} $_label  $bar $pctStr');
  }

  /// Finish: print the final status line. This is intentionally async and
  /// fire-and-forget (called without `await` from [update] and [close]).
  /// The 500ms delay keeps fast ops readable; if the process exits early,
  /// the final line may not print — acceptable for a CLI progress aid.
  void _finish() async {
    if (_closed) return;
    _closed = true;
    _sw.stop();
    // Keep bar visible for at least 500ms so fast ops are readable.
    final elapsed = _sw.elapsedMilliseconds;
    if (elapsed < 500)
      await Future.delayed(Duration(milliseconds: 500 - elapsed));
    final ms = _sw.elapsedMilliseconds;
    final time = ms >= 1000 ? '${(ms / 1000).toStringAsFixed(1)}s' : '${ms}ms';
    if (_colorOn) {
      stdout.write('\r\x1b[K  ${green('✓')} $_label in $time\n');
    } else {
      _echo('  ✓ $_label in $time');
    }
  }

  /// Force finish (for when total is not reached).
  void close() {
    if (!_closed) _finish();
  }
}

// ── Table ────────────────────────────────────────────────────────────────────

/// Column-aligned table inside a bordered box.
///
/// Example:
/// ```dart
/// table('3 bundles', ['#', 'ID', 'CHANNEL', 'ON'], [
///   ['0', 'abc-123', 'production', '✓'],
///   ['1', 'def-456', 'staging', '✗'],
/// ]);
/// ```
void table(String title, List<String> headers, List<List<String>> rows) {
  if (headers.isEmpty) return;

  // Calculate column widths from content.
  final colCount = headers.length;
  final colWidths = List<int>.filled(colCount, 0);
  for (var i = 0; i < colCount; i++) {
    colWidths[i] = _dispWidth(headers[i]);
  }
  for (final row in rows) {
    for (var i = 0; i < colCount && i < row.length; i++) {
      colWidths[i] = math.max(colWidths[i], _dispWidth(row[i]));
    }
  }

  // Build formatted lines.
  final formatted = <String>[];

  // Header line.
  final headerParts = <String>[];
  for (var i = 0; i < colCount; i++) {
    headerParts.add(headers[i].padRight(colWidths[i]));
  }
  formatted.add(bold(headerParts.join('  ')));

  // Separator line.
  final sepParts = <String>[];
  for (var i = 0; i < colCount; i++) {
    sepParts.add('─' * colWidths[i]);
  }
  formatted.add(dim(sepParts.join('  ')));

  // Data rows.
  for (final row in rows) {
    final parts = <String>[];
    for (var i = 0; i < colCount; i++) {
      final cell = i < row.length ? row[i] : '';
      parts.add(cell.padRight(colWidths[i]));
    }
    formatted.add(parts.join('  '));
  }

  box(title, formatted);
}
