package com.hifirend.usb

import android.content.Context
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbManager
import android.util.Log
import com.hifirend.NativeBridge
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

private const val TAG = "hifirend"

/**
 * Fetches a track over HTTP and feeds it to the native decoder.
 *
 * HTTP stays in Kotlin because redirects, TLS and byte-range requests are
 * solved problems here; the audio engine only wants bytes. This is the path a
 * DLNA controller drives — BubbleUPnP proxying Tidal hands us a plain HTTP
 * FLAC URL, so that is the shape it is built for.
 *
 * The USB connection must outlive the stream: native wraps the file descriptor
 * but does not own it, so closing early pulls it out from under the transfers.
 */
class HttpStreamPlayback(private val context: Context) {

    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private var connection: UsbDeviceConnection? = null
    private val fetching = AtomicBoolean(false)

    @Volatile
    var currentUri: String? = null
        private set

    fun play(uri: String): String {
        stop()

        val device = UsbAudioProbe(context).findAudioDevice()
            ?: return """{"ok":false,"message":"No USB audio device connected."}"""
        if (!usbManager.hasPermission(device)) {
            return """{"ok":false,"message":"USB permission not granted. Open the app and probe the DAC once."}"""
        }
        val conn = usbManager.openDevice(device)
            ?: return """{"ok":false,"message":"Could not open the DAC."}"""

        for (i in 0 until device.interfaceCount) {
            val itf = device.getInterface(i)
            if (itf.interfaceClass == UsbConstants.USB_CLASS_AUDIO) {
                conn.claimInterface(itf, true)
            }
        }
        connection = conn

        val started = NativeBridge.startStream(conn.fileDescriptor)
        if (!started.contains("\"ok\":true")) {
            stop()
            return started
        }

        currentUri = uri
        fetching.set(true)
        thread(name = "http-fetch", isDaemon = true) { fetch(uri) }
        Log.i(TAG, "stream: fetching $uri")
        return """{"ok":true,"uri":"${uri.replace("\"", "\\\"")}"}"""
    }

    private fun fetch(uri: String) {
        var stream: InputStream? = null
        var conn: HttpURLConnection? = null
        try {
            conn = (URL(uri).openConnection() as HttpURLConnection).apply {
                connectTimeout = 15_000
                readTimeout = 30_000
                instanceFollowRedirects = true
                // Some DLNA servers behave differently for unknown agents, and
                // a few refuse to stream without a Range header at all.
                setRequestProperty("User-Agent", "HiFiRenderer/1.0 DLNADOC/1.50")
                setRequestProperty("Connection", "close")
            }
            val code = conn.responseCode
            if (code !in 200..299) {
                Log.e(TAG, "stream: HTTP $code for $uri")
                NativeBridge.endStream()
                return
            }
            Log.i(TAG, "stream: HTTP $code, type=${conn.contentType}, len=${conn.contentLengthLong}")

            stream = conn.inputStream
            val buf = ByteArray(32 * 1024)
            var total = 0L
            while (fetching.get()) {
                val n = stream.read(buf)
                if (n < 0) break
                if (n > 0) {
                    total += n
                    // Blocks when the native buffer is full; that backpressure
                    // is what stops a fast server buffering a whole album.
                    if (!NativeBridge.pushStreamData(buf, n)) break
                }
            }
            Log.i(TAG, "stream: fetched $total bytes")
        } catch (e: Throwable) {
            Log.e(TAG, "stream: fetch failed: ${e::class.java.simpleName}: ${e.message}")
        } finally {
            runCatching { stream?.close() }
            runCatching { conn?.disconnect() }
            NativeBridge.endStream()
        }
    }

    fun stop() {
        fetching.set(false)
        NativeBridge.stopStream()
        connection?.close()
        connection = null
        currentUri = null
    }

    fun status(): String = NativeBridge.streamStatus()
    fun positionSeconds(): Int = NativeBridge.streamPositionSeconds()
}
