package com.hifirend.power

/**
 * When the panel should be held lit, and when it should be let go.
 *
 * Pure decision logic, with no Android in it, because the interesting part is
 * a small state machine over time and that is worth being able to test without
 * a device. The Android half -- the window flag and waking the screen -- lives
 * in [ScreenPolicy].
 *
 * The rule the spec asks for: the screen stays on while music is playing, and
 * goes dark once it has been quiet for a while. So playing continuously
 * refreshes the deadline, and the countdown only starts when playback stops.
 * That is why this takes the playing flag on every tick rather than being told
 * about transitions: a missed transition would strand the screen either on for
 * ever or off during a track, and the renderer has two protocols that can both
 * start and stop playback.
 */
class ScreenIdlePolicy(idleMillis: Long = DEFAULT_IDLE_MILLIS) {

    var idleMillis: Long = idleMillis
        set(value) {
            field = value.coerceIn(MIN_IDLE_MILLIS, MAX_IDLE_MILLIS)
        }

    /** When something last happened that should postpone blanking. */
    private var lastActivityAt: Long? = null

    /** True while the panel should be held on. */
    var keepScreenOn: Boolean = true
        private set

    /**
     * Advances the policy. Returns true when [keepScreenOn] changed, so the
     * caller only touches the window when there is something to change.
     */
    fun update(playing: Boolean, now: Long): Boolean {
        val since = lastActivityAt ?: now.also { lastActivityAt = it }
        // Playing is itself activity: a long album must not go dark mid-track.
        if (playing) lastActivityAt = now

        val wanted = playing || (now - since) < idleMillis
        val changed = wanted != keepScreenOn
        keepScreenOn = wanted
        return changed
    }

    /** Something happened that should postpone blanking. */
    fun noteActivity(now: Long) {
        lastActivityAt = now
        keepScreenOn = true
    }

    /** How long until the screen would blank, or null when it is staying on. */
    fun millisUntilBlank(now: Long): Long? {
        val since = lastActivityAt ?: return idleMillis
        return (idleMillis - (now - since)).takeIf { it > 0 }
    }

    companion object {
        /**
         * Five minutes. Long enough that a gap between albums does not blank
         * the screen in front of someone choosing the next one, short enough
         * that an appliance left alone spends its night dark.
         */
        const val DEFAULT_IDLE_MILLIS = 5 * 60_000L
        const val MIN_IDLE_MILLIS = 30_000L
        const val MAX_IDLE_MILLIS = 120 * 60_000L
    }
}
