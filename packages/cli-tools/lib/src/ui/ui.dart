library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

/// Terminal UI toolkit for the flutter_ota_kit CLI: colored text, banners,
/// bordered boxes, step logs, dynamic spinners and progress bars.
///
/// Everything degrades gracefully to plain text when stdout is not a TTY or the
/// `NO_COLOR` env var is set, so pipes/CI/tests stay clean. Boxes auto-size to
/// the terminal width and wrap long content so they never render broken.

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

bool get _noColor {
  final v = Platform.environment['NO_COLOR'];
  return v != null && v.isNotEmpty;
}

bool get _colorOn =>
    !_noColor && stdout.hasTerminal && stdout.supportsAnsiEscapes;

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

int get _cols => stdout.hasTerminal ? stdout.terminalColumns : 80;

final _ansi = RegExp('\x1b\\[[0-9;]*m');

int _dispWidth(String s) => s.replaceAll(_ansi, '').length;

void _echo(String s) => stdout.writeln(s);

/// `key  value` laid out in a fixed 18-char column (visible-width aware).
String kv(String k, String v) {
  final pad = math.max(0, 18 - _dispWidth(k));
  return '${dim(k)}${' ' * pad}  $v';
}

void banner(String name) {
  _echo('');
  _echo(
    '  ${cyan('▶')} ${cyan(bold('flutter-ota'))} ${dim('·')} ${bold(name)}',
  );
  _echo('  ${dim('─' * math.min(_cols - 4, 60))}');
}

void step(String msg) => _echo('  ${green('✓')} $msg');

void warn(String msg) => _echo('  ${yellow('!')} ${yellow(msg)}');

void err(String msg) => _echo('  ${red('✗')} ${red(msg)}');

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
  final timer = Timer.periodic(const Duration(milliseconds: 80), (_) {
    i = (i + 1) % _frames.length;
    stdout.write('\r\x1b[K  ${cyan(_frames[i])} $label');
  });
  try {
    final r = await task();
    timer.cancel();
    stdout.write('\r\x1b[K  ${green('✓')} ${done ?? label}\n');
    return r;
  } catch (e) {
    timer.cancel();
    stdout.write('\r\x1b[K  ${red('✗')} $label\n');
    rethrow;
  }
}

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
    final cut = _cut(rem, inner);
    out.add(cut);
    rem = rem.substring(cut.length);
  }
  return rem;
}

int _boxWidth(List<String> lines, String title) {
  var longest = _dispWidth(title) + 4;
  for (final l in lines) {
    for (final w in l.split('\n')) {
      longest = math.max(longest, _dispWidth(w));
    }
  }
  final target = math.max(longest + 4, 40);
  return math.max(math.min(_cols - 1, target), 20);
}

/// Bordered box with a centered title; auto-sizes to the terminal and wraps
/// long content so the right/left edges always stay aligned.
void box(String title, List<String> lines) {
  final width = _boxWidth(lines, title);
  final inner = width - 4;
  final wrapped = <String>[];
  for (final l in lines) {
    wrapped.addAll(_wrap(l, inner));
  }

  final titleText = ' $title ';
  final tVisible = _dispWidth(titleText);
  var dashes = math.max(2, width - 2 - tVisible);
  final left = math.max(1, dashes ~/ 2);
  final right = dashes - left;
  final top = '╭${'─' * left}$titleText${'─' * right}╮';
  _echo(top);
  for (final l in wrapped) {
    final pad = math.max(0, inner - _dispWidth(l));
    _echo('│ $l${' ' * pad} │');
  }
  _echo('╰${'─' * (width - 2)}╯');
}

/// Live progress bar with an animated spinner prefix. Call [update] as work
/// progresses; it renders a `[████░░] 45%` bar that overwrites the same line.
class ProgressBar {
  ProgressBar(this.total, this.label);

  int total;
  final String label;
  int _current = 0;
  int _spin = 0;
  bool _closed = false;

  void update(int current, [String? label]) {
    _current = current;
    if (label != null) _label = label;
    _draw();
    if (total > 0 && _current >= total) _finish();
  }

  late String _label = label;

  void _draw() {
    if (_closed) return;
    if (!_colorOn) {
      _echo('  $_label: $_current/$total');
      return;
    }
    const barW = 28;
    final pct = total > 0 ? (_current / total).clamp(0.0, 1.0) : 1.0;
    final filled = (barW * pct).round();
    final bar = '${green('█' * filled)}${gray('·' * (barW - filled))}';
    _spin = (_spin + 1) % _frames.length;
    final pctStr = '${(pct * 100).round()}%'.padLeft(4);
    stdout.write('\r\x1b[K  ${cyan(_frames[_spin])} $_label  [$bar] $pctStr');
  }

  void _finish() {
    if (_closed) return;
    _closed = true;
    if (_colorOn) stdout.write('\n');
  }
}
