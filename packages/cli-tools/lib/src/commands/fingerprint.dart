import '../cli_base.dart';
import '../ui/ui.dart';
import '../util.dart';

/// `flutter_ota_kit fingerprint` — compute a build-time fingerprint hash.
class FingerprintCommand extends FlutterPatcherCommand {
  FingerprintCommand() {
    argParser.addOption(
      'source',
      abbr: 's',
      defaultsTo: './dist',
      help: 'Directory to fingerprint.',
    );
  }

  @override
  String get name => 'fingerprint';

  @override
  String get description =>
      'Compute a deterministic fingerprint hash for a directory (build-time).';

  @override
  Future<int> run() => runGuarded(() async {
    banner(name);
    final source = argResults!['source'] as String;
    final hash = generateFingerprint(source);
    box('fingerprint', [kv('source', source), kv('hash', hash)]);
  });
}
