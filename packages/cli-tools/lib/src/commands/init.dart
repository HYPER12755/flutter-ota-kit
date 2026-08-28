import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../backend.dart';
import '../cli_base.dart';
import '../config.dart';

/// `flutter_patcher init` — scaffold a project config file.
class InitCommand extends Command<int> {
  InitCommand({this.config, this.backendOverride});

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'init';

  @override
  String get description =>
      'Scaffold a .flutter_patcher.json config for the current project.';

  @override
  ArgParser get argParser => ArgParser()
    ..addOption('provider', defaultsTo: 'supabase', help: 'Backend provider.')
    ..addOption('url', help: 'Supabase project URL.')
    ..addOption('key', help: 'Supabase service role key.')
    ..addOption('anon-key', help: 'Supabase anon key.')
    ..addOption('bucket', defaultsTo: 'bundles', help: 'Storage bucket.')
    ..addOption('base-path', help: 'Storage base path.')
    ..addOption('channel', defaultsTo: 'production', help: 'Default channel.')
    ..addOption('platform', defaultsTo: 'android', help: 'Default platform.')
    ..addOption('source', defaultsTo: './dist', help: 'Default deploy source.')
    ..addFlag('force', abbr: 'f', help: 'Overwrite an existing config.');

  String? _prompt(String label, String? current) {
    if (!stdin.hasTerminal) return current;
    stdout.write('$label${current != null ? ' [$current]' : ''}: ');
    final line = stdin.readLineSync();
    return (line == null || line.trim().isEmpty) ? current : line.trim();
  }

  @override
  Future<int> run() => runGuarded(() async {
        final file = configCandidates().first;
        if (file.existsSync() && !(argResults!['force'] as bool)) {
          throw StateError(
            'Config already exists at ${file.path}. Use --force to overwrite.',
          );
        }

        final provider = argResults!['provider'] as String;
        final url = _prompt('Supabase URL', argResults!['url'] as String?);
        final key = _prompt(
          'Supabase service role key',
          argResults!['key'] as String?,
        );
        final anonKey = argResults!['anon-key'] as String?;
        final bucket = argResults!['bucket'] as String? ?? 'bundles';
        final basePath = argResults!['base-path'] as String?;
        final channel = argResults!['channel'] as String? ?? 'production';
        final platform = argResults!['platform'] as String? ?? 'android';
        final source = argResults!['source'] as String? ?? './dist';

        final cfg = FlutterPatcherConfig(
          provider: provider,
          supabase: SupabaseConfigJson(
            url: url,
            serviceRoleKey: key,
            anonKey: anonKey,
            bucket: bucket,
            basePath: basePath,
          ),
          channel: channel,
          platform: platform,
          source: source,
        );
        saveConfig(cfg);
        stdout.writeln('Wrote ${file.path}');
      });
}
