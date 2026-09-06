package com.hifirend.power

import android.content.Context

/**
 * How long the renderer stays lit once the music stops.
 *
 * Kept in preferences rather than as a constant because the right answer is a
 * property of the room, not of the app: a phone on a shelf across a listening
 * room wants to go dark quickly, one sitting on a desk being used as a display
 * wants to stay up. The service reads this at startup and whenever it changes.
 *
 * "Never" is offered and is a real choice for a phone that is permanently
 * powered — but it is the user's to make, not a default, because an OLED panel
 * left showing the same now-playing screen for months is how it acquires a
 * permanent one.
 */
object ScreenTimeout {

    private const val PREFS = "hifirend_upnp"
    private const val KEY = "screen_idle_minutes"

    /** Matches ScreenIdlePolicy's default. */
    const val DEFAULT_MINUTES = 5

    /** The value meaning "hold the screen on for ever". */
    const val NEVER = 0

    /** What the settings screen offers; minutes, with 0 for never. */
    val CHOICES = listOf(1, 2, 5, 10, 30, NEVER)

    fun minutes(context: Context): Int =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getInt(KEY, DEFAULT_MINUTES)

    fun setMinutes(context: Context, minutes: Int) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putInt(KEY, minutes).apply()
    }

    /** Plain wording for the screen, so the UI and the app agree on it. */
    fun describe(minutes: Int): String = when (minutes) {
        NEVER -> "Never"
        1 -> "1 minute"
        else -> "$minutes minutes"
    }
}
