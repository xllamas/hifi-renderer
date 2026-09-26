package com.hifirend.upnp

import android.util.Log
import org.json.JSONObject
import org.jupnp.support.model.ProtocolInfo
import org.jupnp.support.model.ProtocolInfos

private const val TAG = "hifirend"

/**
 * What the renderer tells controllers it can accept.
 *
 * Controllers consult GetProtocolInfo before sending anything and refuse to
 * send formats that are absent, so a missing entry reads as "the renderer is
 * broken" rather than "that format is unsupported". Servers also use it to
 * decide whether to transcode.
 *
 * The list has to follow the attached DAC, because the DAC is what decides the
 * answer: a 768 kHz hi-fi DAC and a 48 kHz dongle are not the same renderer,
 * and advertising the same capabilities for both is how a controller ends up
 * sending a 96 kHz file to hardware that cannot clock it.
 *
 * Rates are only expressible for LPCM. There is no standard way to say "FLAC,
 * but only up to 48 kHz" in protocolInfo -- the DLNA profiles for compressed
 * formats carry no rate constraint -- so a rate-limited DAC gets its LPCM
 * entries narrowed to what it can actually clock, and the container formats are
 * governed by [allowNativeFormats] instead.
 */
object SinkFormats {

    /** Everything the decoders handle, independent of the DAC. */
    private val NATIVE = listOf(
        "audio/flac", "audio/x-flac",
        "audio/mpeg",
        "audio/mp4", "audio/aac", "audio/x-m4a",
        "audio/wav", "audio/x-wav", "audio/wave",
        "audio/aiff", "audio/x-aiff",
    )

    /**
     * DSD files, played as DoP -- 24-bit PCM at a sixteenth of the DSD rate.
     * Servers disagree on the name, so all three common ones are offered.
     */
    private val DSD = listOf("audio/x-dsd", "audio/x-dsf", "audio/x-dff")

    /**
     * Whether a DAC clocking [rates] can carry DSD64, the slowest DSD, which
     * arrives as DoP at 176.4 kHz. Not a property of the decoder: on a DAC
     * that stops at 96 kHz a DSD file is unplayable, and offering it would
     * only have the server send it and the track fail after the fetch.
     */
    fun canCarryDop(rates: List<Int>) = rates.any { it >= 176400 }

    /**
     * [caps] is the probe's capability JSON, or null when the DAC has not been
     * read (no device, or no permission yet) -- in which case the full list is
     * advertised, because refusing to name a format we can decode would leave
     * a controller unable to send anything at all.
     *
     * [allowNativeFormats] false drops the compressed and lossless container
     * formats, leaving only LPCM at rates the DAC can clock. That is what makes
     * a server transcode rather than send a file the DAC cannot play -- at the
     * cost of the bit-perfect path, since the server is then doing the decoding.
     *
     * That mode's guarantee is exactness in both directions: nothing but LPCM,
     * and no rate the DAC cannot clock. A stray container format would be sent
     * as-is and might exceed the ceiling; a stray rate would be transcoded
     * *to* something unplayable, which is worse than refusing the original,
     * because the server has then spent its effort producing a stream that
     * cannot play and the failure looks like the renderer's.
     */
    fun build(caps: JSONObject?, allowNativeFormats: Boolean = true): ProtocolInfos {
        val rates = playableRates(caps)
        val depths = playableDepths(caps)
        val entries = mutableListOf<String>()

        if (allowNativeFormats) {
            entries += NATIVE
            // Unlike the rest, gated on the DAC: with none read, or one that
            // cannot clock 176.4 kHz, there is nothing DoP could reach.
            if (canCarryDop(rates)) entries += DSD
        }

        // LPCM, qualified by rate. L16 is 16-bit and L24 is 24-bit by
        // definition, so each is only offered when the DAC has a container
        // that wide.
        // With the DAC unread -- no device, or no permission yet -- there are
        // no rates to be exact about. 44.1 and 48 kHz are what every DAC ever
        // made can clock, so they are the safe claim until the probe answers;
        // the advertisement is rebuilt when it does.
        val lpcmRates = rates.ifEmpty { listOf(44100, 48000) }
        for (rate in lpcmRates) {
            if (depths.isEmpty() || depths.any { it >= 16 }) {
                entries += "audio/L16;rate=$rate;channels=2"
            }
            if (depths.any { it >= 24 }) {
                entries += "audio/L24;rate=$rate;channels=2"
            }
        }

        val infos = ProtocolInfos()
        for (e in entries) {
            runCatching { infos.add(ProtocolInfo("http-get:*:$e:*")) }
                .onFailure { Log.w(TAG, "bad protocolInfo '$e': ${it.message}") }
        }

        // The same LPCM entries again, named by their DLNA profile.
        //
        // DLNA.ORG_PN=LPCM is defined for 16-bit L16 at 44.1 or 48 kHz, mono or
        // stereo, and a transcoding server decides what to convert *to* by
        // matching profile names rather than by parsing MIME parameters. A
        // renderer that offers only the bare "audio/L16;rate=..." form can be
        // read as having no profile the server knows how to produce, which
        // looks the same to it as a renderer that cannot accept LPCM at all.
        for (rate in lpcmRates.filter { it == 44100 || it == 48000 }) {
            if (depths.isNotEmpty() && depths.none { it >= 16 }) continue
            runCatching {
                infos.add(ProtocolInfo(
                    "http-get:*:audio/L16;rate=$rate;channels=2:DLNA.ORG_PN=LPCM"))
            }.onFailure { Log.w(TAG, "bad LPCM protocolInfo: ${it.message}") }
        }
        // Logged in full, not just counted. This list is the entire contract
        // with the server, and when it is wrong the symptom appears somewhere
        // else entirely -- as a track that will not play, or one that was
        // converted when it needed no converting.
        Log.i(TAG, "protocolInfo: ${infos.size} entries, rates=$lpcmRates " +
            "depths=$depths native=$allowNativeFormats")
        for (info in infos) Log.i(TAG, "  advertising ${info.contentFormat}")
        return infos
    }

    /**
     * Every rate the DAC can clock. UAC2 answers from the clock entity; UAC1
     * has none and lists rates per alt-setting instead, so both are gathered.
     */
    fun playableRates(caps: JSONObject?): List<Int> {
        if (caps == null) return emptyList()
        val out = sortedSetOf<Int>()
        caps.optJSONObject("clock")?.optJSONArray("rates")?.let { arr ->
            for (i in 0 until arr.length()) out.add(arr.optInt(i))
        }
        forEachPlayableFormat(caps) { f ->
            f.optJSONArray("rates")?.let { arr ->
                for (i in 0 until arr.length()) out.add(arr.optInt(i))
            }
        }
        out.remove(0)
        return out.toList()
    }

    private fun playableDepths(caps: JSONObject?): List<Int> {
        if (caps == null) return emptyList()
        val out = sortedSetOf<Int>()
        forEachPlayableFormat(caps) { f -> out.add(f.optInt("bits")) }
        out.remove(0)
        return out.toList()
    }

    /**
     * PCM alt-settings that can actually carry audio out. A capture-only
     * alt-setting looks identical apart from endpoint direction, and a headset
     * adapter exposes both.
     */
    private inline fun forEachPlayableFormat(caps: JSONObject, body: (JSONObject) -> Unit) {
        val formats = caps.optJSONArray("formats") ?: return
        for (i in 0 until formats.length()) {
            val f = formats.optJSONObject(i) ?: continue
            if (f.optString("format") != "PCM") continue
            if (f.optJSONObject("endpoint")?.optBoolean("iso") != true) continue
            body(f)
        }
    }
}
