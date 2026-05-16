package com.aimlessoul.chessunlock

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import org.json.JSONArray

object PrefBridge {
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val WATCHER_PREFS = "ChessUnlockWatcherState"

    private const val K_INITIALIZED = "initialized"
    private const val K_LOCKED_PACKAGES = "lockedPackages"
    private const val K_UNLOCK_UNTIL_MS = "unlockUntilMs"
    private const val K_INDEF_UNLOCK = "indefUnlock"
    private const val K_LOCK_ENABLED = "lockEnabled"

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
        unlockUntilMs: Long
    ) {
        val sanitizedLockedPackages = sanitizeLockedPackages(ctx, lockedPackages)
        watcherPrefs(ctx).edit()
            .putBoolean(K_INITIALIZED, true)
            .putStringSet(K_LOCKED_PACKAGES, sanitizedLockedPackages)
            .putBoolean(K_LOCK_ENABLED, lockEnabled)
            .putBoolean(K_INDEF_UNLOCK, indefUnlock)
            .putLong(K_UNLOCK_UNTIL_MS, unlockUntilMs)
            .apply()
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
}
