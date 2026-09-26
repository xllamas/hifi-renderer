package com.hifirend.upnp

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SinkFormatsTest {

    @Test
    fun `DSD is only offered to a DAC that can clock DoP at 176 kHz`() {
        assertTrue(SinkFormats.canCarryDop(listOf(44100, 48000, 176400, 192000)))
        assertTrue(SinkFormats.canCarryDop(listOf(768000)))
    }

    @Test
    fun `a DAC that stops at 96 kHz, or one not read yet, is not offered DSD`() {
        assertFalse(SinkFormats.canCarryDop(listOf(44100, 48000, 88200, 96000)))
        assertFalse(SinkFormats.canCarryDop(emptyList()))
    }
}
