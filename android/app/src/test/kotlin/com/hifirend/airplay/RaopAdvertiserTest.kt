package com.hifirend.airplay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The TXT record is a set of promises, and the only test that matters is
 * whether the receiver keeps them.
 *
 * It is the whole capability negotiation: a sender reads it and decides what
 * to send before a word of RTSP is spoken, so a field claiming something not
 * implemented does not fail cleanly -- the sender simply sends it, and the
 * receiver discards it or chokes on it. Nothing in the code fails when the
 * record drifts from what the code does, which is exactly why it drifted:
 * checked against shairport-sync on 2026-09-08, `ek` was documented in the
 * KDoc and never sent, and `md` claimed artwork support this receiver does not
 * have.
 */
class RaopAdvertiserTest {

    private val txt = RaopAdvertiser.txtRecords()

    @Test
    fun `announces the one format AirPlay 1 carries`() {
        assertEquals("2", txt["ch"])
        assertEquals("16", txt["ss"])
        assertEquals("44100", txt["sr"])
        assertEquals("1", txt["txtvers"])
    }

    @Test
    fun `claims only the codecs that are implemented`() {
        // 0 is PCM and 1 is ALAC, both of which the ALAC path handles. The AAC
        // variants would be sent if claimed, and nothing here decodes them.
        assertEquals("0,1", txt["cn"])
    }

    @Test
    fun `claims only the metadata that is acted on`() {
        // 0 text, 1 artwork, 2 progress. Artwork must stay out: every JPEG a
        // sender pushes for a picture nothing displays is bandwidth spent on
        // the guest path for nothing, and it is the same rule the codec list
        // follows. shairport-sync advertises 0,2 for the same reason.
        assertEquals("0,2", txt["md"])
        assertFalse("artwork is not implemented and must not be claimed",
            txt["md"]!!.split(",").contains("1"))
    }

    @Test
    fun `says a key is present, because AirPlay 1 audio is encrypted`() {
        // Documented in this class from the beginning and never actually sent
        // until the shairport-sync comparison found it missing.
        assertEquals("1", txt["ek"])
        assertEquals("0,1", txt["et"])
    }

    @Test
    fun `does not claim a transport it has not implemented`() {
        // shairport-sync advertises TCP,UDP. Only the UDP path exists here, and
        // a sender that took us at our word on TCP would find nothing
        // listening.
        assertEquals("UDP", txt["tp"])
    }

    @Test
    fun `the instance name carries the hardware prefix senders parse`() {
        // Senders read the twelve hex digits before the @ as a hardware
        // address, and some refuse a name without one. Derived from the UDN
        // because Android no longer hands out a real MAC.
        //
        // The argument is what jUPnP's UDN.toString() actually returns, prefix
        // and all -- not the bare UUID. That matters more than it looks: `d`
        // is a hex digit, so the "uui[d]:" prefix contributes the *leading*
        // digit, and this receiver has been on the network as D24CA6786B69
        // rather than the 24CA6786B69B the bare UUID would give. Accidental,
        // but now load-bearing: tidying the prefix away would change the
        // hardware address, and a sender that remembers receivers by it would
        // see a different device.
        val udn = "uuid:24ca6786-b69b-4b55-b2a7-5a9c53e1fa1c"
        assertEquals("D24CA6786B69", RaopAdvertiser.hardwareId(udn))
        assertEquals(12, RaopAdvertiser.hardwareId(udn).length)
        assertTrue(RaopAdvertiser.hardwareId(udn).all { it in '0'..'9' || it in 'A'..'F' })
        assertEquals(6, RaopAdvertiser.hardwareAddressBytes(udn).size)
    }

    @Test
    fun `a UDN too short to fill the prefix is padded rather than truncated`() {
        // A short or hex-poor UDN must still yield twelve digits: a sender
        // parsing a shorter prefix rejects the session outright.
        assertEquals(12, RaopAdvertiser.hardwareId("ab").length)
        assertEquals("AB0000000000", RaopAdvertiser.hardwareId("ab"))
        assertEquals(12, RaopAdvertiser.hardwareId("").length)
    }
}
