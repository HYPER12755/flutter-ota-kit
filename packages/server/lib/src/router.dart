/// Minimal path router supporting `:param` segments (mirrors hot-updater's
/// `rou3`-based `internalRouter`).
class Router {
  final List<_Route> _routes = [];

  /// Register a route. [pattern] is a leading-slash path with `:name` params.
  void add(String method, String pattern, String name) {
    final segments =
        pattern.split('/').where((s) => s.isNotEmpty).toList();
    final paramNames = <String>[];
    for (final s in segments) {
      paramNames.add(s.startsWith(':') ? s.substring(1) : '');
    }
    _routes.add(_Route(method, segments, name, paramNames));
  }

  /// Find a matching route for [method]/[path]; returns the route name and
  /// decoded params, or `null` when nothing matches.
  ({String name, Map<String, String> params})? find(
    String method,
    String path,
  ) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    for (final route in _routes) {
      if (route.method != method) continue;
      if (route.segments.length != segments.length) continue;

      final params = <String, String>{};
      var matched = true;
      for (var i = 0; i < route.segments.length; i++) {
        final seg = route.segments[i];
        if (seg.startsWith(':')) {
          params[seg.substring(1)] = Uri.decodeComponent(segments[i]);
        } else if (seg != segments[i]) {
          matched = false;
          break;
        }
      }
      if (matched) return (name: route.name, params: params);
    }
    return null;
  }
}

class _Route {
  _Route(this.method, this.segments, this.name, this.paramNames);

  final String method;
  final List<String> segments;
  final String name;
  final List<String> paramNames;
}
