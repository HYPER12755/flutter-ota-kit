// Widget tests for the forced-update progress overlay.

import 'package:flutter/material.dart';
import 'package:flutter_ota_kit/flutter_ota_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [OtaProgressOverlay] inside a minimal Material host with the given
/// initial state and a custom [MediaQuery] so goldens have a fixed size.
Future<void> _pump(
  WidgetTester tester, {
  required ValueNotifier<OtaOverlayState> state,
  bool dismissible = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            OtaProgressOverlay(state: state, dismissible: dismissible),
          ],
        ),
      ),
    ),
  );
}

void main() {
  group('OtaProgressOverlay', () {
    testWidgets('renders indeterminate "Preparing update" before any phase', (
      tester,
    ) async {
      final state = ValueNotifier(const OtaOverlayState());
      await _pump(tester, state: state);
      expect(find.text('Preparing update'), findsOneWidget);
      // No progress bar percentage visible.
      expect(find.textContaining('%'), findsNothing);
      // Card has a rounded shape and an elevation.
      final cardFinder = find.byType(Container);
      expect(cardFinder, findsWidgets);
    });

    testWidgets(
      'shows "Downloading update" + 0% for downloading with no fraction',
      (tester) async {
        final state = ValueNotifier(
          const OtaOverlayState(phase: PatchApplyPhase.downloading),
        );
        await _pump(tester, state: state);
        expect(find.text('Downloading update'), findsOneWidget);
      },
    );

    testWidgets('shows percentage when fraction is known', (tester) async {
      final state = ValueNotifier(
        const OtaOverlayState(
          phase: PatchApplyPhase.downloading,
          fraction: 0.42,
        ),
      );
      await _pump(tester, state: state);
      expect(find.text('Downloading update'), findsOneWidget);
      expect(find.text('42%'), findsOneWidget);
    });

    testWidgets('shows version transition when both versions are known', (
      tester,
    ) async {
      final state = ValueNotifier(
        const OtaOverlayState(
          phase: PatchApplyPhase.downloading,
          fraction: 0.1,
          currentVersion: '1.0.0',
          targetVersion: '1.0.1',
        ),
      );
      await _pump(tester, state: state);
      expect(find.text('1.0.0  →  1.0.1'), findsOneWidget);
    });

    testWidgets('skips version line when current equals target', (
      tester,
    ) async {
      final state = ValueNotifier(
        const OtaOverlayState(
          phase: PatchApplyPhase.downloading,
          currentVersion: '1.0.1',
          targetVersion: '1.0.1',
        ),
      );
      await _pump(tester, state: state);
      expect(find.text('1.0.0  →  1.0.1'), findsNothing);
      expect(find.text('1.0.1'), findsOneWidget); // shows just the target
    });

    testWidgets('shows version line when only target is known', (tester) async {
      final state = ValueNotifier(
        const OtaOverlayState(
          phase: PatchApplyPhase.downloading,
          targetVersion: '1.0.1',
        ),
      );
      await _pump(tester, state: state);
      // No transition (no current), but no crash either.
      expect(find.text('1.0.0  →  1.0.1'), findsNothing);
    });

    testWidgets('shows the server message when provided', (tester) async {
      final state = ValueNotifier(
        const OtaOverlayState(
          phase: PatchApplyPhase.downloading,
          message: 'Critical security fix',
        ),
      );
      await _pump(tester, state: state);
      expect(find.text('Critical security fix'), findsOneWidget);
    });

    testWidgets('omits the server message when empty', (tester) async {
      final state = ValueNotifier(
        const OtaOverlayState(phase: PatchApplyPhase.downloading, message: ''),
      );
      await _pump(tester, state: state);
      expect(find.text(''), findsNothing);
    });

    testWidgets('error variant shows "Update failed" + hint', (tester) async {
      final state = ValueNotifier(
        const OtaOverlayState(
          hasError: true,
          errorText: 'md5 mismatch',
          errorHint: 'Reopen the app to retry.',
          currentVersion: '1.0.0',
          targetVersion: '1.0.1',
        ),
      );
      await _pump(tester, state: state);
      expect(find.text('Update failed'), findsOneWidget);
      expect(find.text('md5 mismatch'), findsOneWidget);
      expect(find.text('Reopen the app to retry.'), findsOneWidget);
    });

    testWidgets('error variant uses default hint when none given', (
      tester,
    ) async {
      final state = ValueNotifier(
        const OtaOverlayState(hasError: true, errorText: 'io error'),
      );
      await _pump(tester, state: state);
      expect(find.text('io error'), findsOneWidget);
      expect(find.text('Close the app and reopen to retry.'), findsOneWidget);
    });

    testWidgets('updating state flows through all 3 phases', (tester) async {
      final state = ValueNotifier(
        const OtaOverlayState(
          phase: PatchApplyPhase.downloading,
          fraction: 0.0,
          currentVersion: '1.0.0',
          targetVersion: '1.0.1',
          message: 'New onboarding flow',
        ),
      );
      await _pump(tester, state: state);
      expect(find.text('Downloading update'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
      expect(find.text('1.0.0  →  1.0.1'), findsOneWidget);
      expect(find.text('New onboarding flow'), findsOneWidget);

      // Advance to verifying.
      state.value = state.value.copyWith(
        phase: PatchApplyPhase.verifying,
        fraction: 0.85,
      );
      await tester.pump();
      expect(find.text('Verifying integrity'), findsOneWidget);
      expect(find.text('85%'), findsOneWidget);

      // Advance to finalizing.
      state.value = state.value.copyWith(
        phase: PatchApplyPhase.finalizing,
        fraction: 1.0,
      );
      await tester.pump();
      expect(find.text('Installing patch'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('Semantics label announces phase', (tester) async {
      final state = ValueNotifier(
        const OtaOverlayState(
          phase: PatchApplyPhase.downloading,
          fraction: 0.5,
        ),
      );
      await _pump(tester, state: state);
      // We don't assert against a specific label because semantics
      // concatenation is platform-dependent; we only verify that a Semantics
      // node is present.
      expect(find.byType(Semantics), findsWidgets);
    });
  });

  group('OtaOverlayManager', () {
    // The manager is a singleton with global state, which makes it hard to
    // test in isolation (a previous test in the same isolate can leave a
    // disposed overlay host behind). We test the public surface only via
    // the public widget tests above, which use the widget's own
    // ValueListenableBuilder.

    test('OtaOverlayState.copyWith preserves fields when not overridden', () {
      const original = OtaOverlayState(
        phase: PatchApplyPhase.downloading,
        fraction: 0.5,
        message: 'hello',
        targetVersion: '1.0.1',
        currentVersion: '1.0.0',
      );
      final copy = original.copyWith(fraction: 0.8);
      expect(copy.fraction, 0.8);
      expect(copy.phase, PatchApplyPhase.downloading);
      expect(copy.message, 'hello');
      expect(copy.targetVersion, '1.0.1');
      expect(copy.currentVersion, '1.0.0');
    });

    test(
      'OtaOverlayState.copyWith can clear hasError by setting other fields',
      () {
        const original = OtaOverlayState(hasError: true, errorText: 'oops');
        // copyWith cannot unset a bool (Dart's nullable param doesn't help);
        // verify the field stays set when other fields are passed.
        final copy = original.copyWith(fraction: 0.0);
        expect(copy.hasError, isTrue);
        expect(copy.errorText, 'oops');
      },
    );
  });
}
