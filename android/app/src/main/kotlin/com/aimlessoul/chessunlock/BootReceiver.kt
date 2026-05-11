package com.aimlessoul.chessunlock

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "ChessUnlockBoot"
        private const val ACTION_RETRY_START =
            "com.aimlessoul.chessunlock.action.RETRY_START_WATCHER"
        private const val EXTRA_RETRY_COUNT = "retryCount"
        private const val MAX_RETRY_COUNT = 3
        private const val RETRY_DELAY_MS = 15_000L
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return

        // Only respond to the actions we declare in the manifest.
        val allowed = action == Intent.ACTION_LOCKED_BOOT_COMPLETED ||
                action == Intent.ACTION_BOOT_COMPLETED ||
                action == Intent.ACTION_USER_UNLOCKED ||
                action == Intent.ACTION_MY_PACKAGE_REPLACED ||
                action == ACTION_RETRY_START

        if (!allowed) return

        if (!PrefBridge.shouldRunWatcher(context)) return

        val started = try {
            // Start the watcher so overlay works immediately after reboot.
            ForegroundAppWatcherService.start(context.applicationContext)
            true
        } catch (t: Throwable) {
            // Avoid crashing boot flow.
            Log.w(TAG, "Unable to restart watcher after $action", t)
            false
        }

        val retryCount = intent.getIntExtra(EXTRA_RETRY_COUNT, 0)
        if (action != ACTION_RETRY_START || (!started && retryCount < MAX_RETRY_COUNT)) {
            scheduleStartRetry(context, retryCount + 1)
        }
    }

    private fun scheduleStartRetry(context: Context, retryCount: Int) {
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val retryIntent = Intent(context, BootReceiver::class.java).apply {
            action = ACTION_RETRY_START
            putExtra(EXTRA_RETRY_COUNT, retryCount)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE
                } else {
                    0
                }
        val pendingIntent = PendingIntent.getBroadcast(context, 4102, retryIntent, flags)
        alarm.set(
            AlarmManager.RTC_WAKEUP,
            System.currentTimeMillis() + RETRY_DELAY_MS,
            pendingIntent
        )
    }
}
