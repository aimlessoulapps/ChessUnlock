package com.aimlessoul.chessunlock

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/** Recovery opens a visible activity; it never schedules another background start. */
internal object WatcherRecovery {
    private const val CHANNEL = "chesslock_watcher_recovery"
    private const val ID = 14002

    fun show(context: Context) {
        try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.createNotificationChannel(NotificationChannel(
                    CHANNEL, "App locking needs attention", NotificationManager.IMPORTANCE_DEFAULT
                ))
            }
            // If notifications are disabled, in-app recovery remains available.
            if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return
            val open = PendingIntent.getActivity(context, ID,
                Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            manager.notify(ID, NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setContentTitle("App locking is not running")
                .setContentText("Open ChessUnlock to resume monitoring your selected apps.")
                .setContentIntent(open)
                .setAutoCancel(true)
                .build())
        } catch (error: RuntimeException) {
            Log.w("ChessUnlockWatcher", "Unable to show recovery notification", error)
        }
    }

    fun clear(context: Context) {
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(ID)
    }
}
