import 'package:flutter_patcher_core/flutter_patcher_core.dart';
void main() {
  // ignore: avoid_print
  print('coerce=${semverCoerce('app version 2.3.6!')}');
  print('sat=${satisfies(const SemVer(2, 3, 6), '~2.3.4')}');
}
