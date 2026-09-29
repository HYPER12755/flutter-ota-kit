import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ota_kit_example/game_screen.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('game screen renders start button, level chip and options', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: GameScreen()));

    expect(find.text('LV 1'), findsOneWidget);
    expect(find.textContaining('START'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(find.text('Wrap walls'), findsOneWidget);
    expect(find.text('Obstacles'), findsOneWidget);
    expect(find.text('Easy'), findsOneWidget);
    expect(find.text('Hard'), findsOneWidget);
  });
}
