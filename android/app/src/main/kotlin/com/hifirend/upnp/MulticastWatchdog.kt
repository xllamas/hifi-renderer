package com.hifirend.upnp

/**
 * Decides when the renderer has stopped hearing multicast and should rejoin
 * the SSDP group.
 *
 * Pure, because the interesting part is a few time comparisons whose failure
 * modes are both severe and slow: firing too eagerly rebinds the stack under a
 * working renderer and forces every controller to rediscover it, and never
 * firing leaves the appliance invisible for hours, which is the fault this
 * exists to end. Neither shows up in a quick manual check.
 */
object MulticastWatchdog {

    /**
     * Silence beyond this means we have stopped hearing the network rather
     * than the network having gone quiet. Announcements arrive every few
     * seconds on a real home network -- twenty-odd devices on the one this was
     * measured on -- so four minutes is far outside normal variation while
     * still recovering long before anybody reaches for the phone.
     */
    const val SILENCE_MS = 4 * 60_000L

    /** Never rebind more often than this, whatever the network is doing. */
    const val BACKOFF_MS = 10 * 60_000L

    /**
     * @param lastHeardAt when multicast last arrived, or 0 if it never has.
     * @param lastHealAt when this last rebound, or 0 if never.
     */
    fun shouldHeal(lastHeardAt: Long, lastHealAt: Long, now: Long): Boolean {
        // Never having heard multicast is not evidence of losing it. A network
        // with nothing else on it would otherwise rebind for ever, and the
        // renderer would be *less* reliable for being watched.
        if (lastHeardAt == 0L) return false
        if (now - lastHeardAt < SILENCE_MS) return false
        if (lastHealAt != 0L && now - lastHealAt < BACKOFF_MS) return false
        return true
    }
}
