# Crash protection

**English** | [简体中文](crash-protection-zh.md)

How `flutter_ota_kit` automatically rolls back when a patch goes wrong,
and how it prevents the same bad patch from being loaded again.

If a patch causes a boot failure or a serious Dart-level error during
the early UI, the SDK rolls back to the APK's built-in version on the
next cold start and adds the offending patch to a local blacklist.

**The whole decision happens on the client** without depending on the
server. You should still pair it with staged rollouts, crash monitoring,
and a server-side kill switch for production — see
[Monitoring recommendations](#monitoring-recommendations).

For the broader patch flow, see [Architecture](architecture.md). For
the public API surface, see [API Reference → Boot diagnostics](api-reference.md#boot-diagnostics).

---

## Default behavior

The default policy is **fail-fast**:

> Once a patch is confirmed to fail even once after loading, it is dropped and added to the local blacklist.

On the next cold start the app falls back to the built-in version of
the APK. The SDK does not retry the same patch, to avoid spreading the
failure across more users.

```dart
await FlutterPatcher.init(
  maxCrashCount: 1,                                // recommended
  verifyAfter: const Duration(seconds: 5),         // post-first-frame watch window
);
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `maxCrashCount` | `1` | Number of consecutive failures before the patch is tripped and blacklisted. **Recommended production value.** |
| `verifyAfter` | `5 seconds` | Window during which the post-first-frame Dart error hooks keep watching. |

You can raise `maxCrashCount`, but it's rarely a good idea in
production. Once a patch is known to fail boot, retrying typically
just amplifies the impact.

---

## What counts as a failure

The SDK tries to distinguish "the patch broke us" from "the user / system
caused a normal exit".

### Counts toward the circuit breaker

- **App crashes** — `REASON_CRASH`
- **Native crashes** — `REASON_CRASH_NATIVE` (a `.so` load failure, JNI
  crash, or native plugin crash)
- **ANRs** — `REASON_ANR`
- **Initialization failures** — `REASON_INITIALIZATION_FAILURE` (e.g. JNI
  / loader errors before any Dart code runs)
- **Serious Dart errors during early launch / first frame**
- **Dart errors caught by the framework that nonetheless leave the first
  frame blank or unusable**

### Does NOT count

- The user swiping the app away from recents
- The user pressing Home to background the app
- The user force-stopping the app from system settings
- The system reclaiming the process under memory pressure
- Non-first-frame exceptions during normal business flow

The signal quality varies across Android versions; see
[Android version differences](#android-version-differences).

---

## Boot success window

Whether a patch is "stable" is decided across two phases. The first
phase is a hard requirement; the second is a graceful extension.

```
          ┌────────────────────────────────────────────────────────┐
   time   │                                                        │
    ↓     ▼                                                        │
  ────────┼──── markBooting() ──── first frame ─── verifyAfter ──┴─ patch "stable"
          │     [set patch_loading=true]   [set false]    [tear down hooks]
          │
   on failure inside the verifyAfter window  →  queue rollback for next boot
   on exit before first frame (API 30+)      →  ApplicationExitInfo
```

### 1. First-frame render (hard requirement)

After the patch loads, if the app reaches the first frame, the boot
is treated as **initially successful** and any in-flight
circuit-breaker state is cleared.

This avoids misclassifying as patch failures:

- Pressing Home right after the first frame
- Swiping the app from recents shortly after launch
- The system reclaiming the process in the background

### 2. `verifyAfter` watch window (graceful extension)

After the first frame, the Dart error hooks keep watching for
`verifyAfter` (default 5 seconds). The window catches serious
Dart-level failures during the first-screen experience:

- Tapping immediately on the first screen triggers an exception
- The framework caught an exception but the page rendered blank
- Critical first-screen logic threw and left the app unusable

`verifyAfter` only accumulates while the app is **foregrounded**. After
the window closes, business-level errors no longer feed back into the
circuit breaker.

---

## Android version differences

Android's signal for "why did the process exit" varies by version.

### Android 11+ (API 30+)

Android 11+ supports `ActivityManager.getHistoricalProcessExitReasons`,
which lets the SDK distinguish:

- Real Dart / framework crashes (`REASON_CRASH`)
- Native crashes (`REASON_CRASH_NATIVE`)
- ANRs (`REASON_ANR`)
- Initialization failures (`REASON_INITIALIZATION_FAILURE`) — e.g. JNI /
  loader errors before any Dart code runs
- **User-initiated stops, low-memory reclaims, and external SIGKILLs are
  NOT counted**

Looking up the previous session is keyed by the **pid we recorded
on `attachBaseContext`**, which the SDK deliberately retains across
successful boots. That's what lets the next cold start still
attribute a *post-first-frame* native crash to the patch — without
it we'd only catch failures before the patch-loading flag was
cleared.

### Android 10 and below

Android 10 and below do not have `ApplicationExitInfo`. The SDK falls
back to a `patch_loading` flag persisted in SharedPreferences to
determine "did the previous launch die mid-patch-load".

This means:

- Boot failures *before* the first frame are detected (the flag is
  still `true`).
- **Known blind spot**: native crashes or ANRs that happen *after* the
  first frame are not attributable — the flag was already cleared by
  `markBootSuccess`. The Dart-error hooks still cover this window for
  Dart-level failures.
- Dart errors inside the `verifyAfter` window are still caught by the
  error hooks.

If your traffic on API < 30 is significant, plug in your existing
crash-monitoring system and stop delivering the bad patch from the
server side as soon as you see it.

### `ApplicationExitInfo` reason mapping (API 30+)

| `reason` constant | Counts as crash? |
|------------------|------------------|
| `REASON_CRASH` | ✅ Yes |
| `REASON_CRASH_NATIVE` | ✅ Yes |
| `REASON_ANR` | ✅ Yes |
| `REASON_INITIALIZATION_FAILURE` | ✅ Yes |
| `REASON_USER_REQUESTED` | ❌ No |
| `REASON_USER_STOPPED` | ❌ No |
| `REASON_LOW_MEMORY` | ❌ No |
| `REASON_OTHER` | ❌ No |
| `REASON_SIGNALED` (e.g. SIGKILL) | ❌ No |

---

## Blacklist

A patch that triggers an automatic rollback is recorded in the local
blacklist with the composite key `(version, md5)`.

What this means:

- The same patch will be rejected if delivered again
- If you reuse the same `version` for a new fix, a different MD5 is
  still allowed
- Manual `rollback()` does **not** add the patch to the blacklist
- The blacklist persists across APK upgrades, in case the server
  forgets to delist a known-bad patch

> **Missing MD5**: when the server does not ship `md5`
> (`PatchInfo.md5 == ''`), the pre-download blacklist check degrades to
> a version-only match — any blacklist entry sharing this `version` is
> enough to reject the patch. On the native side the entry's `md5` field
> is filled with the actual md5 computed after download, which keeps it
> useful for triage.

The blacklist uses FIFO eviction with a cap of 50 entries; older
records are dropped beyond that.

### Inspect the blacklist

```dart
final entries = await FlutterPatcher.blacklist;

for (final e in entries) {
  print('${e.version} / ${e.md5} / ${e.reason} / ${e.blacklistedAt}');
}
```

### Clear the blacklist

```dart
await FlutterPatcher.clearBlacklist();
```

`clearBlacklist()` is for debugging — don't expose it to ordinary users
in production. Blacklist entries are also dropped automatically when
FIFO evicts them (after 50 entries).

---

## Configuration

Crash-protection settings live in `FlutterPatcher.init()`:

```dart
await FlutterPatcher.init(
  maxCrashCount: 1,
  verifyAfter: const Duration(seconds: 5),
);
```

### `maxCrashCount`

Number of consecutive failures before the patch is tripped and
blacklisted.

**Default: `1`.** This is the recommended production value. Higher
values increase the chance of a bad patch reaching more users before
it's blocked.

### `verifyAfter`

The window during which the post-first-frame Dart error hooks keep
watching.

**Default: 5 seconds.** Raise it if your first-screen initialization
or interactions are slow; lower it if you only care about the very
early window.

---

## Monitoring recommendations

Client-side crash protection is the last line of defense. In
production, also monitor and act server-side.

### 1. Report boot diagnostics

After every cold start, read `lastBootDiagnostic` and report any
non-healthy state to your analytics backend. The API and field shapes
are documented in [API Reference → Boot diagnostics](api-reference.md#boot-diagnostics).

Watch these states in particular:

| Status | Meaning | Action |
|--------|---------|--------|
| `droppedCircuitBreaker` | Patch tripped the circuit breaker | **Strong alert; stop delivering** |
| `droppedSignatureInvalid` | Signature verification failed | Alert; investigate the source |
| `droppedMd5Mismatch` | Local file MD5 does not match the recorded MD5 | Report and investigate |
| `droppedMetaCorrupted` | Patch metadata is corrupt | Report and investigate |
| `hookInstallFailed` | FlutterLoader hook failed to install | Check Flutter version compatibility |

```dart
// In your app's boot path:
final diag = await FlutterPatcher.lastBootDiagnostic;
if (diag != null && diag.outcome != BootOutcome.success) {
  await myAnalytics.track('boot_outcome', {
    'outcome': diag.outcome.name,
    'version': diag.version,
    'timestamp': diag.timestamp.toIso8601String(),
  });
}
```

### 2. Server-side automatic delisting

If the same patch produces multiple `droppedCircuitBreaker` events
in a short window, the server should **automatically stop returning
that patch**.

Useful dimensions to consider:

- Patch version
- MD5
- Target APK `versionCode`
- ABI
- Device Android version
- App version
- Time window

### 3. Staged rollout

A typical ramp:

```
1% → 5% → 20% → 50% → 100%
```

Watch crash rate, boot-failure rate, and the key business metrics at
each stage. If anything looks wrong, **stop delivering the patch
immediately** — the in-flight users will be protected by the next
cold start, and the at-risk users will be protected by the blacklist.

### 4. Emergency rollback

An emergency rollback only needs the check-update endpoint to stop
returning the bad version. Devices that already triggered crash
protection have rolled back locally and will refuse to load the same
problematic patch again.

```bash
# Roll production back to the previous stable bundle
flutter-ota rollback -b supabase -c production --bundle-id 01a059a5-...

# Or just stop returning the bad bundle entirely
flutter-ota bundle disable -b supabase --id 01a059a6-...
```

---

## Debugging

### Logcat

Crash-protection logs use this tag:

```bash
adb logcat | grep FlutterPatcher/Guard
```

You should see entries like:

```
D/FlutterPatcher/Guard: markBooting() pid=12345
D/FlutterPatcher/Guard: first frame rendered, markBootSuccess()
D/FlutterPatcher/Guard: Dart error in verifyAfter window, count=1
D/FlutterPatcher/Guard: next boot will rollback
D/FlutterPatcher/Guard: ApplicationExitInfo REASON_CRASH for pid 12345
D/FlutterPatcher/Guard: circuit breaker tripped, blacklisting patch
```

### Diagnostic card

`example/lib/diag_card.dart` renders the diagnostic fields as a visual
card. While debugging on a real device you can directly see:

- Current patch state (installed / not installed / blacklisted)
- The most recent boot diagnostic
- All blacklist entries
- The reason for the most recent rollback

Tap any field to see the raw value; long-press to copy.

### Forcing a bad-patch test locally

To verify the rollback path works on a real device:

```bash
# 1. Apply a known-good patch first (so the install path is exercised)
flutter-ota build --name 1.0.1 --platform android --arch x86_64
flutter-ota deploy -b supabase -s dist -c production -p android \
  --target-app-version 1.0.0 --force

# 2. Now deliberately break a Dart file and build again
echo "void main() => throw 'intentional crash';" > lib/main.dart
flutter-ota build --name 1.0.2
flutter-ota deploy -b supabase -s dist -c production -p android \
  --target-app-version 1.0.0 --force

# 3. Open the app → crash → close → reopen → 1.0.1 is back
```

This is the only way to truly verify the rollback. Unit tests can't
exercise the native boot hook.

---

## Implementation details (for contributors and the curious)

This section is for people modifying the crash-protection logic or
debugging edge cases. The first half of the doc is what you need to
*use* the system.

### Circuit-breaker timeline

The state machine lives in
`android/src/main/kotlin/com/flutter_ota_kit/flutter_ota_kit/CrashGuard.kt`.
Keys are SharedPreferences-backed: `KEY_PATCH_LOADING`, `KEY_CRASH_COUNT`,
`KEY_LAST_BOOTING_PID`.

| When | What happens |
|------|--------------|
| `Application.attachBaseContext` | `markBooting()`: write `patch_loading=true` and the current pid (synchronous `commit()`). |
| Dart `FlutterPatcher.init()` | Defensive fallback write of `patch_loading=true` if the native write failed. |
| First frame rendered | `markBootSuccess()`: clear `patch_loading` and `crash_count`. **Keep** `KEY_LAST_BOOTING_PID` so the next cold start can still query ExitInfo for this pid. Start the `verifyAfter` timer. |
| Foreground time accumulates `verifyAfter` | Tear down the Dart-error-hook watch window. |
| Dart error hook fires inside the window | Count one failure and queue a rollback on the next cold start. |
| Next cold start `shouldLoadPatch` | On API 30+ with a known pid, query `getHistoricalProcessExitReasons` for the precise exit reason. Otherwise fall back to `patch_loading`. |
| `crash_count >= maxCrashCount` | Delete the patch directory, add to the blacklist, fall back to the APK's built-in version. |

### Dart-side blank-screen safety net

A bad patch doesn't always crash the process. A Dart-level `throw`
caught by the framework can leave the process alive but the screen
blank or unusable.

To handle that, `init()` installs **Flutter-level** error hooks during
the `verifyAfter` window:

- `PlatformDispatcher.instance.onError`
- `FlutterError.onError`

Either firing inside the window counts as one patch failure and
queues a rollback on disk.

> The SDK does **not** install Android's `Thread.UncaughtExceptionHandler`.
> Native (JNI / `.so`) crashes are caught indirectly on the **next**
> cold start via `ApplicationExitInfo` (API 30+) or the `patch_loading`
> fallback (API < 30). Recovery is always cross-process; the current
> process has already loaded the patched `.so` and cannot revert without
> a restart.

After the window closes, both hooks still forward transparently to
any prior handler but stop reporting circuit-breaker events to the
native side.

### Why `KEY_LAST_BOOTING_PID` survives boot success

The naive design would clear all state after a successful boot. We
deliberately **keep** the pid of the last successful boot so the next
cold start can still query `getHistoricalProcessExitReasons` for that
pid. Without this retention, a native crash that happens 2 seconds
after first frame would be invisible to the next boot — the pid would
be gone, and the query would return empty.

The cost is ~8 bytes of SharedPreferences storage. The benefit is
accurate attribution of post-first-frame native crashes on Android 11+.

---

## See also

- [API Reference](api-reference.md) — `rollback()`, `blacklist`, and boot diagnostics
- [Production Playbook](production-playbook.md) — emergency rollback and monitoring
- [Configuration](configuration.md) — signing and verification options
- [Architecture](architecture.md) — full system design
