package com.aimlessoul.chessunlock

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
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
        private const val FOREGROUND_POLL_ACTIVE_MS = 800L
        private const val OVERLAY_CONFIRM_DELAY_MS = 100L
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
    private var overlayEmergencyButton: Button? = null
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
                        locked.contains(current) &&
                        !PrefBridge.isEmergencyUnlocked(this@ForegroundAppWatcherService, current)

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
                    locked.contains(confirmed) &&
                    !PrefBridge.isEmergencyUnlocked(this@ForegroundAppWatcherService, confirmed)
                ) {
                    showOverlay(confirmed)
                    scheduleNext(450)
                } else {
                    clearPendingBlockedPackage()
                    hideOverlay()
                    scheduleNext(350)
                }
            } catch (_: Throwable) {
                scheduleNext(FOREGROUND_POLL_ACTIVE_MS)
            }
        }
    }

    private val emergencyButtonTick = object : Runnable {
        override fun run() {
            if (!running || !overlayShown) return
            updateEmergencyButtonState()
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
        if (until <= 0L) return FOREGROUND_POLL_ACTIVE_MS

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

        val root = FrameLayout(this)
        root.setBackgroundColor(0xE6000000.toInt())

        val card = FrameLayout(this)
        card.setPadding(dp(24), dp(24), dp(24), dp(24))

        val bg = GradientDrawable()
        bg.cornerRadius = dp(28).toFloat()
        bg.setColor(0xFF151A17.toInt())
        bg.setStroke(dp(1), 0x24FFFFFF)
        card.background = bg

        val cardContent = LinearLayout(this)
        cardContent.orientation = LinearLayout.VERTICAL
        cardContent.gravity = Gravity.CENTER_HORIZONTAL
        cardContent.setPadding(0, dp(44), 0, dp(2))

        val iconFrame = FrameLayout(this)
        val iconBg = GradientDrawable()
        iconBg.cornerRadius = dp(22).toFloat()
        iconBg.setColor(0x1F43D66E)
        iconBg.setStroke(dp(1), 0x3343D66E)
        iconFrame.background = iconBg

        val icon = ImageView(this)
        icon.setImageDrawable(applicationInfo.loadIcon(packageManager))
        icon.scaleType = ImageView.ScaleType.FIT_CENTER
        val iconLp = FrameLayout.LayoutParams(dp(42), dp(42))
        iconLp.gravity = Gravity.CENTER
        iconFrame.addView(icon, iconLp)

        val title = TextView(this)
        title.text = "This app is Restricted"
        title.textSize = 22f
        title.typeface = Typeface.DEFAULT_BOLD
        title.gravity = Gravity.CENTER
        title.setTextColor(0xFFF4F7F5.toInt())
        title.setPadding(0, dp(22), 0, dp(10))

        val subtitle = TextView(this)
        subtitle.text = overlaySubtitleText()
        subtitle.textSize = 15f
        subtitle.gravity = Gravity.CENTER
        subtitle.setLineSpacing(0f, 1.12f)
        subtitle.setTextColor(0xFFB9C4BD.toInt())
        subtitle.setPadding(0, 0, 0, dp(24))

        val btn = Button(this)
        btn.text = "Open ChessUnlock"
        btn.isAllCaps = false
        btn.textSize = 16f
        btn.typeface = Typeface.DEFAULT_BOLD
        btn.setTextColor(0xFF06110A.toInt())
        val btnBg = GradientDrawable()
        btnBg.cornerRadius = dp(18).toFloat()
        btnBg.setColor(0xFF43D66E.toInt())
        btn.background = btnBg
        btn.setOnClickListener {
            AnalyticsLogger.overlayOpenChessUnlockClicked(this)
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

        val emergencyBtn = Button(this)
        emergencyBtn.isAllCaps = false
        emergencyBtn.textSize = 12f
        emergencyBtn.typeface = Typeface.DEFAULT_BOLD
        emergencyBtn.setTextColor(0xFF43D66E.toInt())
        emergencyBtn.minHeight = 0
        emergencyBtn.minWidth = 0
        emergencyBtn.setIncludeFontPadding(false)
        emergencyBtn.setPadding(dp(10), dp(4), dp(10), dp(4))
        val emergencyBtnBg = GradientDrawable()
        emergencyBtnBg.cornerRadius = dp(16).toFloat()
        emergencyBtnBg.setColor(0x00151A17)
        emergencyBtnBg.setStroke(dp(1), 0x6643D66E)
        emergencyBtn.background = emergencyBtnBg

        val iconFrameLp = LinearLayout.LayoutParams(dp(76), dp(76))
        cardContent.addView(iconFrame, iconFrameLp)
        cardContent.addView(title)
        cardContent.addView(subtitle)
        val btnLp = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dp(54)
        )
        cardContent.addView(btn, btnLp)

        val contentLp = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        )
        card.addView(cardContent, contentLp)

        val emergencyBtnLp = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            dp(42)
        )
        emergencyBtnLp.gravity = Gravity.TOP or Gravity.END
        card.addView(emergencyBtn, emergencyBtnLp)

        val lpCard = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        )
        lpCard.gravity = Gravity.CENTER
        lpCard.marginStart = dp(24)
        lpCard.marginEnd = dp(24)

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
        overlayEmergencyButton = emergencyBtn
        overlayBlockedPkg = blockedPkg
        overlayEmergencyButton?.setOnClickListener {
            handleEmergencyUnlockTap(blockedPkg)
        }
        overlayShown = true
        updateEmergencyButtonState()
        CrashlyticsLogger.overlayShown()
        AnalyticsLogger.overlayShown(this)
    }

    private fun updateOverlayText(blockedPkg: String) {
        if (overlayBlockedPkg == blockedPkg) return
        overlaySubtitle?.text = overlaySubtitleText()
        overlayEmergencyButton?.setOnClickListener {
            handleEmergencyUnlockTap(blockedPkg)
        }
        overlayBlockedPkg = blockedPkg
        updateEmergencyButtonState()
    }

    private fun overlaySubtitleText(): String {
        return "Solve a chess puzzle in ChessUnlock to use this app."
    }

    private fun emergencyUnlockButtonText(): String {
        val activeMs = PrefBridge.getEmergencyUnlockActiveRemainingMs(this)
        if (activeMs > 0L) {
            return "Emergency\n${formatCountdown(activeMs)}"
        }
        return "Emergency\n1 min - ${PrefBridge.getEmergencyUnlockRemaining(this)} left"
    }

    private fun updateEmergencyButtonState() {
        val activeMs = PrefBridge.getEmergencyUnlockActiveRemainingMs(this)
        val remaining = PrefBridge.getEmergencyUnlockRemaining(this)
        val enabled = activeMs <= 0L && remaining > 0
        overlayEmergencyButton?.text = emergencyUnlockButtonText()
        overlayEmergencyButton?.isEnabled = enabled
        overlayEmergencyButton?.alpha = if (enabled || activeMs > 0L) 1.0f else 0.55f

        handler.removeCallbacks(emergencyButtonTick)
        if (overlayShown && activeMs > 0L) {
            handler.postDelayed(emergencyButtonTick, 1000L)
        }
    }

    private fun formatCountdown(ms: Long): String {
        val totalSeconds = ((ms + 999L) / 1000L).coerceAtLeast(1L)
        val minutes = totalSeconds / 60L
        val seconds = totalSeconds % 60L
        return "$minutes:${seconds.toString().padStart(2, '0')}"
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density + 0.5f).toInt()
    }

    private fun hideOverlay() {
        if (!overlayShown) {
            handler.removeCallbacks(emergencyButtonTick)
            return
        }
        try {
            overlayRoot?.let { wm.removeView(it) }
        } catch (_: Throwable) {
        } finally {
            handler.removeCallbacks(emergencyButtonTick)
            overlayRoot = null
            overlaySubtitle = null
            overlayEmergencyButton = null
            overlayBlockedPkg = null
            overlayShown = false
        }
    }

    private fun handleEmergencyUnlockTap(blockedPkg: String) {
        when (PrefBridge.tryUseEmergencyUnlock(this, blockedPkg)) {
            PrefBridge.EmergencyUnlockResult.UNLOCKED -> {
                Toast.makeText(this, "Emergency unlock started for 1 minute.", Toast.LENGTH_SHORT).show()
                clearPendingBlockedPackage()
                hideOverlay()
                handler.postDelayed(tick, 300)
            }
            PrefBridge.EmergencyUnlockResult.ACTIVE -> {
                updateEmergencyButtonState()
                Toast.makeText(this, "Emergency unlock is already active.", Toast.LENGTH_SHORT).show()
            }
            PrefBridge.EmergencyUnlockResult.NOT_PREMIUM -> {
                Toast.makeText(this, "ChessUnlock Premium required.", Toast.LENGTH_SHORT).show()
                clearPendingBlockedPackage()
                suppressOverlayUntilMs = System.currentTimeMillis() + SELF_OPEN_SUPPRESS_MS
                lastPkg = packageName
                hideOverlay()
                PrefBridge.requestOpenPaywall(this)
                val i = Intent(this, MainActivity::class.java)
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                startActivity(i)
                handler.postDelayed(tick, 300)
            }
            PrefBridge.EmergencyUnlockResult.LIMIT_REACHED -> {
                updateEmergencyButtonState()
                Toast.makeText(this, "Emergency unlock limit reached for today.", Toast.LENGTH_SHORT).show()
            }
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
