// Widget tests for the structured terminal forced-update overlay.

import 'package:flutter/material.dart';
import 'package:flutter_ota_kit/flutter_ota_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// True if any rendered `Text` or `RichText` in the tree contains [needle].
/// `find.textContaining` does not traverse `RichText` spans, so meta rows and
/// log lines (which are `RichText`) need this.
bool _hasText(WidgetTester tester, String needle) {
  for (final w in tester.allWidgets) {
    if (w is Text && (w.data?.contains(needle) ?? false)) return true;
    if (w is RichText) {
      final span = w.text;
      if (span is TextSpan && span.toPlainText().contains(needle)) return true;
    }
  }
  return false;
}


Future<void> _pump(
  WidgetTester tester, {
  required ValueNotifier<OtaOverlayState> state,
  VoidCallback? onRetry,
}) async {
  // A tall canvas so the scrollable body lays out without overflow.
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: OtaProgressOverlay(state: state, onRetry: onRetry),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 80));
}

void main() {
  group('OtaProgressOverlay (terminal)', () {
    testWidgets('renders the section skeleton', (tester) async {
      final state = ValueNotifier(const OtaOverlayState());
      await _pump(tester, state: state);

      expect(find.text('META'), findsOneWidget);
      expect(find.text('STEPS'), findsOneWidget);
      expect(find.text('PROGRESS'), findsOneWidget);
      expect(find.text('LOG'), findsOneWidget);
      // Title bar text.
      expect(find.text('flutter-ota · forced update'), findsOneWidget);
      // Running status pill (no error).
      expect(find.text('RUNNING'), findsOneWidget);
      expect(find.text('FAILED'), findsNothing);
    });

    testWidgets('shows meta rows: channel, version, bundle, size',
        (tester) async {
      final state = ValueNotifier(
        const OtaOverlayState(
          phase: PatchApplyPhase.downloading,
          fraction: 0.62,
          currentVersion: '1.4.0',
          targetVersion: '1.4.1',
          channel: 'production',
          bundleHash: 'a1b2c3d4',
          totalBytes: 8 * 1048576, // 8.0 MB
          message: 'New onboarding flow',
        ),
      );
      await _pump(tester, state: state);

      expect(_hasText(tester, 'production'), isTrue);
      expect(_hasText(tester, '1.4.0'), isTrue); // version + steps
      expect(_hasText(tester, 'a1b2c3d4'), isTrue);
      expect(_hasText(tester, '8.0 MB'), isTrue);
      // Footer shows the deploy message when running.
      expect(find.text('New onboarding flow'), findsOneWidget);
    });

    testWidgets('active step shows the running percentage', (tester) async {
      final state = ValueNotifier(
        const OtaOverlayState(
          phase: PatchApplyPhase.downloading,
          fraction: 0.62,
          activeStep: 1,
        ),
      );
      await _pump(tester, state: state);

      // The active step's status chip + the progress bar suffix both read 62%.
      expect(find.text('62%'), findsWidgets);
      // Step 1 label present.
      expect(find.text('Download bundle'), findsOneWidget);
      // Earlier step marked done.
      expect(find.text('done'), findsOneWidget);
      // Later steps still waiting.
      expect(find.text('wait'), findsWidgets);
    });

    testWidgets('error state flips pill, marks failed step, shows hint',
        (tester) async {
      final state = ValueNotifier(
        const OtaOverlayState(
          hasError: true,
          errorText: 'MD5 mismatch',
          errorHint: 'Close the app and reopen to retry.',
          currentVersion: '1.4.0',
          targetVersion: '1.4.1',
          activeStep: 2,
          fraction: 0.88,
        ),
      );
      await _pump(tester, state: state);

      expect(find.text('FAILED'), findsOneWidget);
      expect(find.text('RUNNING'), findsNothing);
      // Failed step status chip.
      expect(find.text('error'), findsOneWidget);
      // Progress "phase" stat halts.
      expect(find.text('halted'), findsOneWidget);
      // Footer hint.
      expect(find.text('Close the app and reopen to retry.'), findsOneWidget);
    });

    testWidgets('retry button appears with onRetry and fires', (tester) async {
      var tapped = false;
      final state = ValueNotifier(
        const OtaOverlayState(
          hasError: true,
          errorText: 'io error',
          activeStep: 1,
        ),
      );
      await _pump(tester, state: state, onRetry: () => tapped = true);

      final retry = find.text('[ retry ]');
      expect(retry, findsOneWidget);
      await tester.tap(retry);
      expect(tapped, isTrue);
    });

    testWidgets('no retry button when onRetry is null and canRetry is false',
        (tester) async {
      final state = ValueNotifier(
        const OtaOverlayState(hasError: true, errorText: 'io error'),
      );
      await _pump(tester, state: state);
      expect(find.text('[ retry ]'), findsNothing);
    });

    testWidgets('log lines render (tag + body split)', (tester) async {
      final state = ValueNotifier(
        const OtaOverlayState(
          phase: PatchApplyPhase.verifying,
          activeStep: 2,
          logs: [
            LogLine('green', 'download complete ✓'),
            LogLine('cyan', 'verify   md5 match ✓'),
          ],
        ),
      );
      await _pump(tester, state: state);

      // Body of the split "verify   md5 match ✓" line (rendered as RichText).
      expect(_hasText(tester, 'md5 match'), isTrue);
    });

    testWidgets('restarting state completes every step + shows restarting phase',
        (tester) async {
      final state = ValueNotifier(
        const OtaOverlayState(
          phase: PatchApplyPhase.finalizing,
          restarting: true,
          fraction: 1.0,
          currentVersion: '1.4.0',
          targetVersion: '1.4.1',
          activeStep: 5,
        ),
      );
      await _pump(tester, state: state);

      // No step is left "working"/"wait" — all are done.
      expect(find.text('wait'), findsNothing);
      expect(find.text('working'), findsNothing);
      // Phase stat reads "restarting".
      expect(find.text('restarting'), findsOneWidget);
    });

    testWidgets('non-download active phase shows a working spinner, not a %',
        (tester) async {
      final state = ValueNotifier(
        const OtaOverlayState(
          phase: PatchApplyPhase.verifying,
          activeStep: 2, // Verify step active, no fraction
        ),
      );
      await _pump(tester, state: state);

      // The active verify step must not display a frozen "0%".
      expect(find.text('0%'), findsNothing);
    });

    testWidgets('out-of-range activeStep never throws / clamps into the list',
        (tester) async {
      final state = ValueNotifier(
        const OtaOverlayState(
          phase: PatchApplyPhase.finalizing,
          activeStep: 99, // absurd index from a bad native event
        ),
      );
      await _pump(tester, state: state);
      // Renders without a range error; the last step is the active one.
      expect(find.text('Finalize & restart'), findsOneWidget);
    });
  });

  group('OtaOverlayState.copyWith', () {
    test('preserves fields when not overridden', () {
      const original = OtaOverlayState(
        phase: PatchApplyPhase.downloading,
        fraction: 0.5,
        message: 'hello',
        targetVersion: '1.0.1',
        currentVersion: '1.0.0',
        totalBytes: 100,
        bytesReceived: 50,
        bytesPerSec: 10,
      );
      final copy = original.copyWith(fraction: 0.8);
      expect(copy.fraction, 0.8);
      expect(copy.phase, PatchApplyPhase.downloading);
      expect(copy.message, 'hello');
      expect(copy.targetVersion, '1.0.1');
      expect(copy.currentVersion, '1.0.0');
      expect(copy.totalBytes, 100);
      expect(copy.bytesReceived, 50);
      expect(copy.bytesPerSec, 10);
    });

    test('sets hasError explicitly, leaves it otherwise', () {
      const original = OtaOverlayState(hasError: true, errorText: 'oops');
      final unchanged = original.copyWith(fraction: 0.0);
      expect(unchanged.hasError, isTrue);
      expect(unchanged.errorText, 'oops');

      final cleared = original.copyWith(hasError: false);
      expect(cleared.hasError, isFalse);
    });
  });
}
