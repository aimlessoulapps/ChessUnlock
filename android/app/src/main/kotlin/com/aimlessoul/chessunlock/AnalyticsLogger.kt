package com.aimlessoul.chessunlock

import android.content.Context
import android.os.Bundle
import com.google.firebase.analytics.FirebaseAnalytics

object AnalyticsLogger {
    fun overlayShown(context: Context) {
        logEvent(context, "app_lock_overlay_shown")
    }

    fun overlayOpenChessLockClicked(context: Context) {
        logEvent(context, "open_chesslock_from_overlay_tapped")
    }

    private fun logEvent(context: Context, name: String) {
        try {
            FirebaseAnalytics
                .getInstance(context.applicationContext)
                .logEvent(name, Bundle().apply {
                    putString("screen_name", "AppLockOverlay")
                })
        } catch (_: Throwable) {
            // Analytics must never affect overlay behavior.
        }
    }
}
