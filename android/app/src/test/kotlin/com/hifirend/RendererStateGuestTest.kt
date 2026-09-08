package com.hifirend

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * What the screen must forget when a guest takes the output, and what it must
 * not.
 *
 * A guest arriving over AirPlay is the one handover where every field on the
 * now-playing screen belongs to somebody else. The owner's track is still in
 * [RendererState] -- the playlist stops but deliberately remembers what it
 * stopped on, so a failure has something to point at -- and the fidelity
 * fields describe a stream that has just been replaced. Publishing the guest's
 * stream over the top of that, field by field, is how a screen ends up
 * confidently describing music nobody is playing.
 */
class RendererStateGuestTest {

    /** The state is a singleton, so each test starts from a known screen. */
    @Before
    fun reset() {
        RendererState.clearTrack()
        RendererState.transportState = "STOPPED"
    }

    private fun ownerPlayingLocalFlac() {
        RendererState.title = "First — Redbook"
        RendererState.artist = "Test Signals"
        RendererState.album = "OpenHome Playlist"
        RendererState.albumArtUri = "http://192.168.100.134:8900/cover.png"
        RendererState.durationSeconds = 30
        RendererState.positionSeconds = 10
        RendererState.transportState = "PLAYING"
        RendererState.sourceFormat = "FLAC"
        RendererState.sourceRate = 44100
        RendererState.sourceBits = 16
        RendererState.bitPerfect = true
        RendererState.senderAltered = false
    }

    @Test
    fun `clearing the track clears the fidelity claim with it`() {
        // The coupling that makes ordering matter where a guest session is
        // published: clearTrack() reaches clearFormat(), so anything written
        // before it -- the guest's format, and above all its bit-perfect
        // answer -- is thrown away. Publishing the guest's stream and *then*
        // clearing the owner's track would leave the screen with no badge and
        // no explanation, which is the state this whole path exists to end.
        ownerPlayingLocalFlac()
        RendererState.clearTrack()

        assertNull(RendererState.title)
        assertNull(RendererState.sourceFormat)
        assertFalse(RendererState.bitPerfect)
        assertFalse(RendererState.senderAltered)
        assertEquals(0, RendererState.sourceRate)
    }

    @Test
    fun `a guest's stream carries none of the owner's track`() {
        // Observed on the Redmi 2026-09-08: a guest streaming while the screen
        // still read "Third — 96/24 / Test Signals / OpenHome Playlist" with
        // the owner's cover art. Worse than the bit-perfect tick it replaced --
        // that overstated quality, this names a specific track that is not
        // playing.
        ownerPlayingLocalFlac()

        // The order publishGuestStream() uses: forget the owner first, then
        // describe the guest.
        RendererState.clearTrack()
        RendererState.transportState = "PLAYING"
        RendererState.sourceFormat = "ALAC"
        RendererState.sourceRate = 44100
        RendererState.sourceBits = 16
        RendererState.channels = 2
        RendererState.bitPerfect = false
        RendererState.senderAltered = true

        assertNull("the owner's title must not label a guest's stream",
            RendererState.title)
        assertNull(RendererState.artist)
        assertNull(RendererState.album)
        assertNull("cover art is the most confident lie of the set",
            RendererState.albumArtUri)
        assertEquals("a guest's stream has no duration we know of",
            0, RendererState.durationSeconds)

        // ...and the guest's own description survived the clearing.
        assertEquals("ALAC 16/44.1", RendererState.formatBadge())
        assertFalse(RendererState.bitPerfect)
        assertTrue(RendererState.senderAltered)
    }

    @Test
    fun `the published status tells the screen both halves`() {
        // bitPerfect false alone is ambiguous -- it is equally the fallback
        // output and nothing playing. The screen needs senderAltered to say
        // which, so both must reach it.
        RendererState.clearTrack()
        RendererState.sourceFormat = "ALAC"
        RendererState.sourceRate = 44100
        RendererState.sourceBits = 16
        RendererState.bitPerfect = false
        RendererState.senderAltered = true
        RendererState.output = "usb"

        val json = RendererState.toJson()
        assertTrue(json.contains("\"bitPerfect\":false"))
        assertTrue(json.contains("\"senderAltered\":true"))
        // Not the fallback: the DAC really is carrying this.
        assertTrue(json.contains("\"output\":\"usb\""))
    }
}
