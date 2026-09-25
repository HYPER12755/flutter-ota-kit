/// SemVer range evaluation following node-semver semantics (as verkit).
///
/// A range is `||`-separated comparator sets; each set is space-separated
/// AND-ed comparators. Shorthand (~, ^, x-ranges, partials, hyphen ranges)
/// is expanded into primitive comparators.
library;

import 'semver_version.dart';

enum _Op { lt, lte, gt, gte, eq }

class _Comparator {
  final _Op op;
  final SemVer version;
  const _Comparator(this.op, this.version);

  bool test(SemVer v) {
    switch (op) {
      case _Op.lt:
        return v < version;
      case _Op.lte:
        return v <= version;
      case _Op.gt:
        return v > version;
      case _Op.gte:
        return v >= version;
      case _Op.eq:
        // Build metadata ignored for equality of ranges.
        return v.major == version.major &&
            v.minor == version.minor &&
            v.patch == version.patch &&
            v.prerelease.join('.') == version.prerelease.join('.');
    }
  }

  /// Whether this comparator explicitly opts a version into prerelease
  /// testing: same major.minor.patch tuple with its own prerelease set.
  bool allowsPrereleaseOf(SemVer v) =>
      version.isPrerelease &&
      version.major == v.major &&
      version.minor == v.minor &&
      version.patch == v.patch;

  @override
  String toString() => '${_opStr(op)}$version';
}

String _opStr(_Op o) => switch (o) {
  _Op.lt => '<',
  _Op.lte => '<=',
  _Op.gt => '>',
  _Op.gte => '>=',
  _Op.eq => '=',
};

final RegExp _xRe = RegExp(r'^[xX*]$');

bool _isX(String? s) => s == null || s.isEmpty || _xRe.hasMatch(s);

/// Expands one raw comparator token into primitives.
List<_Comparator> _parseToken(String raw) {
  var t = raw.trim();
  if (t.isEmpty || t == '*' || t == 'x' || t == 'X') return const [];

  // Strip operator prefix.
  String op;
  if (t.startsWith('>=')) {
    op = '>=';
    t = t.substring(2);
  } else if (t.startsWith('<=')) {
    op = '<=';
    t = t.substring(2);
  } else if (t.startsWith('>')) {
    op = '>';
    t = t.substring(1);
  } else if (t.startsWith('<')) {
    op = '<';
    t = t.substring(1);
  } else if (t.startsWith('~')) {
    op = '~';
    t = t.substring(1);
  } else if (t.startsWith('^')) {
    op = '^';
    t = t.substring(1);
  } else {
    if (t.startsWith('=')) t = t.substring(1);
    op = '';
  }
  t = t.trim();

  final m = RegExp(
    r'^v?(\d+|x|X|\*)(?:\.(\d+|x|X|\*))?(?:\.(\d+|x|X|\*))?'
    r'(?:-((?:[0-9A-Za-z-]+)(?:\.[0-9A-Za-z-]+)*))?'
    r'(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$',
  ).firstMatch(t);
  if (m == null) throw FormatException('invalid comparator: $raw');

  final majS = m.group(1)!;
  final minS = m.group(2);
  final patS = m.group(3);
  final preRaw = m.group(4);

  final majIsX = _isX(majS);
  final minIsX = !majIsX && _isX(minS);
  final patIsX = !(majIsX || minIsX) && _isX(patS);
  final hasPre = preRaw != null && preRaw.isNotEmpty;

  SemVer ver(String a, String b, String c, [List<String> pre = const []]) =>
      SemVer(int.parse(a), int.parse(b), int.parse(c), pre);

  // Full X handling per node-semver replaceXRanges rules.
  if (majIsX) {
    return const [_Comparator(_Op.gte, SemVer(0, 0, 0))];
  }

  final hasMinor = !minIsX;
  final hasPatch = hasMinor && !patIsX;

  switch (op) {
    case '':
    case '=':
      if (!hasMinor) {
        return [
          _Comparator(_Op.gte, ver(majS, '0', '0')),
          _Comparator(_Op.lt, ver('${int.parse(majS) + 1}', '0', '0')),
        ];
      }
      if (!hasPatch) {
        return [
          _Comparator(_Op.gte, ver(majS, minS!, '0')),
          _Comparator(_Op.lt, ver(majS, '${int.parse(minS) + 1}', '0')),
        ];
      }
      final pre = hasPre ? preRaw.split('.') : const <String>[];
      return [_Comparator(_Op.eq, ver(majS, minS!, patS!, pre))];

    case '>':
      if (!hasMinor) {
        return [_Comparator(_Op.gte, ver('${int.parse(majS) + 1}', '0', '0'))];
      }
      if (!hasPatch) {
        return [
          _Comparator(_Op.gte, ver(majS, '${int.parse(minS!) + 1}', '0')),
        ];
      }
      return [_Comparator(_Op.gt, ver(majS, minS!, patS!))];

    case '>=':
      if (!hasMinor) {
        return [_Comparator(_Op.gte, ver(majS, '0', '0'))];
      }
      if (!hasPatch) {
        return [_Comparator(_Op.gte, ver(majS, minS!, '0'))];
      }
      return [
        _Comparator(
          _Op.gte,
          ver(majS, minS!, patS!, hasPre ? preRaw.split('.') : const []),
        ),
      ];

    case '<':
      if (!hasMinor) {
        return [_Comparator(_Op.lt, ver(majS, '0', '0'))];
      }
      if (!hasPatch) {
        return [_Comparator(_Op.lt, ver(majS, minS!, '0'))];
      }
      return [
        _Comparator(
          _Op.lt,
          ver(majS, minS!, patS!, hasPre ? preRaw.split('.') : const []),
        ),
      ];

    case '<=':
      if (!hasMinor) {
        // <=* handled above; here <=N means < N+1.0.0
        return [_Comparator(_Op.lt, ver('${int.parse(majS) + 1}', '0', '0'))];
      }
      if (!hasPatch) {
        return [_Comparator(_Op.lt, ver(majS, '${int.parse(minS!) + 1}', '0'))];
      }
      return [
        _Comparator(
          _Op.lte,
          ver(majS, minS!, patS!, hasPre ? preRaw.split('.') : const []),
        ),
      ];

    case '~':
      if (!hasMinor) {
        return [
          _Comparator(_Op.gte, ver(majS, '0', '0')),
          _Comparator(_Op.lt, ver('${int.parse(majS) + 1}', '0', '0')),
        ];
      }
      if (!hasPatch) {
        return [
          _Comparator(_Op.gte, ver(majS, minS!, '0')),
          _Comparator(_Op.lt, ver(majS, '${int.parse(minS) + 1}', '0')),
        ];
      }
      return [
        _Comparator(
          _Op.gte,
          ver(majS, minS!, patS!, hasPre ? preRaw.split('.') : const []),
        ),
        _Comparator(_Op.lt, ver(majS, '${int.parse(minS) + 1}', '0')),
      ];

    case '^':
      if (!hasMinor) {
        return [
          _Comparator(_Op.gte, ver(majS, '0', '0')),
          _Comparator(_Op.lt, ver('${int.parse(majS) + 1}', '0', '0')),
        ];
      }
      if (!hasPatch) {
        if (int.parse(majS) == 0) {
          return [
            _Comparator(_Op.gte, ver('0', minS!, '0')),
            _Comparator(_Op.lt, ver('0', '${int.parse(minS) + 1}', '0')),
          ];
        }
        return [
          _Comparator(_Op.gte, ver(majS, minS!, '0')),
          _Comparator(_Op.lt, ver('${int.parse(majS) + 1}', '0', '0')),
        ];
      }
      final maj = int.parse(majS);
      final min = int.parse(minS!);
      final pat = int.parse(patS!);
      final upper = maj > 0
          ? SemVer(maj + 1, 0, 0)
          : (min > 0 ? SemVer(0, min + 1, 0) : SemVer(0, 0, pat + 1));
      return [
        _Comparator(
          _Op.gte,
          ver(majS, minS, patS, hasPre ? preRaw.split('.') : const []),
        ),
        _Comparator(_Op.lt, upper),
      ];
  }
  throw StateError('unreachable');
}

/// Splits a comparator set string into individual comparator tokens,
/// correctly joining operator prefixes (`>=`, `<=`, `>`, `<`, `~`, `^`, `=`)
/// with their following version string even when separated by whitespace.
///
/// For example, `>= 5.7.0 <= 5.7.4` → `['>= 5.7.0', '<= 5.7.4']`.
List<String> _splitComparators(String set) {
  final tokens = <String>[];
  // Match operator-prefixed comparators first (e.g., ">= 5.7.0"), then bare tokens.
  final re = RegExp(r'(?:>=|<=|>|<|~|\^|=)\s*\S+|\S+');
  for (final m in re.allMatches(set)) {
    tokens.add(m.group(0)!.trim());
  }
  return tokens;
}

List<List<_Comparator>> _parseRange(String range) {
  final sets = range.trim().split(r'||');
  final result = <List<_Comparator>>[];
  for (var set in sets.map((s) => s.trim()).toList()) {
    if (set.isEmpty) set = '*';
    // Hyphen ranges first.
    final hyphenMatch = RegExp(r'^\s*(\S+)\s+-\s+(\S+)\s*$').firstMatch(set);
    if (hyphenMatch != null) {
      final comps = _hyphenToComparators(
        hyphenMatch.group(1)!,
        hyphenMatch.group(2)!,
      );
      result.add(comps);
      continue;
    }
    final comparators = <_Comparator>[];
    for (final token in _splitComparators(set)) {
      comparators.addAll(_parseToken(token));
    }
    result.add(comparators);
  }
  return result;
}

List<_Comparator> _hyphenToComparators(String leftRaw, String rightRaw) {
  final out = <_Comparator>[];
  final fullRe = RegExp(
    r'^v?(\d+|x|X|\*)(?:\.(\d+|x|X|\*))?(?:\.(\d+|x|X|\*))?'
    r'(?:-((?:[0-9A-Za-z-]+)(?:\.[0-9A-Za-z-]+)*))?'
    r'(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$',
  );

  // Left side: full version (with optional prerelease) -> inclusive lower.
  final lm = fullRe.firstMatch(leftRaw.trim());
  if (lm != null) {
    final maj = lm.group(1)!;
    final min = lm.group(2);
    final pat = lm.group(3);
    final pre = lm.group(4)?.split('.') ?? const <String>[];
    if (_isX(min)) {
      out.add(_Comparator(_Op.gte, SemVer(int.parse(maj), 0, 0)));
    } else if (_isX(pat)) {
      out.add(_Comparator(_Op.gte, SemVer(int.parse(maj), int.parse(min!), 0)));
    } else {
      out.add(
        _Comparator(
          _Op.gte,
          SemVer(int.parse(maj), int.parse(min!), int.parse(pat!), pre),
        ),
      );
    }
  }

  // Right side: partial -> exclusive upper bound at next boundary;
  // full version -> inclusive upper.
  final rm = fullRe.firstMatch(rightRaw.trim());
  if (rm != null) {
    final maj = rm.group(1)!;
    final min = rm.group(2);
    final pat = rm.group(3);
    final pre = rm.group(4)?.split('.') ?? const <String>[];
    if (_isX(min)) {
      out.add(_Comparator(_Op.lt, SemVer(int.parse(maj) + 1, 0, 0)));
    } else if (_isX(pat)) {
      out.add(
        _Comparator(_Op.lt, SemVer(int.parse(maj), int.parse(min!) + 1, 0)),
      );
    } else {
      out.add(
        _Comparator(
          _Op.lte,
          SemVer(int.parse(maj), int.parse(min!), int.parse(pat!), pre),
        ),
      );
    }
  }
  return out;
}

/// node-semver `satisfies(version, range)` with default options:
/// prerelease versions only match when some comparator in the matched set
/// carries the same major.minor.patch tuple WITH a prerelease.
bool satisfies(SemVer version, String range) {
  List<List<_Comparator>> sets;
  try {
    sets = _parseRange(range);
  } on FormatException {
    return false;
  }
  for (final set in sets) {
    var ok = true;
    for (final c in set) {
      if (!c.test(version)) {
        ok = false;
        break;
      }
    }
    if (!ok) continue;
    if (version.isPrerelease) {
      final allowed = set.any((c) => c.allowsPrereleaseOf(version));
      if (!allowed) continue;
    }
    return true;
  }
  return false;
}
