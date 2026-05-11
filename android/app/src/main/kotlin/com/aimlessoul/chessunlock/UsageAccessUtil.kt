package com.aimlessoul.chessunlock

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build

object UsageAccessUtil {

    private var cachedPkg: String? = null
    private var cachedTs: Long = 0L

    fun hasUsageAccess(context: Context): Boolean {
        return try {
            val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    context.packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    context.packageName
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * Stable foreground detection:
     * - Looks at last few seconds of UsageEvents to find latest RESUMED/FOREGROUND
     * - If no events exist (user stays in same app), returns cachedPkg instead of null.
     */
    fun getForegroundPackage(context: Context): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return null

        return try {
            val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val end = System.currentTimeMillis()
            val begin = end - 4000

            val events = usm.queryEvents(begin, end)
            val e = UsageEvents.Event()

            var lastPkg: String? = null
            var lastTs = 0L

            while (events.hasNextEvent()) {
                events.getNextEvent(e)
                val pkg = e.packageName ?: continue
                val ts = e.timeStamp

                val isResume =
                    (Build.VERSION.SDK_INT >= 29 && e.eventType == UsageEvents.Event.ACTIVITY_RESUMED) ||
                            e.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND

                if (isResume && ts >= lastTs) {
                    lastTs = ts
                    lastPkg = pkg
                }
            }

            if (lastPkg != null) {
                cachedPkg = lastPkg
                cachedTs = lastTs
                lastPkg
            } else {
                cachedPkg
            }
        } catch (_: Throwable) {
            cachedPkg
        }
    }
}