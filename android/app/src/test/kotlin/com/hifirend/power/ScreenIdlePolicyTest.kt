package com.hifirend.power

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * When the panel is held on, and when it is let go.
 *
 * Worth testing off-device because both failure modes are slow and quiet. The
 * previous implementation blanked the screen three minutes into every album,
 * which only shows if you watch a long track to its end; and its idle timeout
 * fired into a listener nothing had registered, which shows as a screen that
 * simply never turns off. Neither is something a quick manual check catches.
 */
class ScreenIdlePolicyTest {

    private val minute = 60_000L

    @Test
    fun `playing holds the panel on however long the track runs`() {
        val p = ScreenIdlePolicy()
        var t = 0L
        p.update(playing = true, now = t)
        // A twenty-minute side of vinyl must not go dark halfway through.
        repeat(20) {
            t += minute
            p.update(playing = true, now = t)
        }
        assertTrue(p.keepScreenOn)
    }

    @Test
    fun `the countdown starts when playback stops, not when it started`() {
        val p = ScreenIdlePolicy()
        var t = 0L
        repeat(10) { t += minute; p.update(playing = true, now = t) }
        assertTrue(p.keepScreenOn)

        t += 4 * minute
        p.update(playing = false, now = t)
        assertTrue("four minutes quiet is not yet five", p.keepScreenOn)

        t += 2 * minute
        p.update(playing = false, now = t)
        assertFalse(p.keepScreenOn)
    }

    @Test
    fun `the default is five minutes`() {
        assertEquals(5 * minute, ScreenIdlePolicy().idleMillis)
    }

    @Test
    fun `update reports only actual changes, so the window is left alone`() {
        val p = ScreenIdlePolicy()
        var t = 0L
        assertFalse("first tick already matches the default", p.update(false, t))

        t += 6 * minute
        assertTrue("blanking is a change", p.update(false, t))
        t += minute
        assertFalse("staying blanked is not", p.update(false, t))

        t += minute
        assertTrue("playing again is a change", p.update(true, t))
        t += minute
        assertFalse("still playing is not", p.update(true, t))
    }

    @Test
    fun `playback starting wakes the panel from an idle blank`() {
        val p = ScreenIdlePolicy()
        var t = 0L
        // The first tick seeds the deadline, so the countdown runs from when
        // the renderer came up rather than from the epoch.
        p.update(playing = false, now = t)
        t += 6 * minute
        p.update(playing = false, now = t)
        assertFalse(p.keepScreenOn)

        p.update(playing = true, now = t + 1)
        assertTrue(p.keepScreenOn)
    }

    @Test
    fun `a renderer that has just started keeps its screen on for the timeout`() {
        // Someone has just plugged it in and is looking at it; blanking
        // immediately because nothing has played yet would be wrong.
        val p = ScreenIdlePolicy()
        p.update(playing = false, now = 1_000_000L)
        assertTrue(p.keepScreenOn)
        p.update(playing = false, now = 1_000_000L + 4 * minute)
        assertTrue(p.keepScreenOn)
        p.update(playing = false, now = 1_000_000L + 6 * minute)
        assertFalse(p.keepScreenOn)
    }

    @Test
    fun `a gap between albums shorter than the timeout does not blank`() {
        val p = ScreenIdlePolicy()
        var t = 0L
        p.update(playing = true, now = t)
        t += 3 * minute                       // choosing the next record
        p.update(playing = false, now = t)
        assertTrue(p.keepScreenOn)
        p.update(playing = true, now = t + 1)
        assertTrue(p.keepScreenOn)
    }

    @Test
    fun `noteActivity postpones blanking`() {
        val p = ScreenIdlePolicy()
        var t = 0L
        t += 4 * minute
        p.noteActivity(t)
        t += 4 * minute                       // eight total, four since activity
        p.update(playing = false, now = t)
        assertTrue(p.keepScreenOn)
    }

    @Test
    fun `the timeout is configurable and clamped to something sane`() {
        val p = ScreenIdlePolicy()
        p.idleMillis = 20 * minute
        assertEquals(20 * minute, p.idleMillis)
        // Zero would blank the panel while music was playing.
        p.idleMillis = 0
        assertEquals(ScreenIdlePolicy.MIN_IDLE_MILLIS, p.idleMillis)
        p.idleMillis = 999 * minute
        assertEquals(ScreenIdlePolicy.MAX_IDLE_MILLIS, p.idleMillis)
    }

    @Test
    fun `millisUntilBlank counts down and reads null once it has blanked`() {
        val p = ScreenIdlePolicy()
        p.update(playing = false, now = 0)
        assertEquals(5 * minute, p.millisUntilBlank(0))
        assertEquals(2 * minute, p.millisUntilBlank(3 * minute))
        assertEquals(null, p.millisUntilBlank(6 * minute))
    }
}
