import 'dart:convert';

import 'package:args/args.dart';

import '../backend.dart';
import '../cli_base.dart';
import '../config.dart';
import '../sign.dart';
import '../ui/ui.dart';

/// `flutter_ota_kit keys` — generate an Ed25519 keypair for bundle signing.
class KeysCommand extends FlutterPatcherCommand {
  KeysCommand({this.config, this.backendOverride});

  final FlutterPatcherConfig? config;
  final Backend? backendOverride;

  @override
  String get name => 'keys';

  @override
  String get description =>
      'Generate an Ed25519 keypair used to sign deployed bundles.';

  @override
  ArgParser get argParser => ArgParser()
    ..addFlag('save', help: 'Persist the public key into the project config.');

  @override
  Future<int> run() => runGuarded(() async {
    banner('keys');
    final (privateB64, publicB64) = await spinner(
      () => generateEd25519KeyPair(),
      'Generating Ed25519 keypair',
      done: 'Keypair generated',
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
      _save(json);
      step('Saved public key to ${file.path}');
    }
  });

  void _save(Map<String, dynamic> json) {
    final file = configCandidates().first;
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
  }
}
