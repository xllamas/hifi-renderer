package com.hifirend.usb

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Log
import com.hifirend.NativeBridge
import java.util.concurrent.atomic.AtomicBoolean

private const val TAG = "hifirend"

/**
 * Decodes AAC (and any other format the platform handles) with MediaCodec,
 * feeding the resulting PCM straight to the USB engine.
 *
 * Using the platform decoder avoids bundling an AAC implementation, and it
 * costs nothing in fidelity: MediaCodec is a *decoder*, not the system mixer,
 * so its PCM output still reaches the DAC untouched at the source's own rate.
 * That is the distinction that matters — routing through AudioTrack would
 * resample; decoding does not.
 *
 * MediaExtractor fetches the URL itself, so this path does not use the
 * NetworkStream pipe the native decoders read from.
 */
class AacDecoder {

    private val running = AtomicBoolean(false)
    private var thread: Thread? = null

    fun start(uri: String, fd: Int, seekSeconds: Int, onFailure: (String) -> Unit): Boolean {
        stop()
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(uri, mapOf("User-Agent" to "HiFiRenderer/1.0 DLNADOC/1.50"))
        } catch (e: Throwable) {
            extractor.release()
            onFailure("Could not open stream: ${e.message}")
            return false
        }

        var track = -1
        var format: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val f = extractor.getTrackFormat(i)
            if (f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                track = i; format = f; break
            }
        }
        if (track < 0 || format == null) {
            extractor.release()
            onFailure("No audio track in stream")
            return false
        }

        val mime = format.getString(MediaFormat.KEY_MIME)!!
        val rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        Log.i(TAG, "aac: $mime $rate Hz ${channels}ch")

        val started = NativeBridge.startPcmStream(fd, rate, channels, seekSeconds)
        if (!started.contains("\"ok\":true")) {
            extractor.release()
            onFailure(started)
            return false
        }

        extractor.selectTrack(track)
        if (seekSeconds > 0) {
            extractor.seekTo(seekSeconds * 1_000_000L, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
        }

        running.set(true)
        thread = Thread({ decodeLoop(extractor, format, mime) }, "aac-decode").apply {
            isDaemon = true
            start()
        }
        return true
    }

    private fun decodeLoop(extractor: MediaExtractor, format: MediaFormat, mime: String) {
        var codec: MediaCodec? = null
        try {
            codec = MediaCodec.createDecoderByType(mime).apply {
                configure(format, null, null, 0)
                start()
            }
            val info = MediaCodec.BufferInfo()
            var sawInputEnd = false

            while (running.get()) {
                if (!sawInputEnd) {
                    val inIndex = codec.dequeueInputBuffer(10_000)
                    if (inIndex >= 0) {
                        val buf = codec.getInputBuffer(inIndex)!!
                        val size = extractor.readSampleData(buf, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(
                                inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            sawInputEnd = true
                        } else {
                            codec.queueInputBuffer(inIndex, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                val outIndex = codec.dequeueOutputBuffer(info, 10_000)
                if (outIndex >= 0) {
                    if (info.size > 0) {
                        val out = codec.getOutputBuffer(outIndex)!!
                        val bytes = ByteArray(info.size)
                        out.position(info.offset)
                        out.get(bytes, 0, info.size)
                        // Blocks while the ring is full, which is the
                        // backpressure keeping memory bounded.
                        if (!NativeBridge.pushPcm(bytes, bytes.size)) break
                    }
                    codec.releaseOutputBuffer(outIndex, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
            if (running.get()) NativeBridge.pcmEndOfStream()
        } catch (e: Throwable) {
            Log.e(TAG, "aac: decode failed: ${e::class.java.simpleName}: ${e.message}")
        } finally {
            runCatching { codec?.stop() }
            runCatching { codec?.release() }
            runCatching { extractor.release() }
            Log.i(TAG, "aac: decoder finished")
        }
    }

    fun stop() {
        running.set(false)
        thread?.join(1500)
        thread = null
    }
}
