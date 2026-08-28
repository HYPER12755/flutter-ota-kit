import 'dart:io';

import 'package:flutter_patcher_cli/flutter_patcher_cli.dart';

/// `flutter_patcher` executable entry point.
Future<void> main(List<String> args) async {
  final code = await run(args);
  if (code != 0) exitCode = code;
}
