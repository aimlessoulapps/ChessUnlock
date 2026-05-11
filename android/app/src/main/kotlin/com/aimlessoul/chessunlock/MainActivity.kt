package com.aimlessoul.chessunlock

import android.Manifest
import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "chesslock/system"
    private val maxIconDimension = 192
    private val maxIconPngBytes = 512 * 1024
    private val notificationPermissionRequestCode = 4101

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

                "syncWatcherState" -> {
                    syncWatcherState(call.arguments)
                    result.success(null)
                }

                "startWatcher" -> {
                    ForegroundAppWatcherService.start(this)
                    result.success(null)
                }

                "hideWatcherOverlay" -> {
                    ForegroundAppWatcherService.requestHideOverlay(this)
                    result.success(null)
                }

                "stopWatcher" -> {
                    ForegroundAppWatcherService.stop(this)
                    result.success(null)
                }

                "getLaunchableApps" -> {
                    result.success(getLaunchableApps())
                }

                else -> result.notImplemented()
            }
        }
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
            ?.toCollection(LinkedHashSet())
            ?: LinkedHashSet()
        val lockEnabled = args["lockEnabled"] as? Boolean ?: true
        val indefUnlock = args["indefiniteUnlock"] as? Boolean ?: false
        val unlockUntilMs = (args["unlockUntilMs"] as? Number)?.toLong() ?: 0L

        PrefBridge.saveWatcherState(
            applicationContext,
            packages,
            lockEnabled,
            indefUnlock,
            unlockUntilMs
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
            if (!seen.add(pkg)) continue

            val label = try {
                ri.loadLabel(pm)?.toString() ?: pkg
            } catch (_: Throwable) {
                pkg
            }

            val iconB64 = try {
                val d = ri.loadIcon(pm)
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

        out.sortBy { (it["appName"] as? String ?: "").lowercase() }
        return out
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
