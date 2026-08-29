import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart';
void main() {
  // ignore: avoid_print
  print('coerce=${semverCoerce('app version 2.3.6!')}');
  print('sat=${satisfies(const SemVer(2, 3, 6), '~2.3.4')}');
}
