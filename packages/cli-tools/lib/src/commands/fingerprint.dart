import 'dart:io';

import 'package:args/args.dart';

import '../cli_base.dart';
import '../util.dart';

/// `flutter_ota_kit fingerprint` — compute a build-time fingerprint hash.
class FingerprintCommand extends FlutterPatcherCommand {
  @override
  String get name => 'fingerprint';

  @override
  String get description =>
      'Compute a deterministic fingerprint hash for a directory (build-time).';

  @override
  ArgParser get argParser => ArgParser()
    ..addOption(
      'source',
      abbr: 's',
      defaultsTo: './dist',
      help: 'Directory to fingerprint.',
    );

  @override
  Future<int> run() => runGuarded(() async {
    final source = argResults!['source'] as String;
    final hash = generateFingerprint(source);
    stdout.writeln(hash);
  });
}
