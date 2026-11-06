package com.aimlessoul.chessunlock

/** Rebuild the last foreground transition on restart, then query incrementally. */
internal class ForegroundAppState {
    var packageName: String? = null
    private var lastQueryMs = 0L

    fun queryStartMs(nowMs: Long): Long = if (lastQueryMs == 0L || nowMs < lastQueryMs) {
        // Bounded recovery avoids scanning a full day on every 800ms poll.
        packageName = null
        nowMs - 24 * 60 * 60_000L
    } else {
        // Include transitions across a long sleep instead of dropping them.
        maxOf(lastQueryMs - 1000L, nowMs - 24 * 60 * 60_000L)
    }

    fun resumed(packageName: String?) {
        this.packageName = packageName
    }

    fun paused(packageName: String?) {
        if (this.packageName == packageName) this.packageName = null
    }

    fun screenHidden() {
        packageName = null
    }

    fun queryCompleted(nowMs: Long) {
        lastQueryMs = nowMs
    }
}
