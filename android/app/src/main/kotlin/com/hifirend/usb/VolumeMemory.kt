package com.hifirend.usb

import android.content.Context

/**
 * Remembers the volume per DAC, and decides what to start at when nothing is
 * remembered.
 *
 * Starting at whatever the hardware happens to hold is not acceptable. A DAC
 * powers up wherever it powered up, a device with unreadable volume reports its
 * maximum, and this app drives real amplifiers: the first track after a restart
 * arriving at full scale can damage equipment and hearing before anyone reaches
 * a control. So an unknown device starts quiet and is turned up deliberately.
 *
 * Keyed on vendor and product rather than the full device key, because the
 * serial is only readable while permission is held and would make the same DAC
 * look like a new one after a replug. Two DACs of the same model sharing a
 * remembered volume is a far better failure than a power amplifier being handed
 * the level that suited a pair of earphones.
 */
object VolumeMemory {

    private const val PREFS = "hifirend_usb"
    private const val PREFIX = "volume_"

    /** Quiet, but audible enough that the app does not look broken. */
    const val SAFE_DEFAULT = 10

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Stable across replugs and permission changes; see the class note. */
    fun key(vendorId: Int, productId: Int): String = "%04x:%04x".format(vendorId, productId)

    fun remembered(context: Context, key: String?): Int {
        if (key == null) return SAFE_DEFAULT
        return prefs(context).getInt(PREFIX + key, SAFE_DEFAULT).coerceIn(0, 100)
    }

    fun remember(context: Context, key: String?, percent: Int) {
        if (key == null) return
        prefs(context).edit().putInt(PREFIX + key, percent.coerceIn(0, 100)).apply()
    }
}
