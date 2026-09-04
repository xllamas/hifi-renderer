package com.hifirend.upnp

import android.util.Log
import org.jupnp.support.contentdirectory.DIDLParser
import org.jupnp.support.model.DIDLObject

private const val TAG = "hifirend"

/**
 * What the main screen and the widget need about the current track, extracted
 * from the DIDL-Lite a controller sends with SetAVTransportURI.
 *
 * [durationSeconds] matters more than it looks: BubbleUPnP polls
 * GetPositionInfo/GetTransportInfo continuously (143 calls in one short test),
 * and a renderer that reports no duration makes the controller's progress bar
 * look broken even when playback is perfect.
 */
data class TrackMetadata(
    val title: String? = null,
    val artist: String? = null,
    val album: String? = null,
    val albumArtUri: String? = null,
    val durationSeconds: Int = 0,
    val mimeType: String? = null,
    val rawDuration: String? = null,
    /**
     * res@sampleFrequency, as announced by the server. 0 when absent.
     *
     * The server's own statement about the file, which lets a track the DAC
     * cannot clock be refused before any of it is fetched. It is a claim, not
     * a measurement -- the decoder remains the authority -- but it is the only
     * thing available before the download starts.
     */
    val sampleFrequency: Int = 0,
) {
    /** UPnP wants H:MM:SS. */
    val upnpDuration: String
        get() = if (durationSeconds <= 0) "00:00:00" else
            "%d:%02d:%02d".format(durationSeconds / 3600, (durationSeconds % 3600) / 60, durationSeconds % 60)

    companion object {
        /**
         * Controllers vary in what they send and how they escape it, so this
         * never throws: unparseable metadata degrades to empty rather than
         * failing the SetAVTransportURI that carried it.
         */
        fun parse(didl: String?): TrackMetadata {
            if (didl.isNullOrBlank()) return TrackMetadata()
            describeOffer(didl)
            return try {
                val item = DIDLParser().parse(didl).items.firstOrNull()
                    ?: return TrackMetadata()
                val res = item.resources?.firstOrNull()
                val raw = res?.duration
                TrackMetadata(
                    title = item.title?.takeIf { it.isNotBlank() },
                    artist = property(item, DIDLObject.Property.UPNP.ARTIST::class.java)
                        ?: item.creator?.takeIf { it.isNotBlank() },
                    album = property(item, DIDLObject.Property.UPNP.ALBUM::class.java),
                    albumArtUri = property(item, DIDLObject.Property.UPNP.ALBUM_ART_URI::class.java),
                    durationSeconds = parseDuration(raw),
                    mimeType = res?.protocolInfo?.contentFormat,
                    rawDuration = raw,
                    sampleFrequency = res?.sampleFrequency?.toInt() ?: 0,
                ).also {
                    Log.i(TAG, "metadata: '${it.title}' by '${it.artist}' " +
                        "album='${it.album}' ${it.durationSeconds}s mime=${it.mimeType}")
                }
            } catch (e: Throwable) {
                // jUPnP's parser is strict -- it rejects DIDL without
                // <upnp:class>, for instance. Controllers we will never test
                // against are under no obligation to be well-formed, and losing
                // the title and duration is a visible failure, so fall back to
                // pulling out the few fields that matter.
                Log.w(TAG, "strict DIDL parse failed (${e::class.java.simpleName}); using lenient fallback")
                lenient(didl)
            }
        }

        /**
         * Logs every <res> a controller offered, and the raw DIDL behind it.
         *
         * This is how to see whether a server transcoded and to what. A
         * transcoding server usually offers several <res> elements for one
         * track -- the original alongside converted alternatives -- or
         * substitutes a converted one outright, and the giveaway is in the
         * protocolInfo and the sampleFrequency/bitsPerSample attributes rather
         * than in anything the renderer can measure later. By the time audio
         * arrives, a transcode looks exactly like a file that was always that
         * format.
         *
         * Never throws and never affects parsing: this is observation only.
         */
        private fun describeOffer(didl: String) {
            try {
                val res = Regex("<res\\s([^>]*)>", RegexOption.DOT_MATCHES_ALL)
                    .findAll(didl).map { it.groupValues[1] }.toList()
                Log.i(TAG, "offer: ${res.size} <res> element(s) from the controller")
                res.forEachIndexed { i, attrs ->
                    fun a(n: String) = Regex("$n=\"([^\"]*)\"").find(attrs)?.groupValues?.get(1)
                    val detail = listOfNotNull(
                        a("protocolInfo")?.let { "protocolInfo=$it" },
                        a("sampleFrequency")?.let { "rate=$it" },
                        a("bitsPerSample")?.let { "bits=$it" },
                        a("nrAudioChannels")?.let { "ch=$it" },
                        a("bitrate")?.let { "bitrate=$it" },
                        a("size")?.let { "size=$it" },
                        a("duration")?.let { "duration=$it" },
                    ).joinToString(" ")
                    Log.i(TAG, "offer[$i]: $detail")
                }
                // The whole thing, chunked: logcat drops anything past about
                // 4 kB in one message, and DIDL from a real server exceeds it.
                val chunk = 3000
                val parts = (didl.length + chunk - 1) / chunk
                for (i in 0 until parts) {
                    Log.i(TAG, "didl[${i + 1}/$parts]: " +
                        didl.substring(i * chunk, minOf((i + 1) * chunk, didl.length)))
                }
            } catch (e: Throwable) {
                Log.w(TAG, "could not describe the offer: ${e::class.java.simpleName}")
            }
        }

        /** Last-resort extraction; no XML parsing, no exceptions. */
        internal fun lenient(didl: String): TrackMetadata {
            fun tag(name: String): String? =
                Regex("<$name(?:\\s[^>]*)?>(.*?)</$name>", RegexOption.DOT_MATCHES_ALL)
                    .find(didl)?.groupValues?.get(1)?.trim()?.takeIf { it.isNotEmpty() }

            val res = Regex("<res\\s([^>]*)>", RegexOption.DOT_MATCHES_ALL).find(didl)?.groupValues?.get(1)
            fun attr(n: String): String? = res?.let {
                Regex("$n=\"([^\"]*)\"").find(it)?.groupValues?.get(1)
            }

            val raw = attr("duration")
            return TrackMetadata(
                title = tag("dc:title"),
                artist = tag("upnp:artist") ?: tag("dc:creator"),
                album = tag("upnp:album"),
                albumArtUri = tag("upnp:albumArtURI"),
                durationSeconds = parseDuration(raw),
                mimeType = attr("protocolInfo")?.split(":")?.getOrNull(2),
                rawDuration = raw,
                sampleFrequency = attr("sampleFrequency")?.toIntOrNull() ?: 0,
            ).also {
                Log.i(TAG, "metadata (lenient): '${it.title}' by '${it.artist}' " +
                    "album='${it.album}' ${it.durationSeconds}s mime=${it.mimeType}")
            }
        }

        private fun <V> property(
            item: DIDLObject,
            type: Class<out DIDLObject.Property<V>>,
        ): String? = try {
            item.getFirstPropertyValue(type)?.toString()?.takeIf { it.isNotBlank() }
        } catch (_: Throwable) {
            null
        }

        /**
         * res@duration is H:MM:SS[.mmm] in the spec, but real controllers also
         * send MM:SS and stray whitespace, so accept what arrives.
         */
        internal fun parseDuration(s: String?): Int {
            if (s.isNullOrBlank()) return 0
            val parts = s.trim().split(":")
            if (parts.isEmpty()) return 0
            return try {
                val secs = parts.last().substringBefore('.').toDouble()
                when (parts.size) {
                    1 -> secs.toInt()
                    2 -> parts[0].toInt() * 60 + secs.toInt()
                    else -> parts[parts.size - 3].toInt() * 3600 +
                            parts[parts.size - 2].toInt() * 60 + secs.toInt()
                }
            } catch (_: NumberFormatException) {
                0
            }
        }
    }
}
