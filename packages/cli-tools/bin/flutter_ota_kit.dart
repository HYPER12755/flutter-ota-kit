import 'dart:io';

import 'package:flutter_ota_kit_cli/flutter_ota_kit_cli.dart';

/// `flutter_ota_kit` executable entry point.
Future<void> main(List<String> args) async {
  final code = await run(args);
  if (code != 0) exitCode = code;
}
