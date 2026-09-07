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

    /**
     * How long to wait after a rebind that achieved *nothing*.
     *
     * This is the loop guard. If multicast has still not arrived since the
     * last rejoin, rejoining again is unlikely to help -- the fault is not the
     * group membership -- and repeating it every ninety seconds would move the
     * stream server's port every ninety seconds for no gain.
     */
    const val BACKOFF_MS = 10 * 60_000L

    /**
     * How long to wait after a rebind that *worked*.
     *
     * Measured 2026-09-07, and the reason this distinction exists at all. A
     * lapse healed at 09:05:17 armed a flat ten-minute backoff; a second,
     * unrelated lapse began at 09:08:41 and the watchdog then refused to act
     * on it for the rest of the backoff. The renderer was undiscoverable for
     * about six and a half minutes against a window that promises ninety
     * seconds, and the log said so in as many words:
     *
     *     09:39:45  not rejoining -- silent 270s, heard 456, last heal 341s ago
     *     09:40:45  not rejoining -- silent 331s, heard 456, last heal 402s ago
     *
     * Multicast plainly returned after the first heal, so that rebind worked
     * and the next lapse is a *new* fault rather than the old one unhealed.
     * The loop guard has no business suppressing it.
     *
     * Two minutes rather than nothing, because the detection window is ninety
     * seconds and a network whose multicast is merely sporadic -- a lone
     * neighbour announcing every few minutes -- would otherwise rebind on
     * every gap, and a renderer whose port moves constantly is worse for
     * controllers than one that is occasionally slow to be found. Two minutes
     * sits just above the window, so it cannot chain rebinds back to back
     * while barely delaying a genuine recurrence.
     *
     * Rebinding is cheap enough to justify this: measured twice against live
     * audio, it costs the stream nothing at all -- zero underruns, the frame
     * counter advancing 10.02 seconds' worth across a ten-second window -- and
     * costs a controller about two seconds before the renderer answers again
     * on its new port.
     */
    const val WORKING_BACKOFF_MS = 2 * 60_000L

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
        if (lastHealAt != 0L) {
            // Whether the last rebind achieved anything is readable from these
            // two timestamps alone: multicast heard *after* the rejoin means
            // the rejoin restored it, so this silence is a fresh fault and the
            // loop guard does not apply to it. Heard only before means nothing
            // came back, and doing the same thing again is what the long
            // backoff exists to prevent.
            val previousRejoinWorked = lastHeardAt > lastHealAt
            val wait = if (previousRejoinWorked) WORKING_BACKOFF_MS else BACKOFF_MS
            if (now - lastHealAt < wait) return false
        }
        return true
    }
}
