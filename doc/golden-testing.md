# Golden file testing

A guide to Flutter's pixel-perfect testing system, how `flutter_ota_kit` uses
it for the forced-update overlay, and how to add goldens to your own widgets.

## What is a golden file test?

A **golden file** is a PNG image committed to git that represents what a widget
should look like under specific conditions. A golden test is a widget test that
**rasterizes a widget tree to PNG bytes** and compares them against the
committed file. If the bytes differ, the test fails.

This catches visual regressions that no other test can:

- A `Color` accidentally changed from `0xFF5B8DEF` to `0xFF5B8EEF` → the visual test fails, even though no assertion-based test would notice.
- A new child `Text` widget added inside a card → the test fails because the card is now 4px taller.
- A `Theme.of(context)` change that accidentally picks up a wrong text style → the test catches the font shift.

The name "golden" comes from the traditional name for reference files in image
comparison testing — the file is the **golden truth**.

## How the pipeline works

The full path from code to PNG is:

```
┌────────────────────┐
│ testWidgets(        │
│   tester.           │
│   pumpWidget(       │  ← 1. Build a real Flutter widget tree
│     MyWidget(),     │
│   )                 │
│ )                   │
└────────┬───────────┘
         │
         ↓
┌────────────────────┐
│ TestWidgetsFlutter  │  ← 2. Run a Flutter binding that owns
│ Binding runs the    │     pumps, layout, paint, hit-tests.
│ tree off-screen     │
└────────┬───────────┘
         │
         ↓
┌────────────────────┐
│ matchesGoldenFile(   │  ← 3. Find a RepaintBoundary, call
│   'goldens/x.png'    │     `.toImage()` on its render object,
│ )                    │     encode as PNG, compare with file
└────────┬───────────┘
         │
         ↓
┌────────────────────┐
│ goldens/x.png on    │  ← 4. On `flutter test`: fail if bytes
│ disk, committed to  │     differ. On `--update-goldens`:
│ git                 │     overwrite with the new bytes.
└────────────────────┘
```

**No emulator, no real device, no human.** The whole pipeline runs in a Dart
process on your CI box.

## Why the project uses goldens

The forced-update overlay (`lib/src/ota_progress_overlay.dart`) is a
**safety-critical surface** — it appears when the user's app is being
hot-patched, blocking all interaction, with the explicit promise "this
will finish in N seconds." A regression that makes the card unreadable, the
spinner invisible, or the progress bar too small to see is worse than a
crash. Goldens guarantee the visual contract.

Other places in the project where goldens would help:

- The generated `setup.dart` files (`init` codegen output)
- The CLI's terminal UI tables (banners, boxes, progress spinners)
- The dark-theme variant of every public widget

## How the forced-update overlay uses goldens

The test file `test/overlay_golden_test.dart` produces **6 single-state
goldens** (one per visible state × 2 themes):

| Golden | What it captures |
|--------|------------------|
| `goldens/overlay/01_idle.png` | "Preparing update" before any phase starts |
| `goldens/overlay/02_downloading_start.png` | Downloading with version transition + 0% bar |
| `goldens/overlay/03_downloading_mid.png` | Downloading 50%, ring half-filled, 50% pill above bar |
| `goldens/overlay/04_verifying.png` | Verifying 85% with "Critical security fix" message |
| `goldens/overlay/05_error.png` | Error state with red-tinted block + retry hint |
| `goldens/overlay/06_dark.png` | Downloading 50% on ThemeData.dark for dark-mode parity |

There's also `test/overlay_compare_goldens.dart` which produces **4
side-by-side comparison goldens** (v1 on the left, v2 on the right) so
regressions across the v1→v2 redesign can be caught visually.

## Anatomy of a golden test

Here's the full pipeline, annotated. Source: `test/overlay_golden_test.dart`.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_ota_kit/flutter_ota_kit.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpOverlay(
  WidgetTester tester, {
  required ValueNotifier<OtaOverlayState> state,
  ThemeData? theme,
}) async {
  // 1. Fix the canvas size so the PNG is reproducible across machines.
  //    Without this, goldens are sensitive to the test runner's screen size
  //    and produce different bytes on different hosts.
  tester.view.physicalSize = const Size(720, 1480);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // 2. Build a real widget tree. The overlay is wrapped in Scaffold+MaterialApp
  //    so it inherits a real ColorScheme and TextTheme — the same context
  //    the overlay sees in production.
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        body: Stack(
          children: [
            const Center(
              child: Text('App screen behind overlay',
                  style: TextStyle(color: Colors.black45)),
            ),
            OtaProgressOverlay(state: state),
          ],
        ),
      ),
    ),
  );

  // 3. Let the spinner tick a frame. Without this, the first frame would
  //    capture glyph index 0 of the braille spinner — a 1-of-10 chance the
  //    golden happens to look right. Pumping once stabilizes the visual.
  await tester.pump(const Duration(milliseconds: 80));
}

void main() {
  testWidgets('downloading 50% (fraction known)', (tester) async {
    // 4. Construct the exact state we want to render. The overlay is
    //    data-driven — same code path renders every state.
    final state = ValueNotifier(const OtaOverlayState(
      phase: PatchApplyPhase.downloading,
      fraction: 0.50,
      currentVersion: '1.0.0',
      targetVersion: '1.0.1',
      message: 'New onboarding flow',
    ));

    // 5. Pump the widget tree, then assert the PNG matches the file.
    await _pumpOverlay(tester, state: state);
    await expectLater(
      find.byType(OtaProgressOverlay),
      matchesGoldenFile('goldens/overlay/03_downloading_mid.png'),
    );
  });
}
```

## Running golden tests

Three modes:

```bash
# 1. Compare against committed goldens. Fails if any PNG differs.
flutter test test/overlay_golden_test.dart

# 2. Regenerate the goldens from the current code. Use this when you
#    intentionally change the visual design and want to accept the new look.
flutter test test/overlay_golden_test.dart --update-goldens

# 3. Run all tests in the package (goldens + widget + unit).
flutter test
```

When you commit a golden, the **PNG bytes** are the truth. The diff
`git diff test/goldens/` will show pixel changes. Reviewers can open the
PNG to see the visual diff.

## The mechanics of `matchesGoldenFile`

When you write `matchesGoldenFile('goldens/overlay/03_downloading_mid.png')`:

1. The test framework finds the `RepaintBoundary` in the matched widget's render tree.
2. It calls `RenderRepaintBoundary.toImage(pixelRatio: 1.0)` which returns a `dart:ui.Image`.
3. The image is encoded to PNG bytes via `image.toByteData(format: ImageByteFormat.png)`.
4. If `--update-goldens` was passed, the bytes are written to the file. Otherwise:
   - If the file doesn't exist → test fails (`GoldenFileComparator` throws `MissingGoldenFileException`).
   - If the bytes differ → test fails with a diff (the framework writes the new bytes to a `.diff.png` next to the golden for inspection).
   - If the bytes match → test passes.

The default comparator is `flutterGoldensFileComparator` from
`package:flutter_test`. It does **exact byte comparison** — no fuzzy matching,
no perceptual diff. If even one pixel changes, the test fails.

This strictness is intentional: goldens are a contract, not a heuristic. If
the design legitimately changes, the developer regenerates the goldens
intentionally. Random drift is the enemy.

## The mechanism of `toImage` (the renderer)

The `toImage()` call on a `RenderRepaintBoundary` is what actually
rasterizes the widget tree. It works like this:

1. The renderer walks the render tree starting at the boundary.
2. For each `RenderBox`, it calls `paint(PaintingContext, Offset)`.
3. The `PaintingContext` records draw calls into an `PictureRecorder` (a `dart:ui.Picture`).
4. After the walk completes, `PictureRecorder.endRecording()` returns a `Picture`.
5. `Picture.toImage(width, height)` rasterizes the picture into a GPU-backed `dart:ui.Image`.
6. `Image.toByteData(format: ImageByteFormat.png)` encodes the image as PNG.

The renderer uses **Skia** (the engine that's already loaded in the test
process), so there's no separate rasterization pass. It's all the same code
that runs in production — just driven by a programmatic layout pass instead
of a vsync.

## Common gotchas

### 1. Font rendering differs across platforms

The braille spinner in the overlay uses `fontFamily: 'monospace'`. On Linux
test runners, `monospace` maps to DejaVu Sans Mono. On macOS, it maps to Menlo. The
glyphs render the same shape but at different metrics, so the PNG bytes
differ.

**Fix**: the test sets `tester.view.devicePixelRatio = 1.0` to normalize
scaling. For monospace text, this is usually enough. If you need
cross-platform stability, use `flutter test --platform=...` or commit a
per-platform golden set.

### 2. Timers and animations

The overlay's spinner uses `SingleTickerProviderStateMixin` which auto-cancels
in `dispose()`. If you replace it with `Timer.periodic` (as the **old v1
code** did), the timer keeps running after the widget tree is disposed and
the test fails with `A Timer is still pending`.

**Fix**: always use `SingleTickerProviderStateMixin` for repeating animations
in test-friendly widgets. Or use `Ticker` directly via the binding.

### 3. `RepaintBoundary` is required for `toImage`

`matchesGoldenFile` finds the **nearest enclosing `RepaintBoundary`** to the
matched widget. If your widget isn't inside a `RepaintBoundary`, the
`toImage` call captures the entire screen, not just your widget.

The `MaterialApp` you wrap your test in **does** add a `RepaintBoundary`
internally. But if you put your widget directly inside the test's root
without `MaterialApp`, you may get unexpected captures.

**Fix**: always wrap test widgets in `MaterialApp` (or `WidgetsApp`) so the
boundary is in place.

### 4. `setUp`/`addTearDown` ordering

```dart
testWidgets('foo', (tester) async {
  tester.view.physicalSize = const Size(720, 1480);
  addTearDown(tester.view.resetPhysicalSize);
  // ...rest of test
});
```

`addTearDown` is the only safe way to reset the view. Don't use
`tearDown` blocks — they run after `pumpWidget` has already done
disposal, and the assertions inside `matchesGoldenFile` may need the
modified view.

### 5. Static state leaks between tests

`OtaOverlayManager` is a singleton with global state. Testing it in
isolation is hard because a previous test in the same isolate can leave a
disposed overlay host behind. The `overlay_test.dart` solves this by
**not testing the manager directly** — only the public widget surface
(`OtaProgressOverlay`), which is composable and stateless.

If you must test a singleton, the `setUp` callback can reset it explicitly
by calling its public `dispose()` / `reset()` method.

### 6. Pixel-perfect dependencies on text rendering

The overlay's percentage pill uses `fontFamily: 'monospace'` and a precise
`fontSize: 14`. Different Flutter versions ship different default
monospace fonts. A `flutter upgrade` may break goldens even when the
overlay code didn't change.

**Mitigation**: either accept that goldens need regenerating after Flutter
upgrades, or use a custom test font (`goldenFileComparator` with
`withTextScale: 1.0` and `customFontFamily: 'Ahem'`).

## Adding goldens to your own widget

1. **Write a widget test that pumps your widget inside `MaterialApp`**.

   ```dart
   testWidgets('MyWidget — default state', (tester) async {
     await tester.pumpWidget(
       const MaterialApp(home: Scaffold(body: MyWidget())),
     );
     await expectLater(
       find.byType(MyWidget),
       matchesGoldenFile('goldens/my_widget.png'),
     );
   });
   ```

2. **Run with `--update-goldens` to generate the initial file**:

   ```bash
   flutter test test/my_widget_test.dart --update-goldens
   ```

3. **Open the PNG** in a viewer and verify it looks right. This is the
   one step that requires a human.

4. **Commit the PNG** to git:

   ```bash
   git add test/goldens/my_widget.png
   git commit -m "Add golden for MyWidget default state"
   ```

5. **Add tests for every state** you care about. Each state should be its
   own test with its own PNG:

   ```dart
   testWidgets('MyWidget — error state', (tester) async { ... });
   testWidgets('MyWidget — loading state', (tester) async { ... });
   testWidgets('MyWidget — dark theme', (tester) async { ... });
   ```

6. **Add a CI step** that runs `flutter test` (without `--update-goldens`)
   so PRs that change a PNG fail the build.

## File layout convention

The project follows this layout:

```
test/
  goldens/
    overlay/                 # Single-state goldens for OtaProgressOverlay
      01_idle.png
      02_downloading_start.png
      ...
    compare/                 # Side-by-side v1 vs v2
      01_downloading_0.png
      ...
  overlay_test.dart          # Widget tests (no goldens)
  overlay_golden_test.dart   # Single-state goldens
  overlay_compare_goldens.dart  # Comparison goldens (v1 vs v2)
```

The `goldens/` directory is **always at the package root** (or under a
`test/goldens/` subdirectory). The path is relative to the `flutter test`
working directory, which is the package root by default.

## When NOT to use goldens

Goldens are expensive:

- Each golden PNG is 5-50KB. A test suite with 100 goldens adds 1-5MB of git history.
- `toImage` is slow — typically 50-200ms per PNG on a CI machine.
- Strict byte comparison means **any** pixel change fails the test, including
  font rendering variations across platforms.

Use goldens for:

- UI surfaces that are visible to end users (the overlay, error screens)
- Components that are designed once and rarely change
- Visual contracts that you want to enforce across PRs

Don't use goldens for:

- **Layout tests** — use `expect(find.byType(...), findsOneWidget)` instead
- **Interaction tests** — use `tester.tap()` and verify state changes
- **Performance tests** — use the Flutter DevTools timeline
- **Frequently-changing UI** — if the design is in flux, goldens become a
  maintenance burden

For the forced-update overlay, goldens are the right tool: the UI rarely
changes, the design is well-defined, and the consequences of a visual
regression are severe (the user can't read the error message).

## CI integration

The project's CI runs `flutter test` on every PR. Goldens live in the
repo, so a fresh CI checkout has the reference PNGs. The CI doesn't
have a separate "update goldens" step — that requires a human in the
loop. A PR that changes a golden fails the test, the reviewer looks at
the diff, and either:
- The diff is correct (intentional redesign) → reviewer asks the author
  to regenerate and recommit the goldens.
- The diff is unintended → reviewer asks the author to fix the regression.

This keeps the goldens as a true contract: humans see the visual diff
before approving a PNG change.

## What goldens do and don't catch

| Concern | Caught? |
|---------|--------|
| Color value changed accidentally | ✅ |
| Text style changed accidentally | ✅ |
| Layout size changed | ✅ |
| New widget added to the tree | ✅ |
| Animation runs on a different frame | ✅ (with `--update-goldens` regenerating) |
| RTL vs LTR differences | ❌ (separate goldens needed) |
| Dynamic data variations | ❌ (only what you pump is captured) |
| User interaction bugs | ❌ (use widget tests) |
| Async timing bugs | ❌ (use integration tests) |
| Platform-specific rendering | ❌ (need per-platform goldens) |

## Reference: the `_V1Overlay` in `test/overlay_compare_goldens.dart`

To compare v1 against v2, the test re-implements the v1 widget inline. This
is intentional — it gives the test file a self-contained, executable
record of what the old design looked like, so future readers can see the
diff at a glance.

The `_V1Overlay` class is **not exported** and is **not used in
production**. It's a 200-line fixture that exists only to render the old
design for the comparison golden. If you find yourself wanting to use
it in a real test, that's a sign you should regenerate the v2 goldens
instead.
