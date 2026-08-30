import 'dart:io';

void main(List<String> args) {
  final mode = args[0]; // 'hosted' or 'path'
  final files = args.skip(1).toList();
  final hostedFor = {
    'flutter_ota_kit_core': '^0.1.0',
    'flutter_ota_kit_plugin_core': '^0.0.1',
    'flutter_ota_kit_client': '^0.1.0',
    'flutter_ota_kit_supabase': '^0.1.0',
    'flutter_ota_kit_postgres': '^0.1.0',
    'flutter_ota_kit_cloudflare': '^0.1.0',
    'flutter_ota_kit_aws': '^0.1.0',
  };
  final pathFor = {
    'flutter_ota_kit_core': '../../packages/core',
    'flutter_ota_kit_plugin_core': '../plugin-core',
    'flutter_ota_kit_client': 'packages/client',
    'flutter_ota_kit_supabase': 'plugins/supabase',
    'flutter_ota_kit_postgres': 'plugins/postgres',
    'flutter_ota_kit_cloudflare': 'plugins/cloudflare',
    'flutter_ota_kit_aws': 'plugins/aws',
  };
  final pathRe = RegExp(r'^(\s*)path:\s*(\S+)\s*$');
  for (final f in files) {
    final lines = File(f).readAsLinesSync();
    final out = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final m = pathRe.firstMatch(line);
      if (m != null) {
        final prev = lines[i - 1].trim().replaceAll(':', '').trim();
        if (mode == 'hosted' && hostedFor.containsKey(prev)) {
          out.add('${m.group(1)}${hostedFor[prev]}');
          continue;
        }
        if (mode == 'path' && pathFor.containsKey(prev)) {
          out.add('${m.group(1)}path: ${pathFor[prev]}');
          continue;
        }
      }
      out.add(line);
    }
    File(f).writeAsStringSync('${out.join('\n')}\n');
    stdout.writeln('converted $f -> $mode');
  }
}
