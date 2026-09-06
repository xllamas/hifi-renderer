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
     * The service's own hold on the display, independent of any window.
     *
     * The activity's FLAG_KEEP_SCREEN_ON only works while an activity exists,
     * and on this appliance it frequently does not: the renderer plays for
     * hours with no UI, and the screen policy then had nothing to act through.
     * A wake lock held by the foreground service does not care whether a
     * window is up.
     *
     * It is also the only wake that survives MIUI. Waking by starting the
     * activity is a background activity start, which MIUI gates behind
     * "Display pop-up windows while running in the background" -- observed
     * being refused on the test phone, which is exactly why playback started
     * into a dark screen. A wake lock is not subject to that.
     *
     * SCREEN_BRIGHT_WAKE_LOCK is deprecated in favour of the window flag, and
     * the window flag is the thing that does not work here.
     */
    @Volatile
    private var screenLock: PowerManager.WakeLock? = null

    /**
     * Observed, not inferred: the screen was dark while music was playing.
     *
     * Android disables a screen wake lock held by a process with no visible
     * window, and a vendor may refuse the background activity start that would
     * give it one -- so whether waking works cannot be decided from the make
     * of the phone or from any permission we can query. It can only be
     * watched. This is what lets the settings screen say the permission is
     * needed *because it was seen failing*, rather than warning everybody.
     */
    @Volatile
    var wakeRefused: Boolean = false
        private set

    private var darkWhilePlayingTicks = 0

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
        // "Never" is a setting, not a very long timeout: the panel is simply
        // held, and no amount of idling releases it.
        if (holdForever) {
            if (screenLock?.isHeld != true) applyKeepScreenOn(true)
            return
        }
        if (policy.update(playing, now)) {
            Log.i(TAG, if (policy.keepScreenOn) "screen: holding the panel on"
                       else "screen: idle timeout reached, letting the panel sleep")
        }
        // Reconciled every tick rather than only on a change. "Changed" never
        // reports the *initial* state, so acting on it alone meant the very
        // first hold -- the one covering a freshly started renderer -- was
        // never applied and no lock was ever taken. Both calls below no-op
        // when reality already matches.
        applyKeepScreenOn(policy.keepScreenOn)
        watchForARefusedWake(playing)
    }

    /**
     * Music playing into a dark screen is the whole symptom, so that is what
     * is watched for. Ten ticks is five seconds -- long enough to sit out the
     * wake transition, short enough to catch the first track.
     */
    private fun watchForARefusedWake(playing: Boolean) {
        if (!playing || !policy.keepScreenOn) {
            darkWhilePlayingTicks = 0
            return
        }
        if (powerManager.isInteractive) {
            darkWhilePlayingTicks = 0
            return
        }
        darkWhilePlayingTicks++
        if (darkWhilePlayingTicks == 10 && !wakeRefused) {
            wakeRefused = true
            Log.w(TAG, "screen: playing but the panel stayed dark -- the vendor " +
                "refused the background activity start, so the now-playing " +
                "screen cannot come forward")
        }
    }

    /**
     * Applies the decision both ways it can be applied: the window flag when a
     * UI happens to exist, and the service's own wake lock, which works when
     * one does not.
     */
    private fun applyKeepScreenOn(on: Boolean, causeWakeup: Boolean = false) {
        if (ScreenState.keepScreenOn != on) ScreenState.keepScreenOn = on
        if (on) acquireScreenLock(causeWakeup) else releaseScreenLock()
    }

    @Synchronized
    private fun acquireScreenLock(causeWakeup: Boolean) {
        // Already holding one is the common case on every tick; re-acquiring
        // would leak a lock per tick.
        if (screenLock?.isHeld == true && !causeWakeup) return
        releaseScreenLock()
        val flags = PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
            if (causeWakeup) PowerManager.ACQUIRE_CAUSES_WAKEUP else 0
        try {
            @Suppress("DEPRECATION")
            screenLock = powerManager.newWakeLock(flags, "hifirend:screen").apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (e: Throwable) {
            Log.w(TAG, "screen: could not hold the display: ${e.message}")
            screenLock = null
        }
    }

    @Synchronized
    private fun releaseScreenLock() {
        screenLock?.let { lock -> runCatching { if (lock.isHeld) lock.release() } }
        screenLock = null
    }

    @Volatile
    private var holdForever = false

    /** [ScreenTimeout.NEVER] holds the panel on; anything else is minutes. */
    fun setIdleTimeoutMinutes(minutes: Int) {
        holdForever = minutes == ScreenTimeout.NEVER
        if (holdForever) {
            Log.i(TAG, "screen: set to stay on")
            applyKeepScreenOn(true)
            policy.noteActivity(System.currentTimeMillis())
        } else {
            policy.idleMillis = minutes * 60_000L
            // Start the countdown from the change, not from whenever the last
            // track ended, or shortening the timeout could blank the panel
            // under the hand of the person who just changed it.
            policy.noteActivity(System.currentTimeMillis())
            Log.i(TAG, "screen: idle timeout set to $minutes minute(s)")
        }
    }

    val idleTimeoutMinutes: Int
        get() = if (holdForever) ScreenTimeout.NEVER else (policy.idleMillis / 60_000L).toInt()

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
            applyKeepScreenOn(true)
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
        val wasAsleep = !powerManager.isInteractive
        policy.noteActivity(System.currentTimeMillis())
        if (!wasAsleep) {
            applyKeepScreenOn(true)
            return
        }

        Log.i(TAG, "screen: waking for playback")
        // The wake lock first, and unconditionally. It is what actually turns
        // the panel on, and unlike the activity launch below nothing can
        // refuse it.
        applyKeepScreenOn(true, causeWakeup = true)

        // Then try to bring the now-playing screen to the front, so what
        // lights up is the track rather than a lock screen. This is a
        // background activity start and may well be refused -- MIUI gates it
        // behind a permission that is off by default -- so it is the bonus,
        // not the mechanism.
        try {
            context.startActivity(
                Intent(context, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    putExtra(EXTRA_TURN_SCREEN_ON, true)
                }
            )
        } catch (e: Throwable) {
            Log.w(TAG, "screen: could not bring the UI forward (the panel is lit anyway): " +
                "${e.message}")
        }
    }

    /** Leaves the panel on: a renderer that has stopped must not go dark mid-teardown. */
    fun shutdown() {
        ScreenState.keepScreenOn = true
        releaseScreenLock()
    }

    companion object {
        const val EXTRA_TURN_SCREEN_ON = "turn_screen_on"
    }
}
