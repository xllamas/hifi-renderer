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
 */
class ProblemTest {

    @Test
    fun `an unreachable server is not reported as a format problem`() {
        val d = Problem.describe(
            "the media server could not be reached: Failed to connect to /192.168.100.41:57645")
        assertEquals("The renderer lost contact with the media server.", d.headline)
        // The technical wording is kept for whoever walks over to the screen.
        assertTrue(d.detail!!.contains("192.168.100.41:57645"))
    }

    @Test
    fun `a server that stops responding is a server problem`() {
        assertEquals(
            "The renderer lost contact with the media server.",
            Problem.describe("the media server stopped responding: timeout").headline,
        )
    }

    @Test
    fun `an unresolvable host is a server problem`() {
        assertEquals(
            "The renderer lost contact with the media server.",
            Problem.describe("the media server's address could not be resolved: nas.local").headline,
        )
    }

    @Test
    fun `an HTTP error says the server refused it, not that the file is wrong`() {
        assertEquals(
            "The media server refused this track.",
            Problem.describe("the server answered HTTP 404 for this track").headline,
        )
    }

    @Test
    fun `a genuine format failure still reports as one`() {
        assertEquals(
            "This track is in a format the renderer cannot decode.",
            Problem.describe("not a decodable FLAC stream").headline,
        )
        assertEquals(
            "This track is in a format the renderer cannot decode.",
            Problem.describe(
                "unsupported or unrecognised audio format (audio/L16;rate=44100)").headline,
        )
    }

    @Test
    fun `a rate mismatch still blames neither the file nor the network`() {
        assertEquals(
            "This DAC cannot be set to this track's rate or bit depth.",
            Problem.describe("no PCM alt-setting holds 24-bit 2ch at 96000 Hz").headline,
        )
    }

    @Test
    fun `a USB failure still points at the DAC`() {
        assertEquals(
            "The renderer lost its connection to the DAC.",
            Problem.describe("libusb: iso transfer submit failed").headline,
        )
    }

    @Test
    fun `anything unrecognised stays honestly vague`() {
        assertEquals(
            "This track could not be played.",
            Problem.describe("something nobody has seen before").headline,
        )
    }
}
