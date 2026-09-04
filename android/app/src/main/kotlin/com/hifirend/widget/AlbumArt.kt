package com.hifirend.widget

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.util.Log
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

private const val TAG = "hifirend"

/**
 * Album art for the widget: fetched, downscaled and rounded off the main thread.
 *
 * Two hard constraints shape this.
 *
 * A RemoteViews update crosses a binder transaction with a ~1 MB ceiling for
 * the whole update, and album art from a media server is routinely 1000x1000
 * or larger — 4 MB decoded. Oversized art does not degrade, it throws
 * TransactionTooLargeException and the widget simply stops updating. So the
 * bitmap is decoded straight to widget size with inSampleSize and never held
 * at full resolution.
 *
 * The other is that the art URL points at someone else's media server, which
 * may be slow, gone, redirecting, or serving a 404 page as text/html. None of
 * that may disturb playback or leave the widget retrying in a loop, so a URL
 * that fails once is remembered and not attempted again.
 */
object AlbumArt {

    /**
     * Covers the art slot at the largest height a 2-cell widget is given on a
     * high-density panel, with room for the user resizing it taller. At
     * ARGB_8888 this is 410 KB, comfortably inside the binder budget.
     */
    private const val TARGET_PX = 320

    /** Art is an image; anything much larger than this is not one we want. */
    private const val MAX_BYTES = 6 * 1024 * 1024

    private val executor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "widget-art").apply { isDaemon = true }
    }

    @Volatile private var cachedUri: String? = null
    @Volatile private var cached: Bitmap? = null
    @Volatile private var failedUri: String? = null
    @Volatile private var loadingUri: String? = null

    /**
     * The art for [uri] if it is already decoded, otherwise null — and, in that
     * case, a fetch is started and [onLoaded] runs when it lands so the caller
     * can redraw. Never blocks.
     */
    fun forUri(uri: String?, onLoaded: () -> Unit): Bitmap? {
        if (uri.isNullOrBlank()) return null
        if (uri == cachedUri) return cached
        if (uri == failedUri || uri == loadingUri) return null

        loadingUri = uri
        executor.execute {
            val bitmap = runCatching { fetch(uri) }
                .onFailure { Log.w(TAG, "widget art failed: ${it::class.java.simpleName}: ${it.message}") }
                .getOrNull()
            if (bitmap != null) {
                cached = bitmap
                cachedUri = uri
            } else {
                failedUri = uri
            }
            loadingUri = null
            // Redraw either way: a failure has to replace whatever art the
            // previous track left on screen with the placeholder.
            runCatching { onLoaded() }
        }
        return null
    }

    private fun fetch(uri: String): Bitmap? {
        val bytes = download(uri) ?: return null

        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            Log.w(TAG, "widget art: not an image ($uri)")
            return null
        }

        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight)
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options) ?: return null
        return round(square(decoded))
    }

    private fun download(uri: String): ByteArray? {
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL(uri).openConnection() as HttpURLConnection).apply {
                connectTimeout = 5_000
                readTimeout = 5_000
                instanceFollowRedirects = true
                setRequestProperty("Accept", "image/*")
            }
            val code = conn.responseCode
            if (code !in 200..299) {
                Log.w(TAG, "widget art: HTTP $code for $uri")
                return null
            }
            val out = ByteArrayOutputStream()
            val buffer = ByteArray(16 * 1024)
            conn.inputStream.use { input ->
                while (true) {
                    val n = input.read(buffer)
                    if (n < 0) break
                    out.write(buffer, 0, n)
                    if (out.size() > MAX_BYTES) {
                        Log.w(TAG, "widget art: oversized, giving up on $uri")
                        return null
                    }
                }
            }
            out.toByteArray()
        } finally {
            runCatching { conn?.disconnect() }
        }
    }

    /**
     * inSampleSize only halves, so this lands on the first power of two at or
     * below the target — decoding at most 2x the pixels we need rather than
     * the 16x a large cover would otherwise cost.
     */
    private fun sampleSize(width: Int, height: Int): Int {
        var sample = 1
        val longest = maxOf(width, height)
        while (longest / (sample * 2) >= TARGET_PX) sample *= 2
        return sample
    }

    /** Centre-crops to a square at exactly [TARGET_PX], matching the layout slot. */
    private fun square(source: Bitmap): Bitmap {
        val side = minOf(source.width, source.height)
        val left = (source.width - side) / 2
        val top = (source.height - side) / 2
        val cropped = if (side == source.width && side == source.height) source
            else Bitmap.createBitmap(source, left, top, side, side)
        // Scale down only. Art smaller than the slot is left alone: upscaling it
        // costs memory in the binder transaction and makes it no sharper.
        if (cropped.width <= TARGET_PX) return cropped
        return Bitmap.createScaledBitmap(cropped, TARGET_PX, TARGET_PX, true)
    }

    /** RemoteViews cannot clip, so the corners have to be in the bitmap. */
    private fun round(source: Bitmap): Bitmap {
        val output = Bitmap.createBitmap(source.width, source.height, Bitmap.Config.ARGB_8888)
        val radius = source.width * 0.09f
        Canvas(output).drawRoundRect(
            RectF(0f, 0f, source.width.toFloat(), source.height.toFloat()),
            radius, radius,
            Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = BitmapShader(source, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
            },
        )
        return output
    }
}
