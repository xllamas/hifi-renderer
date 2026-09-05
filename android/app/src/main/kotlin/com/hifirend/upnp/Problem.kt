package com.hifirend.upnp

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
 */
object Problem {

    data class Described(val headline: String, val detail: String?)

    /** Already-plain messages, such as a refusal composed for the user. */
    fun plain(message: String) = Described(message, null)

    fun describe(technical: String): Described {
        val m = technical.lowercase()
        val headline = when {
            m.contains("unsupported or unrecognised") ||
                m.contains("not a decodable") ||
                m.contains("not integer pcm") ||
                m.contains("no mp3 frame") ->
                "This track is in a format the renderer cannot decode."

            // The DAC is fine and the file is fine; they simply do not meet.
            m.contains("does not support") ||
                m.contains("no pcm alt-setting") ||
                m.contains("set sample rate") ||
                m.contains("which no dac can be configured for") ->
                "This DAC cannot be set to this track's rate or bit depth."

            m.contains("libusb") || m.contains("claim_interface") ||
                m.contains("set_alt_setting") || m.contains("iso transfer") ||
                m.contains("no pcm isochronous") || m.contains("audio class version") ->
                "The renderer lost its connection to the DAC."

            else -> "This track could not be played."
        }
        return Described(headline, technical)
    }
}
