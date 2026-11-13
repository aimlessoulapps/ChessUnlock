package com.aimlessoul.chessunlock

import android.Manifest
import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ResultReceiver
import android.provider.Settings
import android.util.Base64
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "chesslock/system"
    private val TAG = "ChessUnlockAppList"
    private val maxIconDimension = 192
    private val maxIconPngBytes = 512 * 1024
    private val notificationPermissionRequestCode = 4101
    private var resumed = false

    override fun onResume() {
        super.onResume()
        resumed = true
    }

    override fun onPause() {
        resumed = false
        super.onPause()
    }

    private fun startWatcher(result: MethodChannel.Result) {
        if (ForegroundAppWatcherService.isRunning) {
            result.success(null)
            return
        }
        if (!resumed) {
            WatcherRecovery.show(this)
            result.error("watcherUnavailable", "Open ChessUnlock to resume app locking.", null)
            return
        }
        val handler = Handler(Looper.getMainLooper())
        var completed = false
        fun complete(success: Boolean) {
            if (completed) return
            completed = true
            handler.removeCallbacksAndMessages(null)
            if (success) result.success(null)
            else result.error("watcherUnavailable", "App locking is not running. Tap Retry in ChessUnlock.", null)
        }
        val receiver = object : ResultReceiver(handler) {
            override fun onReceiveResult(resultCode: Int, resultData: Bundle?) {
                complete(resultCode == 1)
            }
        }
        handler.postDelayed({
            if (!completed) {
                ForegroundAppWatcherService.stop(this)
                WatcherRecovery.show(this)
                complete(false)
            }
        }, 8_000L)
        if (!ForegroundAppWatcherService.start(this, receiver)) complete(false)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasUsageAccess" -> result.success(hasUsageAccess())
                "openUsageAccessSettings" -> {
                    openUsageAccessSettings()
                    result.success(null)
                }

                "hasOverlayPermission" -> result.success(hasOverlayPermission())
                "openOverlaySettings" -> {
                    openOverlaySettings()
                    result.success(null)
                }

                "hasNotificationPermission" -> result.success(hasNotificationPermission())
                "requestNotificationPermission" -> {
                    requestNotificationPermissionIfNeeded()
                    result.success(null)
                }

                "getOwnPackageName" -> {
                    result.success(packageName)
                }

                "consumeOpenPuzzleRequest" -> {
                    result.success(PrefBridge.consumeOpenPuzzleRequest(applicationContext))
                }

                "consumeOpenPaywallRequest" -> {
                    result.success(PrefBridge.consumeOpenPaywallRequest(applicationContext))
                }

                "reserveEmergencyUnlockUse" -> {
                    result.success(PrefBridge.reserveEmergencyUnlockUse(applicationContext))
                }

                "getEmergencyUnlockUsage" -> {
                    result.success(PrefBridge.getEmergencyUnlockUsage(applicationContext))
                }

                "syncWatcherState" -> {
                    try {
                        syncWatcherState(call.arguments)
                        result.success(null)
                    } catch (error: IllegalArgumentException) {
                        result.error("unlockDurationNotAllowed", error.message, null)
                    }
                }

                "startWatcher" -> {
                    startWatcher(result)
                }

                "hideWatcherOverlay" -> {
                    ForegroundAppWatcherService.requestHideOverlay()
                    result.success(null)
                }

                "stopWatcher" -> {
                    ForegroundAppWatcherService.stop(this)
                    result.success(null)
                }

                "getLaunchableApps" -> runAsyncResult(result, "getLaunchableApps") {
                    getLaunchableApps()
                }

                "getLaunchableAppIcons" -> {
                    val args = call.arguments as? Map<*, *>
                    val packageNames = (args?.get("packageNames") as? List<*>)
                        ?.mapNotNull { it?.toString()?.takeIf { pkg -> pkg.isNotBlank() } }
                        ?: emptyList()
                    runAsyncResult(result, "getLaunchableAppIcons") {
                        getLaunchableAppIcons(packageNames)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun runAsyncResult(
        result: MethodChannel.Result,
        label: String,
        block: () -> Any
    ) {
        Thread {
            try {
                val value = block()
                runOnUiThread {
                    result.success(value)
                }
            } catch (t: Throwable) {
                debugAppList("$label failed: ${t.message ?: t.javaClass.simpleName}")
                runOnUiThread {
                    result.error(label, t.message, null)
                }
            }
        }.start()
    }

    private fun hasOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else true
    }

    private fun openOverlaySettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        }
    }

    private fun syncWatcherState(arguments: Any?) {
        val args = arguments as? Map<*, *> ?: return
        val packages = (args["lockedPackages"] as? List<*>)
            ?.mapNotNull { it?.toString()?.takeIf { pkg -> pkg.isNotBlank() } }
            ?.filter { pkg -> pkg != packageName }
            ?.toCollection(LinkedHashSet())
            ?: LinkedHashSet()
        val lockEnabled = args["lockEnabled"] as? Boolean ?: true
        val indefUnlock = args["indefiniteUnlock"] as? Boolean ?: false
        val unlockUntilMs = (args["unlockUntilMs"] as? Number)?.toLong() ?: 0L
        val premiumActive = args["premiumActive"] as? Boolean ?: false
        val premiumValidUntilMs = (args["premiumValidUntilMs"] as? Number)?.toLong() ?: 0L
        val emergencyUnlockDayKey = args["emergencyUnlockDayKey"] as? String ?: ""
        val emergencyUnlockCount = (args["emergencyUnlockCount"] as? Number)?.toInt() ?: 0
        val emergencyUnlockDailyLimit = (args["emergencyUnlockDailyLimit"] as? Number)?.toInt() ?: 0

        PrefBridge.saveWatcherState(
            applicationContext,
            packages,
            lockEnabled,
            indefUnlock,
            unlockUntilMs,
            premiumActive,
            premiumValidUntilMs,
            args["manualLockPause"] as? Boolean ?: false,
            emergencyUnlockDayKey,
            emergencyUnlockCount,
            emergencyUnlockDailyLimit
        )
    }

    private fun hasNotificationPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                    PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            !hasNotificationPermission()
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                notificationPermissionRequestCode
            )
        }
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun openUsageAccessSettings() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    private fun getLaunchableApps(): List<Map<String, Any>> {
        val started = SystemClock.elapsedRealtime()
        debugAppList("getLaunchableApps start")
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN, null)
        intent.addCategory(Intent.CATEGORY_LAUNCHER)

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            android.content.pm.PackageManager.MATCH_ALL
        } else 0

        val resolved = pm.queryIntentActivities(intent, flags)

        val seen = HashSet<String>()
        val out = ArrayList<Map<String, Any>>(resolved.size)

        for (ri in resolved) {
            val pkg = ri.activityInfo.packageName ?: continue
            if (pkg == packageName) continue
            if (!seen.add(pkg)) continue

            val label = try {
                ri.loadLabel(pm)?.toString() ?: pkg
            } catch (_: Throwable) {
                pkg
            }

            out.add(
                mapOf(
                    "packageName" to pkg,
                    "appName" to label,
                    "iconPngBase64" to ""
                )
            )
        }

        out.sortBy { (it["appName"] as? String ?: "").lowercase() }
        debugAppList(
            "getLaunchableApps end count=${out.size} durationMs=${SystemClock.elapsedRealtime() - started}"
        )
        return out
    }

    private fun getLaunchableAppIcons(packageNames: List<String>): List<Map<String, Any>> {
        val started = SystemClock.elapsedRealtime()
        debugAppList("getLaunchableAppIcons start count=${packageNames.size}")
        val pm = packageManager
        val out = ArrayList<Map<String, Any>>(packageNames.size)

        for (pkg in packageNames.distinct()) {
            if (pkg == packageName) continue

            val appInfo = try {
                @Suppress("DEPRECATION")
                pm.getApplicationInfo(pkg, 0)
            } catch (_: Throwable) {
                continue
            }

            val label = try {
                pm.getApplicationLabel(appInfo)?.toString() ?: pkg
            } catch (_: Throwable) {
                pkg
            }

            val iconB64 = try {
                val d = pm.getApplicationIcon(appInfo)
                val png = drawableToPngBytes(d)
                Base64.encodeToString(png, Base64.NO_WRAP)
            } catch (_: Throwable) {
                ""
            }

            out.add(
                mapOf(
                    "packageName" to pkg,
                    "appName" to label,
                    "iconPngBase64" to iconB64
                )
            )
        }

        debugAppList(
            "getLaunchableAppIcons end count=${out.size} durationMs=${SystemClock.elapsedRealtime() - started}"
        )
        return out
    }

    private fun debugAppList(message: String) {
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            Log.d(TAG, message)
        }
    }

    private fun drawableToPngBytes(drawable: Drawable): ByteArray {
        val bmp: Bitmap = when (drawable) {
            is BitmapDrawable -> scaleBitmapForIcon(drawable.bitmap)
            is AdaptiveIconDrawable -> {
                val size = maxIconDimension
                val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bitmap)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
                bitmap
            }
            else -> {
                val w = if (drawable.intrinsicWidth > 0) {
                    drawable.intrinsicWidth.coerceAtMost(maxIconDimension)
                } else {
                    maxIconDimension
                }
                val h = if (drawable.intrinsicHeight > 0) {
                    drawable.intrinsicHeight.coerceAtMost(maxIconDimension)
                } else {
                    maxIconDimension
                }
                val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bitmap)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
                bitmap
            }
        }

        val os = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, os)
        val bytes = os.toByteArray()
        if (bytes.size > maxIconPngBytes) {
            throw IllegalStateException("Icon PNG too large")
        }
        return bytes
    }

    private fun scaleBitmapForIcon(bitmap: Bitmap): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        if (width <= maxIconDimension && height <= maxIconDimension) {
            return bitmap
        }

        val scale = maxIconDimension.toFloat() / maxOf(width, height).toFloat()
        val targetWidth = (width * scale).toInt().coerceAtLeast(1)
        val targetHeight = (height * scale).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(bitmap, targetWidth, targetHeight, true)
    }
}
