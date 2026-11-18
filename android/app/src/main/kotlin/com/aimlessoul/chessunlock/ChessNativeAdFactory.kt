package com.aimlessoul.chessunlock

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import com.google.android.gms.ads.nativead.MediaView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class ChessNativeAdFactory(private val context: Context) : GoogleMobileAdsPlugin.NativeAdFactory {
    override fun createNativeAd(ad: NativeAd, customOptions: MutableMap<String, Any>?): NativeAdView {
        val medium = customOptions?.get("medium") == true
        val dark = customOptions?.get("dark") == true
        fun dp(value: Int) = (value * context.resources.displayMetrics.density).toInt()
        val foreground = if (dark) Color.WHITE else Color.BLACK
        val root = NativeAdView(context)
        root.setBackgroundColor(if (dark) Color.rgb(35, 39, 43) else Color.rgb(242, 245, 242))
        val column = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        root.addView(column, android.widget.FrameLayout.LayoutParams(-1, -1))
        fun label(value: String?, size: Float) = TextView(context).apply {
            text = value; textSize = size; setTextColor(foreground)
            includeFontPadding = false
        }
        if (medium) {
            val media = MediaView(context)
            column.addView(media, LinearLayout.LayoutParams(-1, dp(140)))
            root.mediaView = media
            media.mediaContent = ad.mediaContent
            media.setImageScaleType(android.widget.ImageView.ScaleType.FIT_CENTER)
        }
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = android.view.Gravity.CENTER_VERTICAL
            setPadding(dp(8), dp(3), dp(24), dp(3)) // Reserve the SDK AdChoices corner.
        }
        column.addView(row, LinearLayout.LayoutParams(-1, if (medium) dp(100) else dp(54)))
        ad.icon?.drawable?.let { drawable ->
            val icon = android.widget.ImageView(context).apply {
                setImageDrawable(drawable); scaleType = android.widget.ImageView.ScaleType.FIT_CENTER
            }
            row.addView(icon, LinearLayout.LayoutParams(dp(36), dp(36)).apply { rightMargin = dp(6) })
            root.iconView = icon
        }
        val textColumn = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        row.addView(textColumn, LinearLayout.LayoutParams(0, -2, 1f))
        val headline = label(ad.headline, if (medium) 16f else 12f).apply {
            setTypeface(null, Typeface.BOLD); maxLines = 2
        }
        textColumn.addView(headline)
        root.headlineView = headline
        val details = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL }
        textColumn.addView(details)
        details.addView(label("Ad", 12f).apply {
            setTypeface(null, Typeface.BOLD)
            gravity = android.view.Gravity.CENTER
            setTextColor(Color.BLACK); setBackgroundColor(Color.rgb(255, 210, 80))
        }, LinearLayout.LayoutParams(dp(24), dp(18)).apply { rightMargin = dp(4) })
        val advertiser = label(ad.advertiser ?: ad.store, 10f).apply { maxLines = 1 }
        details.addView(advertiser, LinearLayout.LayoutParams(0, -2, 1f))
        if (ad.advertiser != null) root.advertiserView = advertiser else root.storeView = advertiser
        val cta = Button(context).apply {
            text = ad.callToAction; textSize = 11f; isAllCaps = false
            setPadding(dp(4), 0, dp(4), 0); minWidth = 0; minimumWidth = 0
            visibility = if (ad.callToAction == null) View.GONE else View.VISIBLE
        }
        row.addView(cta, LinearLayout.LayoutParams(dp(88), dp(44)).apply { leftMargin = dp(6) })
        root.callToActionView = cta
        root.setNativeAd(ad)
        return root
    }
}
