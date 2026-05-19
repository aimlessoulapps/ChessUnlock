package com.aimlessoul.chessunlock

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager

class ForegroundAppWatcherService : Service() {

    companion object {
        private const val CHANNEL_ID = "chesslock_watcher"
        private const val NOTIF_ID = 14001

        private const val ACTION_HIDE_OVERLAY = "chesslock.action.HIDE_OVERLAY"
        private const val USAGE_EVENT_LOOKBACK_MS = 10_000L
        private const val USAGE_EVENT_OVERLAP_MS = 1000L
        private const val OVERLAY_CONFIRM_DELAY_MS = 250L
        private const val SELF_OPEN_SUPPRESS_MS = 1800L

        fun start(ctx: Context) {
            val i = Intent(ctx, ForegroundAppWatcherService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ctx.startForegroundService(i)
            } else {
                ctx.startService(i)
            }
        }

        fun requestHideOverlay(ctx: Context) {
            val i = Intent(ctx, ForegroundAppWatcherService::class.java)
            i.action = ACTION_HIDE_OVERLAY
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ctx.startForegroundService(i)
            } else {
                ctx.startService(i)
            }
        }

        fun stop(ctx: Context) {
            val i = Intent(ctx, ForegroundAppWatcherService::class.java)
            ctx.stopService(i)
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var running = false

    private var overlayShown = false
    private var overlayRoot: FrameLayout? = null
    private var overlaySubtitle: TextView? = null
    private var overlayBlockedPkg: String? = null
    private lateinit var wm: WindowManager

    private var lastPkg: String? = null
    private var lastUsageEventQueryMs: Long = 0L
    private var pendingBlockedPkg: String? = null
    private var pendingBlockedSinceMs: Long = 0L
    private var suppressOverlayUntilMs: Long = 0L

    private val tick = object : Runnable {
        override fun run() {
            if (!running) return

            try {
                val locked = PrefBridge.getLockedPackages(this@ForegroundAppWatcherService)
                if (locked.isEmpty()) {
                    hideOverlay()
                    scheduleNext(3000)
                    return
                }

                val enforceNow = shouldEnforceNow()

                val current = getForegroundPackage()
                val now = System.currentTimeMillis()

                if (current == packageName) {
                    clearPendingBlockedPackage()
                    hideOverlay()
                    scheduleNext(650)
                    return
                }

                val shouldBlock = enforceNow &&
                        current != null &&
                        locked.contains(current)

                if (!shouldBlock || now < suppressOverlayUntilMs) {
                    clearPendingBlockedPackage()
                    hideOverlay()
                    scheduleNext(if (now < suppressOverlayUntilMs) 300 else nextIntervalWhileUnlocked())
                    return
                }

                val blockedPkg = current!!
                if (overlayShown) {
                    showOverlay(blockedPkg)
                    scheduleNext(450)
                    return
                }

                if (pendingBlockedPkg != blockedPkg) {
                    pendingBlockedPkg = blockedPkg
                    pendingBlockedSinceMs = now
                    hideOverlay()
                    scheduleNext(OVERLAY_CONFIRM_DELAY_MS)
                    return
                }

                val elapsed = now - pendingBlockedSinceMs
                if (elapsed < OVERLAY_CONFIRM_DELAY_MS) {
                    scheduleNext((OVERLAY_CONFIRM_DELAY_MS - elapsed).coerceAtLeast(100L))
                    return
                }

                val confirmed = getForegroundPackage()
                if (confirmed == blockedPkg &&
                    confirmed != packageName &&
                    locked.contains(confirmed)
                ) {
                    showOverlay(confirmed)
                    scheduleNext(450)
                } else {
                    clearPendingBlockedPackage()
                    hideOverlay()
                    scheduleNext(350)
                }
            } catch (_: Throwable) {
                scheduleNext(1200)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification())
        running = true
        handler.post(tick)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_HIDE_OVERLAY) {
            clearPendingBlockedPackage()
            suppressOverlayUntilMs = System.currentTimeMillis() + SELF_OPEN_SUPPRESS_MS
            lastPkg = packageName
            hideOverlay()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        hideOverlay()
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun scheduleNext(ms: Long) {
        handler.removeCallbacks(tick)
        handler.postDelayed(tick, ms)
    }

    private fun clearPendingBlockedPackage() {
        pendingBlockedPkg = null
        pendingBlockedSinceMs = 0L
    }

    private fun nextIntervalWhileUnlocked(): Long {
        val indef = PrefBridge.getIndefUnlock(this)
        if (indef) return 3500

        val until = PrefBridge.getUnlockUntilMs(this)
        if (until <= 0L) return 1200

        val now = System.currentTimeMillis()
        val remaining = until - now
        return when {
            remaining <= 0 -> 450
            remaining <= 30_000 -> 700
            else -> 2000
        }
    }

    private fun shouldEnforceNow(): Boolean {
        val indef = PrefBridge.getIndefUnlock(this)
        if (indef) return false

        val until = PrefBridge.getUnlockUntilMs(this)
        if (until <= 0L) return true

        return System.currentTimeMillis() >= until
    }

    private fun getForegroundPackage(): String? {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val end = System.currentTimeMillis()
        val begin = if (lastUsageEventQueryMs > 0L) {
            (lastUsageEventQueryMs - USAGE_EVENT_OVERLAP_MS)
                .coerceAtLeast(end - USAGE_EVENT_LOOKBACK_MS)
        } else {
            end - USAGE_EVENT_LOOKBACK_MS
        }

        try {
            val events = usm.queryEvents(begin, end)
            val event = UsageEvents.Event()
            var sawTransitionEvent = false
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                when (event.eventType) {
                    UsageEvents.Event.ACTIVITY_RESUMED,
                    UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                        sawTransitionEvent = true
                        lastPkg = event.packageName
                    }
                    UsageEvents.Event.ACTIVITY_PAUSED,
                    UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                        sawTransitionEvent = true
                        if (event.packageName == lastPkg) {
                            lastPkg = null
                        }
                    }
                }
            }
            lastUsageEventQueryMs = end
            if (lastPkg != null) return lastPkg
            if (sawTransitionEvent) return null
        } catch (_: Throwable) {}

        return lastPkg
    }

    private fun showOverlay(blockedPkg: String) {
        if (blockedPkg == packageName) {
            clearPendingBlockedPackage()
            hideOverlay()
            return
        }

        if (overlayShown) {
            updateOverlayText(blockedPkg)
            return
        }

        val appName = appNameForPackage(blockedPkg)

        val root = FrameLayout(this)
        root.setBackgroundColor(0xCC000000.toInt())

        val card = LinearLayout(this)
        card.orientation = LinearLayout.VERTICAL
        card.setPadding(42, 42, 42, 36)

        val bg = GradientDrawable()
        bg.cornerRadius = 32f
        bg.setColor(0xFFFFFFFF.toInt())
        card.background = bg

        val title = TextView(this)
        title.text = "Locked"
        title.textSize = 20f
        title.setTextColor(0xFF111111.toInt())
        title.setPadding(0, 0, 0, 14)

        val subtitle = TextView(this)
        subtitle.text = overlaySubtitleText(appName)
        subtitle.textSize = 14f
        subtitle.setTextColor(0xFF333333.toInt())
        subtitle.setPadding(0, 0, 0, 24)

        val btn = Button(this)
        btn.text = "Open ChessUnlock"
        btn.setOnClickListener {
            AnalyticsLogger.overlayOpenChessLockClicked(this)
            clearPendingBlockedPackage()
            suppressOverlayUntilMs = System.currentTimeMillis() + SELF_OPEN_SUPPRESS_MS
            lastPkg = packageName
            hideOverlay()
            PrefBridge.requestOpenPuzzle(this)
            val i = Intent(this, MainActivity::class.java)
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            startActivity(i)
            handler.postDelayed(tick, 300)
        }

        card.addView(title)
        card.addView(subtitle)
        card.addView(btn)

        val lpCard = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        )
        lpCard.gravity = Gravity.CENTER
        lpCard.marginStart = 36
        lpCard.marginEnd = 36

        root.addView(card, lpCard)

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE

        val flags = WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_FULLSCREEN or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            flags,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.TOP or Gravity.START

        wm.addView(root, params)
        overlayRoot = root
        overlaySubtitle = subtitle
        overlayBlockedPkg = blockedPkg
        overlayShown = true
        CrashlyticsLogger.overlayShown()
        AnalyticsLogger.overlayShown(this)
    }

    private fun updateOverlayText(blockedPkg: String) {
        if (overlayBlockedPkg == blockedPkg) return
        overlaySubtitle?.text = overlaySubtitleText(appNameForPackage(blockedPkg))
        overlayBlockedPkg = blockedPkg
    }

    private fun appNameForPackage(pkg: String): String {
        return try {
            val ai = packageManager.getApplicationInfo(pkg, 0)
            packageManager.getApplicationLabel(ai)?.toString() ?: pkg
        } catch (_: Throwable) {
            pkg
        }
    }

    private fun overlaySubtitleText(appName: String): String {
        return "You're in: $appName\nSolve the puzzle to unlock."
    }

    private fun hideOverlay() {
        if (!overlayShown) return
        try {
            overlayRoot?.let { wm.removeView(it) }
        } catch (_: Throwable) {
        } finally {
            overlayRoot = null
            overlaySubtitle = null
            overlayBlockedPkg = null
            overlayShown = false
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val ch = NotificationChannel(
            CHANNEL_ID,
            "ChessUnlock Watcher",
            NotificationManager.IMPORTANCE_LOW
        )
        ch.setSound(null, null)
        ch.enableVibration(false)
        nm.createNotificationChannel(ch)
    }

    private fun buildNotification(): Notification {
        val openIntent = Intent(this, MainActivity::class.java)
        val pi = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            (PendingIntent.FLAG_UPDATE_CURRENT or
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("ChessUnlock running")
            .setContentText("Watching locked apps")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .setContentIntent(pi)
            .build()
    }
}
