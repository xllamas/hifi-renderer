package com.hifirend.upnp

import android.util.Log

private const val TAG = "hifirend"

/**
 * Turns an engine failure into something worth putting on the now-playing
 * screen.
 *
 * The engine's messages are written for a log: "no PCM alt-setting holds 24-bit
 * 2ch at 96000 Hz" is exactly what someone debugging the USB layer wants, and
 * exactly what nobody wants to read from across a room while a track silently
 * fails to start. Neither audience can be dropped -- a headline with no detail
 * is unactionable, and detail with no headline is what we had -- so both are
 * carried, and the screen decides how much of each to show.
 *
 * The mapping is deliberately coarse. What the listener can do about a failure
 * falls into very few categories: the track is wrong for this DAC, the DAC is
 * in trouble, or something else went wrong -- and a headline that tried to be
 * more specific would only be repeating the detail in longer words.
 *
 * What crosses to the screen is a **code**, not a sentence. The headline is a
 * sentence a person reads, so it has to exist in every language the app ships
 * in, and translations live in one place: `lib/l10n`. Composing English here
 * and translating it there would mean two sources of truth for the same
 * sentence, and the Kotlin one would be the one nobody remembered to update.
 * [detail] stays as the engine wrote it -- it is diagnostic, it goes in bug
 * reports, and it is more useful in English.
 */
object Problem {

    /**
     * @param code names the sentence; `lib/l10n/app_en.arb` holds the wording.
     * @param args fill its placeholders, in order. Integers because every
     *   parameterised failure so far is counting something -- a sample rate,
     *   a number of tracks.
     * @param detail the engine's own words, kept in English.
     */
    data class Described(
        val code: String,
        val args: List<Int> = emptyList(),
        val detail: String? = null,
    )

    const val SERVER_UNREACHABLE = "serverUnreachable"
    const val SERVER_REFUSED = "serverRefused"
    const val DOWNLOAD_FAILED = "downloadFailed"
    const val UNDECODABLE = "undecodableFormat"
    const val DAC_RATE_UNSUPPORTED = "dacRateUnsupported"
    const val DAC_LOST = "dacConnectionLost"
    const val UNKNOWN = "trackCouldNotBePlayed"
    const val RATE_UNPLAYABLE = "rateUnplayable"
    const val RATE_NOT_OFFERED = "rateNotOffered"
    const val STRIKES = "stoppedAfterFailures"
    const val SKIPPED = "tracksSkipped"

    /**
     * A track refused before it was fetched, because its rate is above
     * anything the DAC can clock. Both rates travel as hertz and are formatted
     * for display on the other side, where the reader's conventions are known.
     */
    fun rateUnplayable(announcedHz: Int, ceilingHz: Int) =
        Described(RATE_UNPLAYABLE, listOf(announcedHz, ceilingHz))

    /**
     * A track refused before it was fetched, because its rate is within the
     * DAC's range but not one it offers -- 88.2 kHz on a DAC that lists 96.
     * Saying "its highest rate is 768 kHz" here would read as nonsense.
     */
    fun rateNotOffered(announcedHz: Int) = Described(RATE_NOT_OFFERED, listOf(announcedHz))

    /** The playlist gave up after this many tracks failed one after another. */
    fun stoppedAfterFailures(count: Int) = Described(STRIKES, listOf(count))

    /** The playlist reached its end having stepped over this many tracks. */
    fun tracksSkipped(count: Int) = Described(SKIPPED, listOf(count))

    /**
     * Whether [hz] is a rate audio is actually recorded at: a multiple of
     * either clock family, 11 025 Hz (44.1k, 88.2k, DSD64...) or 8 kHz (48k,
     * 96k, 32k...).
     *
     * Exists because of a real report. BubbleUPnP announced some Qobuz tracks
     * as `sampleFrequency="44000"`; the FLAC itself said 44100. Taken at its
     * word, that was refused as a rate the DAC does not offer, and tracks that
     * played fine in the Qobuz app would not play here at all.
     */
    fun isRealRate(hz: Int) = hz > 0 && (hz % 11025 == 0 || hz % 8000 == 0)

    /**
     * Why a track announced at [announcedHz] cannot play on a DAC offering
     * [dacRates], or null when there is no reason to think it cannot.
     *
     * The announced rate is the server's claim, not a measurement, so it is
     * only acted on when it is plausible; anything else is left to the
     * decoder, which reads the rate from the stream itself.
     */
    fun forAnnouncedRate(announcedHz: Int, dacRates: List<Int>): Described? {
        if (dacRates.isEmpty() || announcedHz <= 0) return null   // nothing to go on
        if (dacRates.contains(announcedHz)) return null
        if (!isRealRate(announcedHz)) {
            Log.w(TAG, "ignoring announced rate $announcedHz Hz: not a real audio rate; " +
                "the stream's own header will decide")
            return null
        }
        val ceiling = dacRates.max()
        return if (announcedHz > ceiling) rateUnplayable(announcedHz, ceiling)
        else rateNotOffered(announcedHz)
    }

    fun describe(technical: String): Described {
        val m = technical.lowercase()
        val code = when {
            // Checked first, and deliberately so. A server that goes away
            // mid-playlist reaches the decoder as a stream that ended early,
            // and the decoder's honest report of that ("not a decodable FLAC
            // stream") would otherwise match the format case below and send
            // someone to look at their files when the fault is their network.
            m.contains("media server could not be reached") ||
                m.contains("media server stopped responding") ||
                m.contains("address could not be resolved") -> SERVER_UNREACHABLE

            m.contains("server answered http") -> SERVER_REFUSED

            m.contains("could not be fetched") -> DOWNLOAD_FAILED

            m.contains("unsupported or unrecognised") ||
                m.contains("not a decodable") ||
                m.contains("not integer pcm") ||
                m.contains("no mp3 frame") -> UNDECODABLE

            // The DAC is fine and the file is fine; they simply do not meet.
            m.contains("does not support") ||
                m.contains("no pcm alt-setting") ||
                m.contains("set sample rate") ||
                m.contains("which no dac can be configured for") -> DAC_RATE_UNSUPPORTED

            m.contains("libusb") || m.contains("claim_interface") ||
                m.contains("set_alt_setting") || m.contains("iso transfer") ||
                m.contains("no pcm isochronous") || m.contains("audio class version") -> DAC_LOST

            else -> UNKNOWN
        }
        return Described(code, detail = technical)
    }
}
