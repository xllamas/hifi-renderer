package com.hifirend.upnp

import android.content.Context

/**
 * Whether the media server may convert tracks the DAC cannot play.
 *
 * A DAC has a rate ceiling, and protocolInfo can only express one for LPCM:
 * there is no standard way to advertise "FLAC, but only up to 48 kHz", because
 * the DLNA profiles for compressed and lossless containers carry no rate
 * constraint. So the renderer has exactly two things it can say to a server,
 * and they trade against each other:
 *
 *  - Advertise the formats we decode. Files at rates the DAC supports play
 *    bit-perfectly. A file above its ceiling is refused, and reported.
 *  - Withhold them, leaving only LPCM at rates the DAC can clock. Everything
 *    plays, because the server converts -- and nothing is bit-perfect any
 *    more, including files that would have played untouched.
 *
 * Defaulting to the first is the only defensible choice for an app whose
 * entire purpose is the untouched path: silently trading it away to avoid an
 * error message would be exactly the sort of thing this app exists to expose in
 * other people's hardware.
 */
object ServerConversion {

    private const val PREFS = "hifirend_upnp"
    private const val KEY = "allow_server_conversion"

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY, false)

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY, enabled).apply()
    }
}
