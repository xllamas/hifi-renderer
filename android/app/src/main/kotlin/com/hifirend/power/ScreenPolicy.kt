package com.hifirend.power

import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.util.Log
import com.hifirend.MainActivity

private const val TAG = "hifirend"

/**
 * The spec's screen behaviour: blank after a few minutes of inactivity, and
 * wake when playback starts.
 *
 * A dedicated renderer sits idle for hours, so leaving the panel lit wastes
 * power and burns OLED. Waking on playback is what makes it feel like an
 * appliance -- the now-playing screen appears when the music does.
 *
 * This is display policy only. The CPU is kept awake separately by the
 * playback wake lock, because a suspended process cannot meet isochronous
 * deadlines.
 */
class ScreenPolicy(private val context: Context) {

    private val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    private val policy = ScreenIdlePolicy()

    /**
     * Driven from the service's existing 500 ms tick rather than a timer of
     * its own.
     *
     * That tick already knows whether anything is playing, whichever protocol
     * is driving, so there is one place that cannot disagree with the screen.
     * The previous design posted a delayed Runnable when playback *started*
     * and never refreshed it, which blanked the panel three minutes into every
     * album.
     */
    fun tick(playing: Boolean, now: Long = System.currentTimeMillis()) {
        if (policy.update(playing, now)) {
            Log.i(TAG, if (policy.keepScreenOn) "screen: holding the panel on"
                       else "screen: idle timeout reached, letting the panel sleep")
            ScreenState.keepScreenOn = policy.keepScreenOn
        }
    }

    fun setIdleTimeoutMinutes(minutes: Int) {
        policy.idleMillis = minutes * 60_000L
    }

    val idleTimeoutMinutes: Int
        get() = (policy.idleMillis / 60_000L).toInt()

    /**
     * Any activity that should postpone blanking.
     *
     * Logged on the transition only, and only when it is one: this runs on
     * every track, and a line per track would bury the thing it is there to
     * show. The silence when the panel came back on cost a diagnosis once
     * already -- the screen re-lighting looked unexplained until the *audio*
     * log gave it away.
     */
    fun noteActivity() {
        val wasOn = policy.keepScreenOn
        policy.noteActivity(System.currentTimeMillis())
        if (!wasOn) {
            Log.i(TAG, "screen: activity, holding the panel on again")
            ScreenState.keepScreenOn = true
        }
    }

    /**
     * Playback started: wake the screen and show the now-playing view.
     *
     * setTurnScreenOn/setShowWhenLocked on the activity is the supported route
     * from API 27; the deprecated wake lock is the fallback for API 26, which
     * is this app's floor.
     */
    fun wakeForPlayback() {
        noteActivity()
        if (powerManager.isInteractive) return

        Log.i(TAG, "screen: waking for playback")
        try {
            context.startActivity(
                Intent(context, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    putExtra(EXTRA_TURN_SCREEN_ON, true)
                }
            )
        } catch (e: Throwable) {
            Log.w(TAG, "screen: could not launch activity to wake: ${e.message}")
        }

        if (android.os.Build.VERSION.SDK_INT < 27) {
            @Suppress("DEPRECATION")
            powerManager.newWakeLock(
                PowerManager.FULL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "hifirend:wake",
            ).acquire(3_000)
        }
    }

    /** Leaves the panel on: a renderer that has stopped must not go dark mid-teardown. */
    fun shutdown() {
        ScreenState.keepScreenOn = true
    }

    companion object {
        const val EXTRA_TURN_SCREEN_ON = "turn_screen_on"
    }
}
