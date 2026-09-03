package com.hifirend.power

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
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
    private val handler = Handler(Looper.getMainLooper())
    private var idleTimeoutMs: Long = DEFAULT_IDLE_MS

    private val blank = Runnable {
        Log.i(TAG, "screen: idle timeout reached, releasing keep-awake")
        keepScreenOn = false
        onKeepScreenOnChanged?.invoke(false)
    }

    /** The activity observes this to add or clear FLAG_KEEP_SCREEN_ON. */
    @Volatile
    var keepScreenOn: Boolean = true
        private set

    @Volatile
    var onKeepScreenOnChanged: ((Boolean) -> Unit)? = null

    fun setIdleTimeoutMinutes(minutes: Int) {
        idleTimeoutMs = minutes.coerceIn(1, 120) * 60_000L
        restartIdleTimer()
    }

    /** Any activity that should postpone blanking. */
    fun noteActivity() {
        if (!keepScreenOn) {
            keepScreenOn = true
            onKeepScreenOnChanged?.invoke(true)
        }
        restartIdleTimer()
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

    private fun restartIdleTimer() {
        handler.removeCallbacks(blank)
        handler.postDelayed(blank, idleTimeoutMs)
    }

    fun shutdown() = handler.removeCallbacks(blank)

    companion object {
        const val EXTRA_TURN_SCREEN_ON = "turn_screen_on"
        private const val DEFAULT_IDLE_MS = 3 * 60_000L
    }
}
