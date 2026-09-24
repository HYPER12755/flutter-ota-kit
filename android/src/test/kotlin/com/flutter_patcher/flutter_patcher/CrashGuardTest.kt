package com.flutter_patcher.flutter_patcher

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Unit tests for the boot-window crash attribution rule that prevents a
 * healthy OTA patch from being reverted by an unrelated runtime crash/ANR
 * hours into a session.
 */
class CrashGuardTest {

    private val window = PatcherConfig.BOOT_CRASH_WINDOW_MS

    @Test
    fun crashWithinWindowIsChargedToPatch() {
        val bootAt = 1_000_000L
        // Crash 5s after boot — clearly a boot failure.
        assertTrue(CrashGuard.isWithinBootWindow(bootAt, bootAt + 5_000L))
    }

    @Test
    fun crashAtExactWindowEdgeIsCharged() {
        val bootAt = 1_000_000L
        assertTrue(CrashGuard.isWithinBootWindow(bootAt, bootAt + window))
    }

    @Test
    fun crashLongAfterBootIsNotChargedToPatch() {
        val bootAt = 1_000_000L
        // Crash 2 hours into a healthy session — must NOT revert the patch.
        val twoHours = 2 * 60 * 60 * 1000L
        assertFalse(CrashGuard.isWithinBootWindow(bootAt, bootAt + twoHours))
    }

    @Test
    fun crashJustPastWindowIsNotCharged() {
        val bootAt = 1_000_000L
        assertFalse(CrashGuard.isWithinBootWindow(bootAt, bootAt + window + 1L))
    }

    @Test
    fun unknownBootTimestampFallsBackToCharging() {
        // No boot timestamp recorded (legacy state / upgrade) → conservative,
        // preserve prior fail-fast behavior.
        assertTrue(CrashGuard.isWithinBootWindow(0L, 5_000_000L))
    }

    @Test
    fun unknownCrashTimestampFallsBackToCharging() {
        assertTrue(CrashGuard.isWithinBootWindow(1_000_000L, 0L))
    }

    @Test
    fun clockSkewNegativeElapsedTreatedAsInWindow() {
        // ExitInfo timestamp earlier than recorded boot (device clock change) →
        // treat as in-window rather than silently ignoring a genuine boot crash.
        assertTrue(CrashGuard.isWithinBootWindow(2_000_000L, 1_000_000L))
    }
}
