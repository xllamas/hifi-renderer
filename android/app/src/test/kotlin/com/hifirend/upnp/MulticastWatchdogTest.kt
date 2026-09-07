package com.hifirend.upnp

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The renderer goes undiscoverable while everything about it still works:
 * unicast M-SEARCH answered, description served, socket bound, group joined as
 * far as the phone can tell -- and multicast to that same socket never
 * delivered. Only rejoining the group cures it, and nothing can ask whether we
 * are still really in the group, so it is inferred from having stopped hearing
 * a network that was demonstrably noisy.
 */
class MulticastWatchdogTest {

    private val minute = 60_000L

    @Test
    fun `silence on a network we have heard means the membership lapsed`() {
        assertTrue(MulticastWatchdog.shouldHeal(
            lastHeardAt = 1L, lastHealAt = 0L, now = 1L + 5 * minute))
    }

    @Test
    fun `a network we have never heard is never healed`() {
        // Otherwise a renderer alone on a quiet network would rebind for ever
        // and be less reliable for being watched.
        assertFalse(MulticastWatchdog.shouldHeal(
            lastHeardAt = 0L, lastHealAt = 0L, now = 10 * 60 * minute))
    }

    @Test
    fun `a brief gap is not silence`() {
        assertFalse(MulticastWatchdog.shouldHeal(
            lastHeardAt = 1L, lastHealAt = 0L, now = 1L + 3 * minute))
    }

    @Test
    fun `it will not rebind again inside the backoff`() {
        val now = 100 * minute
        // Still silent, and nothing has arrived since the last rejoin -- so
        // that rejoin achieved nothing and repeating it would only keep moving
        // the stream server's port under every controller.
        assertFalse(MulticastWatchdog.shouldHeal(
            lastHeardAt = now - 5 * minute, lastHealAt = now - 2 * minute, now = now))
    }

    @Test
    fun `it tries again once the backoff has passed`() {
        val now = 100 * minute
        assertTrue(MulticastWatchdog.shouldHeal(
            lastHeardAt = now - 5 * minute, lastHealAt = now - 11 * minute, now = now))
    }

    @Test
    fun `a rejoin that worked does not hold off the next fault`() {
        // The 2026-09-07 case, in the numbers it actually happened in: a lapse
        // healed at 09:05, multicast back immediately after, a fresh lapse
        // beginning at 09:08 and still unhealed at 09:11. Under a flat
        // ten-minute backoff this stayed false until 09:15 and the renderer
        // was undiscoverable for six and a half minutes.
        val heal = 0L
        val heardAgain = heal + 20_000L        // the rejoin worked
        val now = heal + 6 * minute            // three minutes into the new lapse
        assertTrue(MulticastWatchdog.shouldHeal(
            lastHeardAt = heardAgain, lastHealAt = heal, now = now, heardCount = 456L))
    }

    @Test
    fun `a rejoin that achieved nothing still serves the full backoff`() {
        // Same three minutes elapsed, but nothing arrived after the rejoin, so
        // rejoining again is not the cure and the loop guard stands.
        val heal = 10 * minute
        val now = heal + 3 * minute
        assertFalse(MulticastWatchdog.shouldHeal(
            lastHeardAt = heal - 90_000L, lastHealAt = heal, now = now,
            heardCount = 456L))
    }

    @Test
    fun `even a rejoin that worked is not repeated straight away`() {
        // Multicast that merely trickles -- a gap past the window, one packet,
        // another gap -- would otherwise rebind on every gap, and a port that
        // moves constantly is worse for controllers than being slow to find.
        val heal = 10 * minute
        val heardAgain = heal + 5_000L
        val now = heal + 100_000L
        assertFalse(MulticastWatchdog.shouldHeal(
            lastHeardAt = heardAgain, lastHealAt = heal, now = now,
            heardCount = 456L))
        // ...but two minutes on, a network this noisy being silent for over a
        // minute is the fault again, and it is treated as one.
        assertTrue(MulticastWatchdog.shouldHeal(
            lastHeardAt = heardAgain, lastHealAt = heal, now = heal + 130_000L,
            heardCount = 456L))
    }

    @Test
    fun `hearing multicast again cancels the concern`() {
        val now = 100 * minute
        assertFalse(MulticastWatchdog.shouldHeal(
            lastHeardAt = now - 10_000L, lastHealAt = 0L, now = now))
    }

    @Test
    fun `a busy network is judged deaf sooner`() {
        val now = 100 * minute
        // Two minutes' silence on a network that produces more than one
        // announcement a second is not a quiet patch.
        assertTrue(MulticastWatchdog.shouldHeal(
            lastHeardAt = now - 2 * minute, lastHealAt = 0L, now = now,
            heardCount = 3000L))
        // The same silence on a network we have barely heard from is not yet
        // evidence of anything.
        assertFalse(MulticastWatchdog.shouldHeal(
            lastHeardAt = now - 2 * minute, lastHealAt = 0L, now = now,
            heardCount = 3L))
    }

    @Test
    fun `even a busy network gets a grace period`() {
        val now = 100 * minute
        assertFalse(MulticastWatchdog.shouldHeal(
            lastHeardAt = now - 60_000L, lastHealAt = 0L, now = now,
            heardCount = 3000L))
    }

    @Test
    fun `a quiet network still waits the full window`() {
        val now = 100 * minute
        assertFalse(MulticastWatchdog.shouldHeal(
            lastHeardAt = now - 3 * minute, lastHealAt = 0L, now = now,
            heardCount = 5L))
        assertTrue(MulticastWatchdog.shouldHeal(
            lastHeardAt = now - 5 * minute, lastHealAt = 0L, now = now,
            heardCount = 5L))
    }
}
