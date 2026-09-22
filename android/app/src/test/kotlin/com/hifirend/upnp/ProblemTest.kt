package com.hifirend.upnp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That a failure is blamed on the right thing.
 *
 * This exists because of a real report: a playlist stopped on its second track
 * and the screen said *"This track is in a format the renderer cannot
 * decode."* The track was fine. The media server had dropped off the network,
 * and the decoder -- which cannot tell a vanished server from a corrupt file,
 * since both arrive as a stream that ends early -- reported the only thing it
 * could see. That message reached the user and sent them looking at their
 * library instead of their network.
 *
 * The fetch knows better, so the fetch's reason now wins. These pin that
 * ordering, because the decoder's wording still matches the format case and
 * would quietly take priority again if the branches were ever reordered.
 *
 * What is asserted is the *code*, not a sentence. The sentences live in
 * lib/l10n now, in ten languages, and a test that pinned the English one here
 * would fail on every rewording while proving nothing about the mapping --
 * which is the only thing this file exists to protect.
 */
class ProblemTest {

    @Test
    fun `an unreachable server is not reported as a format problem`() {
        val d = Problem.describe(
            "the media server could not be reached: Failed to connect to /192.168.100.41:57645")
        assertEquals(Problem.SERVER_UNREACHABLE, d.code)
        // The technical wording is kept for whoever walks over to the screen.
        assertTrue(d.detail!!.contains("192.168.100.41:57645"))
    }

    @Test
    fun `a server that stops responding is a server problem`() {
        assertEquals(
            Problem.SERVER_UNREACHABLE,
            Problem.describe("the media server stopped responding: timeout").code,
        )
    }

    @Test
    fun `an unresolvable host is a server problem`() {
        assertEquals(
            Problem.SERVER_UNREACHABLE,
            Problem.describe("the media server's address could not be resolved: nas.local").code,
        )
    }

    @Test
    fun `an HTTP error says the server refused it, not that the file is wrong`() {
        assertEquals(
            Problem.SERVER_REFUSED,
            Problem.describe("the server answered HTTP 404 for this track").code,
        )
    }

    @Test
    fun `a genuine format failure still reports as one`() {
        assertEquals(
            Problem.UNDECODABLE,
            Problem.describe("not a decodable FLAC stream").code,
        )
        assertEquals(
            Problem.UNDECODABLE,
            Problem.describe(
                "unsupported or unrecognised audio format (audio/L16;rate=44100)").code,
        )
    }

    @Test
    fun `a rate mismatch still blames neither the file nor the network`() {
        assertEquals(
            Problem.DAC_RATE_UNSUPPORTED,
            Problem.describe("no PCM alt-setting holds 24-bit 2ch at 96000 Hz").code,
        )
    }

    @Test
    fun `a USB failure still points at the DAC`() {
        assertEquals(
            Problem.DAC_LOST,
            Problem.describe("libusb: iso transfer submit failed").code,
        )
    }

    @Test
    fun `anything unrecognised stays honestly vague`() {
        assertEquals(
            Problem.UNKNOWN,
            Problem.describe("something nobody has seen before").code,
        )
    }

    private val al400 = listOf(44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 705600, 768000)

    @Test
    fun `an announced rate that is not a real rate is left to the decoder`() {
        // BubbleUPnP's Qobuz metadata said 44000; the FLAC said 44100.
        assertEquals(null, Problem.forAnnouncedRate(44000, al400))
        assertEquals(null, Problem.forAnnouncedRate(44000, listOf(44100, 48000)))
    }

    @Test
    fun `a rate above the DAC's ceiling says what the ceiling is`() {
        val d = Problem.forAnnouncedRate(192000, listOf(44100, 48000))!!
        assertEquals(Problem.RATE_UNPLAYABLE, d.code)
        assertEquals(listOf(192000, 48000), d.args)
    }

    @Test
    fun `a real rate the DAC skips is not reported as being above its ceiling`() {
        val d = Problem.forAnnouncedRate(88200, listOf(44100, 48000, 96000))!!
        assertEquals(Problem.RATE_NOT_OFFERED, d.code)
        assertEquals(listOf(88200), d.args)
    }

    @Test
    fun `offered rates, silence and unknown capabilities refuse nothing`() {
        assertEquals(null, Problem.forAnnouncedRate(44100, al400))
        assertEquals(null, Problem.forAnnouncedRate(0, al400))
        assertEquals(null, Problem.forAnnouncedRate(192000, emptyList()))
    }

    @Test
    fun `every rate audio is recorded at counts as real`() {
        for (hz in listOf(8000, 11025, 16000, 22050, 32000, 44100, 48000, 88200, 96000,
                176400, 192000, 352800, 384000, 705600, 768000, 2822400)) {
            assertTrue("$hz", Problem.isRealRate(hz))
        }
    }
}
