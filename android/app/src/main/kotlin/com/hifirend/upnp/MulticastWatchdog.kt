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
     * Silence that condemns a network we have barely heard from.
     *
     * Four minutes is far outside normal variation while still recovering long
     * before anybody reaches for the phone, and it is the safe figure to use
     * when there is not yet enough traffic to judge by.
     */
    const val SILENCE_MS = 4 * 60_000L

    /**
     * Silence that condemns a *demonstrably busy* network.
     *
     * Measured on the network this was found on: 3210 announcements in forty
     * minutes, better than one a second. Ninety seconds of silence there is
     * not a quiet patch, it is deafness -- and waiting four minutes to say so
     * leaves the renderer invisible for four minutes each time. Measured over
     * a night: eight lapses in fourteen hours, fifteen minutes of invisibility
     * in total at ninety seconds, against something over half an hour of it at
     * four.
     */
    const val BUSY_SILENCE_MS = 90_000L

    /**
     * Multicasts that make a network "busy" enough to trust the shorter
     * window. Twenty is more than a lone neighbour announcing occasionally and
     * far less than a real network manages in a minute.
     */
    const val BUSY_THRESHOLD = 20L

    /** Never rebind more often than this, whatever the network is doing. */
    const val BACKOFF_MS = 10 * 60_000L

    /**
     * @param lastHeardAt when multicast last arrived, or 0 if it never has.
     * @param lastHealAt when this last rebound, or 0 if never.
     * @param heardCount how much multicast has ever arrived, which is what
     *   decides whether the network is busy enough to judge quickly.
     */
    @JvmOverloads
    fun shouldHeal(
        lastHeardAt: Long,
        lastHealAt: Long,
        now: Long,
        heardCount: Long = 0L,
    ): Boolean {
        // Never having heard multicast is not evidence of losing it. A network
        // with nothing else on it would otherwise rebind for ever, and the
        // renderer would be *less* reliable for being watched.
        if (lastHeardAt == 0L) return false
        val silence = if (heardCount >= BUSY_THRESHOLD) BUSY_SILENCE_MS else SILENCE_MS
        if (now - lastHeardAt < silence) return false
        if (lastHealAt != 0L && now - lastHealAt < BACKOFF_MS) return false
        return true
    }
}
