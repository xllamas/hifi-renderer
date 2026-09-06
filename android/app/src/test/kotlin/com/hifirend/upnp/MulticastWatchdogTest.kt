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
        // Still silent, but it has just rebound; the rebind changes the stream
        // server's port, so repeating it would keep pulling the rug from under
        // every controller.
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
    fun `hearing multicast again cancels the concern`() {
        val now = 100 * minute
        assertFalse(MulticastWatchdog.shouldHeal(
            lastHeardAt = now - 10_000L, lastHealAt = 0L, now = now))
    }
}
