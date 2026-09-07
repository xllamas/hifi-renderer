package com.hifirend.airplay

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The field order, which is the whole risk here.
 *
 * A transposition in these eleven numbers does not fail -- it configures the
 * decoder wrongly and produces noise, which is then blamed on the decoder, the
 * decryption, or the network. Pinning the mapping against the line a real
 * sender actually sends is the cheapest insurance available.
 */
class RaopFormatTest {

    /** Exactly what macOS announced on 2026-09-07. */
    private val real = "96 352 0 16 40 10 14 2 255 0 0 44100"

    @Test
    fun `each field comes from the position it actually occupies`() {
        val f = RaopFormat.parse(real)
        assertEquals(352, f.frameLength)
        assertEquals(0, f.compatibleVersion)
        assertEquals(16, f.bitDepth)
        assertEquals(40, f.pb)
        assertEquals(10, f.mb)
        assertEquals(14, f.kb)
        assertEquals(2, f.channels)
        assertEquals(255, f.maxRun)
        assertEquals(0, f.maxFrameBytes)
        assertEquals(0, f.avgBitRate)
        assertEquals(44100, f.sampleRate)
    }

    @Test
    fun `the leading payload type is not mistaken for a field`() {
        // 96 is the RTP payload type, not frameLength. Off-by-one here shifts
        // every subsequent field.
        assertEquals(352, RaopFormat.parse(real).frameLength)
    }

    @Test
    fun `a mangled line falls back rather than refusing the guest`() {
        // The TXT record already promised 44.1/16 stereo, and the defaults are
        // that. Refusing would turn a cosmetic disagreement into a guest who
        // cannot play anything.
        assertEquals(RaopFormat.DEFAULT, RaopFormat.parse(""))
        assertEquals(RaopFormat.DEFAULT, RaopFormat.parse("96 352 0"))
        assertEquals(RaopFormat.DEFAULT, RaopFormat.parse("nonsense"))
    }

    @Test
    fun `extra whitespace is tolerated`() {
        assertEquals(352, RaopFormat.parse("  96   352 0 16 40 10 14 2 255 0 0 44100 ").frameLength)
    }

    @Test
    fun `the default is the only format AirPlay 1 carries`() {
        val d = RaopFormat.DEFAULT
        assertEquals(44100, d.sampleRate)
        assertEquals(16, d.bitDepth)
        assertEquals(2, d.channels)
    }
}
