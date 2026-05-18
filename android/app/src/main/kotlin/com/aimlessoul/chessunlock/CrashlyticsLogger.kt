package com.aimlessoul.chessunlock

import com.google.firebase.crashlytics.FirebaseCrashlytics

object CrashlyticsLogger {
    fun overlayShown() {
        log("overlay_shown")
    }

    private fun log(message: String) {
        try {
            FirebaseCrashlytics
                .getInstance()
                .log(message)
        } catch (_: Throwable) {
            // Crash reporting must never affect overlay behavior.
        }
    }
}
