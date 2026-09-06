package com.hifirend.upnp.openhome

import com.hifirend.RendererState
import com.hifirend.upnp.PlaybackController
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * What happens to a playlist when tracks will not play.
 *
 * Two failures look identical one track at a time and need opposite responses.
 * A single dead link in a long album should cost that track and nothing else --
 * stopping there is the controller-dependent behaviour OpenHome exists to get
 * away from. A source that has gone away fails *every* remaining track, and
 * skipping blindly would tear through the list in seconds and leave "stopped"
 * on screen with the reason long gone.
 *
 * Three in a row is what tells those apart.
 */
class OpenHomeSkipTest {

    /** Records what was asked for, and fails whichever URIs it is told to. */
    private class FakeEngine(val failing: Set<String> = emptySet()) : PlaybackController {
        val played = mutableListOf<String>()
        var stops = 0
        override fun play(uri: String, mimeType: String?): String {
            played += uri
            return if (uri in failing) """{"ok":false,"error":"not a decodable FLAC stream"}"""
            else """{"ok":true}"""
        }
        override fun playGapless(uri: String, mimeType: String?) = play(uri, mimeType)
        override fun stop() { stops++ }
        override fun pause() = Unit
        override fun resume() = Unit
        override fun seek(uri: String, seconds: Int, durationSeconds: Int) = """{"ok":true}"""
        override fun onTrackChanged() = Unit
        override fun positionSeconds() = 0
    }

    private fun listOf(vararg uris: String): OpenHomeTrackList {
        val list = OpenHomeTrackList()
        var after = 0
        for (u in uris) after = list.insert(after, u, "")!!
        return list
    }

    @Before
    fun reset() {
        // The rate guard is a different refusal path; keep it out of the way.
        RendererState.dacRates = emptyList()
        RendererState.lastError = null
        RendererState.lastErrorDetail = null
    }

    @Test
    fun `one bad track is stepped over and the playlist carries on`() {
        val engine = FakeEngine(failing = setOf("b"))
        val list = listOf("a", "b", "c")
        val pl = OpenHomePlaylist(list, engine)

        pl.playAction()
        assertEquals("a", engine.played.last())
        pl.onTrackFinished()          // a ends, b is tried and fails, c takes over

        assertEquals(kotlin.collections.listOf("a", "b", "c"), engine.played)
        assertEquals("Playing", pl.transportState)
        assertEquals("c", list.current()?.uri)
    }

    @Test
    fun `three failures in a row stop the playlist`() {
        val engine = FakeEngine(failing = setOf("a", "b", "c", "d", "e"))
        val pl = OpenHomePlaylist(listOf("a", "b", "c", "d", "e"), engine)

        pl.playAction()

        // Three tried, then it gives up -- it does not run to the end of a
        // playlist whose source has plainly gone.
        assertEquals(kotlin.collections.listOf("a", "b", "c"), engine.played)
        assertEquals("Stopped", pl.transportState)
    }

    @Test
    fun `giving up says it was three in a row, not that one file was bad`() {
        val engine = FakeEngine(failing = setOf("a", "b", "c"))
        OpenHomePlaylist(listOf("a", "b", "c"), engine).playAction()

        // The shape of the failure is the useful part: three consecutive
        // failures point at the source, where one points at a file.
        assertTrue(
            "headline was: ${RendererState.lastError}",
            RendererState.lastError!!.contains("3 tracks in a row"),
        )
        assertTrue(RendererState.lastErrorDetail != null)
    }

    @Test
    fun `a track that plays through clears the run of failures`() {
        // b and d fail, with a good track between them: two separate single
        // failures, never three in a row, so the playlist reaches the end.
        val engine = FakeEngine(failing = setOf("b", "d"))
        val list = listOf("a", "b", "c", "d", "e")
        val pl = OpenHomePlaylist(list, engine)

        pl.playAction()               // a
        pl.onTrackFinished()          // b fails -> c
        assertEquals("c", list.current()?.uri)
        pl.onTrackFinished()          // d fails -> e
        assertEquals("e", list.current()?.uri)
        assertEquals("Playing", pl.transportState)
    }

    @Test
    fun `reaching the end after a skip says so rather than ending silently`() {
        val engine = FakeEngine(failing = setOf("b"))
        val pl = OpenHomePlaylist(listOf("a", "b"), engine)

        pl.playAction()               // a
        pl.onTrackFinished()          // b fails, nothing after it

        assertEquals("Stopped", pl.transportState)
        assertTrue(
            "headline was: ${RendererState.lastError}",
            RendererState.lastError!!.contains("One track was skipped"),
        )
    }

    @Test
    fun `a successful start clears a problem left by an earlier track`() {
        val engine = FakeEngine(failing = setOf("a"))
        val pl = OpenHomePlaylist(listOf("a", "b"), engine)

        pl.playAction()               // a fails, b takes over
        assertEquals("Playing", pl.transportState)
        // A stale banner reappearing when this playlist later stops is exactly
        // the kind of misreporting the screen must never do.
        assertEquals(null, RendererState.lastError)
    }

    @Test
    fun `stopping clears the format badge but not which track it was`() {
        val engine = FakeEngine()
        val pl = OpenHomePlaylist(listOf("a", "b"), engine)

        pl.playAction()
        // Stand in for the engine having published a running stream.
        RendererState.sourceFormat = "FLAC"
        RendererState.sourceRate = 96000
        RendererState.sourceBits = 24
        RendererState.bitPerfect = true

        pl.stopAction()

        // The badge describes a running stream, and there is not one. Leaving
        // "FLAC 24/96 -- bit-perfect" up makes a claim about an idle DAC, which
        // is the one claim this app must not make loosely.
        assertEquals(null, RendererState.sourceFormat)
        assertEquals(0, RendererState.sourceRate)
        assertEquals(0, RendererState.sourceBits)
        assertEquals(false, RendererState.bitPerfect)
        // ...but the track it stopped on is still named, or a failure would
        // have nothing to point at.
        assertEquals("a", pl.list.current()?.uri)
    }

    @Test
    fun `pausing keeps the badge, because the stream is still open`() {
        val engine = FakeEngine()
        val pl = OpenHomePlaylist(listOf("a"), engine)

        pl.playAction()
        RendererState.sourceFormat = "FLAC"
        RendererState.bitPerfect = true

        pl.pauseAction()

        assertEquals("FLAC", RendererState.sourceFormat)
        assertTrue(RendererState.bitPerfect)
    }

    @Test
    fun `giving up after three failures also clears the badge`() {
        RendererState.sourceFormat = "FLAC"
        RendererState.bitPerfect = true
        val engine = FakeEngine(failing = setOf("a", "b", "c"))
        OpenHomePlaylist(listOf("a", "b", "c"), engine).playAction()

        assertEquals(null, RendererState.sourceFormat)
        assertEquals(false, RendererState.bitPerfect)
    }

    @Test
    fun `pressing skip forgives the failures that came before it`() {
        val engine = FakeEngine(failing = setOf("a", "b"))
        val list = listOf("a", "b", "c", "d")
        val pl = OpenHomePlaylist(list, engine)

        pl.playAction()               // a fails -> b fails -> c plays (2 failures)
        assertEquals("c", list.current()?.uri)

        // Two failures are already banked. Pressing next must not mean the
        // very next hiccup ends the playlist.
        pl.nextAction()               // -> d, plays
        assertEquals("Playing", pl.transportState)
        assertEquals("d", list.current()?.uri)
    }
}
