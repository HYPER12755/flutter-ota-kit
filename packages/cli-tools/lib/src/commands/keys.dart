import 'dart:convert';
import 'dart:io';

import '../cli_base.dart';
import '../config.dart';
import '../sign.dart';
import '../ui/ui.dart';

/// `flutter_ota_kit keys` — generate an Ed25519 keypair for bundle signing.
class KeysCommand extends FlutterPatcherCommand {
  KeysCommand() {
    argParser.addFlag(
      'save',
      help: 'Persist the public key into the project config.',
    );
  }

  @override
  String get name => 'keys';

  @override
  String get description =>
      'Generate an Ed25519 keypair used to sign deployed bundles.';

  @override
  Future<int> run() => runGuarded(() async {
    banner('keys');
    final steps = Steps('keys');
    final (privateB64, publicB64) = await steps.run(
      'Generating Ed25519 keypair',
      () => generateEd25519KeyPair(),
      // Use Steps.run without the spinner pattern; keys is fast.
    );
    box('ed25519 keys', [
      '${bold('private')} (keep secret — use with `deploy --key`):',
      '  ${red(privateB64)}',
      '',
      '${bold('public')} (safe to embed / configure on device):',
      '  ${green(publicB64)}',
    ]);
    if (argResults!['save'] as bool) {
      final file = configCandidates().first;
      final json =
          file.existsSync() && file.readAsStringSync().trim().isNotEmpty
          ? (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)
          : <String, dynamic>{};
      writePath(json, 'publicKey', publicB64);
      await steps.run<void>('Saving public key to ${file.path}', () async {
        _save(json);
      });
    }
    steps.summary();
  });

  void _save(Map<String, dynamic> json) {
    final file = configCandidates().first;
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
    if (!Platform.isWindows) {
      Process.runSync('chmod', ['600', file.path]);
    }
  }
}
