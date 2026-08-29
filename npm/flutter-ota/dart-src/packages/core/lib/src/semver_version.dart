/// SemVer version parsing/comparison following the node-semver conventions
/// that verkit (hot-updater's semver dependency) implements.
library;

class SemVer implements Comparable<SemVer> {
  final int major;
  final int minor;
  final int patch;
  final List<String> prerelease; // identifiers; numeric ones stay numeric-ish
  final String? build;

  const SemVer(
    this.major,
    this.minor,
    this.patch, [
    this.prerelease = const [],
    this.build,
  ]);

  /// Strict-ish parse; allows partials ("1", "1.2") padded with zeros.
  /// Returns null on failure.
  static SemVer? tryParse(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    final m = RegExp(
      r'^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?'
      r'(?:-((?:[0-9A-Za-z-]+)(?:\.[0-9A-Za-z-]+)*))?'
      r'(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$',
    ).firstMatch(s);
    if (m == null) return null;
    return SemVer(
      int.parse(m.group(1)!),
      int.tryParse(m.group(2) ?? '') ?? 0,
      int.tryParse(m.group(3) ?? '') ?? 0,
      m.group(4)?.split('.') ?? const [],
      m.group(5),
    );
  }

  factory SemVer.fromJson(Map<String, dynamic> j) => SemVer(
        j['major'] as int,
        j['minor'] as int,
        j['patch'] as int,
        (j['prerelease'] as List?)?.map((e) => '$e').toList() ?? const [],
        j['build'] as String?,
      );

  bool get isPrerelease => prerelease.isNotEmpty;

  @override
  String toString() => '$major.$minor.$patch'
      '${prerelease.isEmpty ? '' : '-${prerelease.join('.')}'}'
      '${build == null ? '' : '+$build'}';

  @override
  int compareTo(SemVer o) {
    final main = [major, minor, patch];
    final other = [o.major, o.minor, o.patch];
    for (var i = 0; i < 3; i++) {
      final c = main[i].compareTo(other[i]);
      if (c != 0) return c;
    }
    // Empty prerelease set > non-empty.
    if (prerelease.isEmpty && o.prerelease.isEmpty) return 0;
    if (prerelease.isEmpty) return 1;
    if (o.prerelease.isEmpty) return -1;
    for (var i = 0; i < prerelease.length && i < o.prerelease.length; i++) {
      final c = _compareIdentifier(prerelease[i], o.prerelease[i]);
      if (c != 0) return c;
    }
    return prerelease.length.compareTo(o.prerelease.length);
  }

  static int _compareIdentifier(String a, String b) {
    final na = int.tryParse(a);
    final nb = int.tryParse(b);
    if (na != null && nb != null) return na.compareTo(nb);
    if (na != null) return -1; // numeric < alphanumeric
    if (nb != null) return 1;
    return a.compareTo(b);
  }

  @override
  bool operator ==(Object o) =>
      o is SemVer && compareTo(o) == 0 && o.build == build;

  @override
  int get hashCode => Object.hash(major, minor, patch, prerelease);

  bool operator <(SemVer o) => compareTo(o) < 0;
  bool operator >(SemVer o) => compareTo(o) > 0;
  bool operator <=(SemVer o) => compareTo(o) <= 0;
  bool operator >=(SemVer o) => compareTo(o) >= 0;
}
