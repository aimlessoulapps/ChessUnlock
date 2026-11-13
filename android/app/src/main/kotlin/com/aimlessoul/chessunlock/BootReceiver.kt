package com.aimlessoul.chessunlock

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (!PrefBridge.shouldRunWatcher(context)) return
        when (action) {
            // Exempt broadcasts; specialUse is allowed to start at boot.
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> ForegroundAppWatcherService.start(context)

            // Neither USER_UNLOCKED nor an old inexact retry alarm is exempt.
            Intent.ACTION_USER_UNLOCKED,
            "com.aimlessoul.chessunlock.action.RETRY_START_WATCHER" -> {
                if (!ForegroundAppWatcherService.isRunning) WatcherRecovery.show(context)
            }
        }
    }
}
