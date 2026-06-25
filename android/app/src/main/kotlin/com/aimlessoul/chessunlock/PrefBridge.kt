package com.aimlessoul.chessunlock

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object PrefBridge {
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val WATCHER_PREFS = "ChessUnlockWatcherState"

    private const val K_INITIALIZED = "initialized"
    private const val K_LOCKED_PACKAGES = "lockedPackages"
    private const val K_UNLOCK_UNTIL_MS = "unlockUntilMs"
    private const val K_INDEF_UNLOCK = "indefUnlock"
    private const val K_LOCK_ENABLED = "lockEnabled"
    private const val K_OPEN_PUZZLE_REQUESTED = "openPuzzleRequested"
    private const val K_OPEN_PAYWALL_REQUESTED = "openPaywallRequested"
    private const val K_PREMIUM_ACTIVE = "premiumActive"
    private const val K_EMERGENCY_UNLOCK_DAY_KEY = "emergencyUnlockDayKey"
    private const val K_EMERGENCY_UNLOCK_COUNT = "emergencyUnlockCount"
    private const val K_EMERGENCY_UNLOCK_DAILY_LIMIT = "emergencyUnlockDailyLimit"
    private const val K_EMERGENCY_UNLOCK_PACKAGE = "emergencyUnlockPackage"
    private const val K_EMERGENCY_UNLOCK_UNTIL_MS = "emergencyUnlockUntilMs"

    private const val FLUTTER_EMERGENCY_UNLOCK_DAY_KEY =
        "flutter.premium.emergencyUnlock.dayKey.v1"
    private const val FLUTTER_EMERGENCY_UNLOCK_COUNT =
        "flutter.premium.emergencyUnlock.count.v1"
    private const val DEFAULT_EMERGENCY_UNLOCK_DAILY_LIMIT = 3
    private const val EMERGENCY_UNLOCK_DURATION_MS = 60_000L

    enum class EmergencyUnlockResult {
        UNLOCKED,
        NOT_PREMIUM,
        ACTIVE,
        LIMIT_REACHED
    }

    private fun prefs(ctx: Context): SharedPreferences {
        return ctx.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
    }

    private fun watcherPrefs(ctx: Context): SharedPreferences {
        val storageCtx = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            ctx.createDeviceProtectedStorageContext()
        } else {
            ctx
        }
        return storageCtx.getSharedPreferences(WATCHER_PREFS, Context.MODE_PRIVATE)
    }

    private fun sanitizeLockedPackages(ctx: Context, packages: Iterable<String>): LinkedHashSet<String> {
        val ownPackage = ctx.packageName
        return packages
            .map { it.trim() }
            .filterTo(LinkedHashSet()) { it.isNotBlank() && it != ownPackage }
    }

    fun saveWatcherState(
        ctx: Context,
        lockedPackages: Set<String>,
        lockEnabled: Boolean,
        indefUnlock: Boolean,
        unlockUntilMs: Long,
        premiumActive: Boolean,
        emergencyUnlockDayKey: String,
        emergencyUnlockCount: Int,
        emergencyUnlockDailyLimit: Int
    ) {
        val sanitizedLockedPackages = sanitizeLockedPackages(ctx, lockedPackages)
        val usage = normalizedEmergencyUsage(
            ctx,
            emergencyUnlockDayKey,
            emergencyUnlockCount,
            emergencyUnlockDailyLimit
        )
        watcherPrefs(ctx).edit()
            .putBoolean(K_INITIALIZED, true)
            .putStringSet(K_LOCKED_PACKAGES, sanitizedLockedPackages)
            .putBoolean(K_LOCK_ENABLED, lockEnabled)
            .putBoolean(K_INDEF_UNLOCK, indefUnlock)
            .putLong(K_UNLOCK_UNTIL_MS, unlockUntilMs)
            .putBoolean(K_PREMIUM_ACTIVE, premiumActive)
            .putString(K_EMERGENCY_UNLOCK_DAY_KEY, usage.dayKey)
            .putInt(K_EMERGENCY_UNLOCK_COUNT, usage.count)
            .putInt(K_EMERGENCY_UNLOCK_DAILY_LIMIT, usage.limit)
            .apply()
    }

    fun requestOpenPuzzle(ctx: Context) {
        watcherPrefs(ctx).edit()
            .putBoolean(K_OPEN_PUZZLE_REQUESTED, true)
            .apply()
    }

    fun requestOpenPaywall(ctx: Context) {
        watcherPrefs(ctx).edit()
            .putBoolean(K_OPEN_PAYWALL_REQUESTED, true)
            .apply()
    }

    fun consumeOpenPuzzleRequest(ctx: Context): Boolean {
        val prefs = watcherPrefs(ctx)
        val requested = prefs.getBoolean(K_OPEN_PUZZLE_REQUESTED, false)
        if (requested) {
            prefs.edit()
                .putBoolean(K_OPEN_PUZZLE_REQUESTED, false)
                .apply()
        }
        return requested
    }

    fun consumeOpenPaywallRequest(ctx: Context): Boolean {
        val prefs = watcherPrefs(ctx)
        val requested = prefs.getBoolean(K_OPEN_PAYWALL_REQUESTED, false)
        if (requested) {
            prefs.edit()
                .putBoolean(K_OPEN_PAYWALL_REQUESTED, false)
                .apply()
        }
        return requested
    }

    private fun hasWatcherState(ctx: Context): Boolean {
        return watcherPrefs(ctx).getBoolean(K_INITIALIZED, false)
    }

    fun getLockedPackages(ctx: Context): Set<String> {
        if (hasWatcherState(ctx)) {
            val raw = watcherPrefs(ctx).getStringSet(K_LOCKED_PACKAGES, emptySet())
                ?: emptySet()
            val sanitized = sanitizeLockedPackages(ctx, raw)
            if (sanitized != raw) {
                watcherPrefs(ctx).edit()
                    .putStringSet(K_LOCKED_PACKAGES, sanitized)
                    .apply()
            }
            return sanitized
        }

        val sp = prefs(ctx)
        val raw = sp.getString("flutter.lockedPackages", null) ?: return emptySet()

        val trimmed = raw.trim()
        val json = when {
            trimmed.startsWith("[") && trimmed.endsWith("]") -> trimmed
            else -> {
                val start = trimmed.indexOf('[')
                val end = trimmed.lastIndexOf(']')
                if (start >= 0 && end > start) trimmed.substring(start, end + 1) else null
            }
        } ?: return emptySet()

        return try {
            val arr = JSONArray(json)
            val out = LinkedHashSet<String>()
            for (i in 0 until arr.length()) {
                val v = arr.optString(i, "")
                if (v.isNotBlank()) out.add(v)
            }
            sanitizeLockedPackages(ctx, out)
        } catch (_: Throwable) {
            emptySet()
        }
    }

    fun getUnlockUntilMs(ctx: Context): Long {
        if (hasWatcherState(ctx)) {
            return watcherPrefs(ctx).getLong(K_UNLOCK_UNTIL_MS, 0L)
        }

        val sp = prefs(ctx)
        return try {
            sp.getLong("flutter.unlockUntilMs", 0L)
        } catch (_: ClassCastException) {
            (sp.getInt("flutter.unlockUntilMs", 0)).toLong()
        }
    }

    fun getIndefUnlock(ctx: Context): Boolean {
        if (hasWatcherState(ctx)) {
            return watcherPrefs(ctx).getBoolean(K_INDEF_UNLOCK, false)
        }

        val sp = prefs(ctx)
        return try {
            sp.getBoolean("flutter.indefUnlock", false)
        } catch (_: ClassCastException) {
            (sp.getString("flutter.indefUnlock", "false") == "true")
        }
    }

    fun getLockEnabled(ctx: Context): Boolean {
        if (hasWatcherState(ctx)) {
            return watcherPrefs(ctx).getBoolean(K_LOCK_ENABLED, true)
        }

        val sp = prefs(ctx)
        return try {
            sp.getBoolean("flutter.lockEnabled", true)
        } catch (_: ClassCastException) {
            sp.getString("flutter.lockEnabled", "true") != "false"
        }
    }

    fun shouldRunWatcher(ctx: Context): Boolean {
        if (getLockedPackages(ctx).isEmpty()) return false
        if (getIndefUnlock(ctx)) return false

        val hasTimedUnlock = getUnlockUntilMs(ctx) > 0L
        return getLockEnabled(ctx) || hasTimedUnlock
    }

    fun isEmergencyUnlocked(ctx: Context, packageName: String): Boolean {
        val prefs = watcherPrefs(ctx)
        val unlockedPackage = prefs.getString(K_EMERGENCY_UNLOCK_PACKAGE, null)
        if (getEmergencyUnlockActiveRemainingMs(ctx) <= 0L) {
            return false
        }

        return unlockedPackage == packageName
    }

    fun tryUseEmergencyUnlock(ctx: Context, packageName: String): EmergencyUnlockResult {
        val prefs = watcherPrefs(ctx)
        if (!prefs.getBoolean(K_PREMIUM_ACTIVE, false)) {
            return EmergencyUnlockResult.NOT_PREMIUM
        }

        if (getEmergencyUnlockActiveRemainingMs(ctx) > 0L) {
            return EmergencyUnlockResult.ACTIVE
        }

        val usage = normalizedEmergencyUsage(ctx)
        if (usage.count >= usage.limit) {
            return EmergencyUnlockResult.LIMIT_REACHED
        }

        val nextCount = usage.count + 1
        saveEmergencyUsage(ctx, usage.dayKey, nextCount)

        prefs.edit()
            .putString(K_EMERGENCY_UNLOCK_PACKAGE, packageName)
            .putLong(
                K_EMERGENCY_UNLOCK_UNTIL_MS,
                System.currentTimeMillis() + EMERGENCY_UNLOCK_DURATION_MS
            )
            .apply()

        return EmergencyUnlockResult.UNLOCKED
    }

    fun getEmergencyUnlockActiveRemainingMs(ctx: Context): Long {
        val prefs = watcherPrefs(ctx)
        val unlockUntilMs = prefs.getLong(K_EMERGENCY_UNLOCK_UNTIL_MS, 0L)
        val unlockedPackage = prefs.getString(K_EMERGENCY_UNLOCK_PACKAGE, null)
        val now = System.currentTimeMillis()

        if (unlockUntilMs <= now) {
            if (unlockUntilMs > 0L || unlockedPackage != null) {
                prefs.edit()
                    .remove(K_EMERGENCY_UNLOCK_PACKAGE)
                    .remove(K_EMERGENCY_UNLOCK_UNTIL_MS)
                    .apply()
            }
            return 0L
        }

        return unlockUntilMs - now
    }

    fun getEmergencyUnlockRemaining(ctx: Context): Int {
        val usage = normalizedEmergencyUsage(ctx)
        return (usage.limit - usage.count).coerceAtLeast(0)
    }

    private data class EmergencyUsage(
        val dayKey: String,
        val count: Int,
        val limit: Int
    )

    private fun normalizedEmergencyUsage(
        ctx: Context,
        dayKey: String? = null,
        count: Int? = null,
        limit: Int? = null
    ): EmergencyUsage {
        val prefs = watcherPrefs(ctx)
        val today = todayKey()
        val rawDayKey = dayKey?.takeIf { it.isNotBlank() }
            ?: prefs.getString(K_EMERGENCY_UNLOCK_DAY_KEY, null)
        val rawCount = count ?: prefs.getInt(K_EMERGENCY_UNLOCK_COUNT, 0)
        val rawLimit = limit ?: prefs.getInt(
            K_EMERGENCY_UNLOCK_DAILY_LIMIT,
            DEFAULT_EMERGENCY_UNLOCK_DAILY_LIMIT
        )
        val normalizedLimit = rawLimit.coerceAtLeast(0)
        val normalizedCount = if (rawDayKey == today) {
            rawCount.coerceIn(0, normalizedLimit)
        } else {
            0
        }
        val normalized = EmergencyUsage(today, normalizedCount, normalizedLimit)

        if (rawDayKey != today || rawCount != normalizedCount || rawLimit != normalizedLimit) {
            prefs.edit()
                .putString(K_EMERGENCY_UNLOCK_DAY_KEY, normalized.dayKey)
                .putInt(K_EMERGENCY_UNLOCK_COUNT, normalized.count)
                .putInt(K_EMERGENCY_UNLOCK_DAILY_LIMIT, normalized.limit)
                .apply()
            saveEmergencyUsage(ctx, normalized.dayKey, normalized.count)
        }

        return normalized
    }

    private fun saveEmergencyUsage(ctx: Context, dayKey: String, count: Int) {
        watcherPrefs(ctx).edit()
            .putString(K_EMERGENCY_UNLOCK_DAY_KEY, dayKey)
            .putInt(K_EMERGENCY_UNLOCK_COUNT, count)
            .apply()

        prefs(ctx).edit()
            .putString(FLUTTER_EMERGENCY_UNLOCK_DAY_KEY, dayKey)
            .putInt(FLUTTER_EMERGENCY_UNLOCK_COUNT, count)
            .apply()
    }

    private fun todayKey(): String {
        return SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
    }
}
