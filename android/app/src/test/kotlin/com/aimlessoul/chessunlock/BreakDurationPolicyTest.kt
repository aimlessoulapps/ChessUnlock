package com.aimlessoul.chessunlock

import android.app.Application
import android.content.Context
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [31, 35], application = Application::class, manifest = Config.NONE)
class BreakDurationPolicyTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private fun save(deadline: Long, premium: Boolean = false) {
        PrefBridge.saveWatcherState(context, emptySet(), false, false, deadline,
            premium, if (premium) Long.MAX_VALUE else 0L, false, "", 0, 1)
    }
    @Test fun freeGrantsStopAtThirtyMinutes() {
        for (minutes in listOf(5, 10, 15, 30)) {
            val deadline = System.currentTimeMillis() + minutes * 60_000L
            save(deadline)
            assertEquals(deadline, PrefBridge.getUnlockUntilMs(context))
        }
        assertThrows(IllegalArgumentException::class.java) {
            save(System.currentTimeMillis() + 45 * 60_000L)
        }
    }
    @Test fun existingLongDeadlineSurvivesFreeReconciliation() {
        val legacyDeadline = System.currentTimeMillis() + 45 * 60_000L
        save(legacyDeadline, premium = true)
        save(legacyDeadline, premium = false)
        assertEquals(legacyDeadline, PrefBridge.getUnlockUntilMs(context))
        assertThrows(IllegalArgumentException::class.java) { save(legacyDeadline + 1) }
    }
    @Test fun premiumRetainsLongerGrants() {
        for (minutes in listOf(45, 60, 120, 180)) {
            val deadline = System.currentTimeMillis() + minutes * 60_000L
            save(deadline, premium = true)
            assertEquals(deadline, PrefBridge.getUnlockUntilMs(context))
        }
    }
}
