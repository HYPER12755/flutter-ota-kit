// Smoke test for the flutter_ota_kit example app.

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_ota_kit_example/main.dart';

void main() {
  testWidgets('example app renders the OTA home screen', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    // The custom OTA demo UI, not the default counter template.
    expect(find.text('Flutter OTA Kit'), findsWidgets);
    expect(find.text('Check for Update'), findsOneWidget);
    expect(find.text('Apply Update'), findsOneWidget);
    expect(find.text('Rollback'), findsOneWidget);
    expect(find.text('Show Diagnostics'), findsOneWidget);
  });
}
