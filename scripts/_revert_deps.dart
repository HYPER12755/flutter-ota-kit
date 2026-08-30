import 'dart:io';

void main(List<String> args) {
  final pluginPathFor = {
    'flutter_ota_kit_core': '../../packages/core',
    'flutter_ota_kit_plugin_core': '../plugin-core',
    'flutter_ota_kit_client': 'packages/client',
    'flutter_ota_kit_supabase': 'plugins/supabase',
    'flutter_ota_kit_postgres': 'plugins/postgres',
    'flutter_ota_kit_cloudflare': 'plugins/cloudflare',
    'flutter_ota_kit_aws': 'plugins/aws',
  };
  final rootPathFor = {
    'flutter_ota_kit_core': 'packages/core',
    'flutter_ota_kit_plugin_core': 'plugins/plugin-core',
    'flutter_ota_kit_client': 'packages/client',
    'flutter_ota_kit_supabase': 'plugins/supabase',
    'flutter_ota_kit_postgres': 'plugins/postgres',
    'flutter_ota_kit_cloudflare': 'plugins/cloudflare',
    'flutter_ota_kit_aws': 'plugins/aws',
  };
  final verRe = RegExp(r'^(\s*)\^[\d.]+\s*$');
  for (final f in args) {
    final lines = File(f).readAsLinesSync();
    final isRoot = lines.any((l) => l.trim() == 'name: flutter_ota_kit');
    final map = isRoot ? rootPathFor : pluginPathFor;
    final out = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final m = verRe.firstMatch(line);
      if (m != null) {
        final prev = lines[i - 1].trim().replaceAll(':', '').trim();
        if (map.containsKey(prev)) {
          out.add('${m.group(1)}path: ${map[prev]}');
          continue;
        }
      }
      out.add(line);
    }
    File(f).writeAsStringSync('${out.join('\n')}\n');
    stdout.writeln('reverted $f -> path');
  }
}
