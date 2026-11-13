package com.aimlessoul.chessunlock

import android.app.Application
import android.app.ForegroundServiceStartNotAllowedException
import android.app.NotificationManager
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.ResultReceiver
import android.os.Bundle
import org.junit.Before
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
// Exercise the watcher in isolation without initializing third-party SDK receivers.
@Config(sdk = [31, 35], application = Application::class, manifest = Config.NONE)
class WatcherLifecycleTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()

    @Before fun allowRecoveryNotifications() {
        shadowOf(RuntimeEnvironment.getApplication())
            .grantPermissions("android.permission.POST_NOTIFICATIONS")
    }

    @Test fun existingForegroundDetectionRegressions() {
        main() // Existing pure Kotlin foreground transition/recovery scenarios.
    }

    @Test fun promotionRefusalStopsServiceAndDoesNotBecomeSticky() {
        for (error in listOf(
            ForegroundServiceStartNotAllowedException("background start denied"),
            SecurityException("permission revoked"),
            IllegalArgumentException("invalid foreground service type")
        )) {
            val controller = Robolectric.buildService(ForegroundAppWatcherService::class.java)
            val service = controller.get()
            shadowOf(service).setThrowInStartForeground(error)
            controller.create()
            assertFalse(ForegroundAppWatcherService.isRunning)
            assertTrue(shadowOf(service).isStoppedBySelf)
            var acknowledged: Int? = null
            val receiver = object : ResultReceiver(Handler(Looper.getMainLooper())) {
                override fun onReceiveResult(code: Int, data: Bundle?) { acknowledged = code }
            }
            assertEquals(Service.START_NOT_STICKY, service.onStartCommand(
                Intent().putExtra("watcherStartResult", receiver), 0, 1))
            shadowOf(Looper.getMainLooper()).idle()
            assertEquals(0, acknowledged)
            // Also protects null-intent system restart failures.
            assertEquals(Service.START_NOT_STICKY, service.onStartCommand(null, 0, 2))
            controller.destroy()
        }
    }

    @Test fun successfulPromotionRunsAndPreservesStickyRestart() {
        val controller = Robolectric.buildService(ForegroundAppWatcherService::class.java).create()
        val service = controller.get()
        assertTrue(ForegroundAppWatcherService.isRunning)
        assertNotNull(shadowOf(service).lastForegroundNotification)
        assertEquals(Service.START_STICKY, service.onStartCommand(null, 0, 1))
        ForegroundAppWatcherService.requestHideOverlay()
        assertTrue(ForegroundAppWatcherService.isRunning)
        ForegroundAppWatcherService.stop(context)
        assertFalse(ForegroundAppWatcherService.isRunning)
        controller.destroy()
        assertFalse(ForegroundAppWatcherService.isRunning)
    }

    @Test fun hideDoesNotCreateAService() {
        ForegroundAppWatcherService.requestHideOverlay()
        assertNull(shadowOf(RuntimeEnvironment.getApplication()).nextStartedService)
        assertFalse(ForegroundAppWatcherService.isRunning)
    }

    @Test fun launchRefusalIsReportedWithoutThrowingOrRetrying() {
        val denied = object : ContextWrapper(context) {
            override fun startForegroundService(intent: Intent): ComponentName? {
                throw ForegroundServiceStartNotAllowedException("not exempt")
            }
        }
        assertFalse(ForegroundAppWatcherService.start(denied))
        assertFalse(ForegroundAppWatcherService.isRunning)
        assertNull(shadowOf(RuntimeEnvironment.getApplication()).nextStartedService)
        val notifications = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        assertNotNull(shadowOf(notifications).getNotification(14002))
    }

    @Test fun onlyExemptBroadcastsStartMonitoring() {
        PrefBridge.saveWatcherState(context, setOf("locked.app"), true, false,
            0L, false, 0L, false, "", 0, 1)
        val receiver = BootReceiver()
        val app = shadowOf(RuntimeEnvironment.getApplication())
        for (action in listOf(Intent.ACTION_USER_UNLOCKED,
            "com.aimlessoul.chessunlock.action.RETRY_START_WATCHER", "unknown")) {
            receiver.onReceive(context, Intent(action))
            assertNull(app.nextStartedService)
        }
        for (action in listOf(Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED)) {
            receiver.onReceive(context, Intent(action))
            assertEquals(ForegroundAppWatcherService::class.java.name,
                app.nextStartedService?.component?.className)
        }
    }
}
