import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../backend.dart';
import '../cli_base.dart';
import '../config.dart';
import '../sign.dart';

/// `flutter_patcher keys` — generate an Ed25519 keypair for bundle signing.
class KeysCommand extends Command<int> {
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
        final (privateB64, publicB64) = await generateEd25519KeyPair();
        stdout.writeln('Private key (keep secret, use with `deploy --key`):');
        stdout.writeln('  $privateB64');
        stdout.writeln('');
        stdout.writeln('Public key (safe to embed / configure on device):');
        stdout.writeln('  $publicB64');
        if (argResults!['save'] as bool) {
          final file = configCandidates().first;
          final json = file.existsSync() && file.readAsStringSync().trim().isNotEmpty
              ? (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)
              : <String, dynamic>{};
          writePath(json, 'publicKey', publicB64);
          _save(json);
          stdout.writeln('');
          stdout.writeln('Saved public key to ${file.path}');
        }
      });

  void _save(Map<String, dynamic> json) {
    final file = configCandidates().first;
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
  }
}
