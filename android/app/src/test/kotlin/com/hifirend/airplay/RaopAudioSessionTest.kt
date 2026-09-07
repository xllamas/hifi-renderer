package com.hifirend.airplay

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * The two rules in the audio path that are wrong-by-default.
 *
 * Both corrupt audio rather than failing: a resend packet parsed as ordinary
 * audio feeds four bytes of the wrong header to the decoder, and treating the
 * unencrypted tail as ciphertext mangles the last samples of every single
 * frame. Neither announces itself -- they arrive as noise, blamed on the
 * decoder -- so both are settled here.
 */
class RaopAudioSessionTest {

    private val key = ByteArray(16) { it.toByte() }
    private val iv = ByteArray(16) { (16 - it).toByte() }

    private fun session(onFrame: (ByteArray, Int) -> Unit = { _, _ -> }) =
        RaopAudioSession(key, iv, onFrame)

    private fun rtp(payloadType: Int, payload: ByteArray, extra: Int = 0): ByteArray {
        val header = ByteArray(12 + extra)
        header[0] = 0x80.toByte()
        header[1] = payloadType.toByte()
        return header + payload
    }

    @Test
    fun `an ordinary audio packet loses exactly its twelve byte header`() {
        val payload = ByteArray(64) { it.toByte() }
        val packet = rtp(0x60, payload)
        val out = session().rtpPayload(packet, packet.size)!!
        assertArrayEquals(payload, out)
    }

    @Test
    fun `a retransmit carries four bytes of its own before the audio`() {
        // Parsed as ordinary audio this hands the decoder four bytes of resend
        // header as though they were samples -- a burst of noise, not an error.
        val payload = ByteArray(32) { (it + 1).toByte() }
        val packet = rtp(0x56, payload, extra = 4)
        val out = session().rtpPayload(packet, packet.size)!!
        assertArrayEquals(payload, out)
    }

    @Test
    fun `the marker bit does not change the payload type`() {
        // The first packet of a stream arrives as 0xE0: marker set, type 0x60.
        // Masking it off is what stops the stream being ignored from its very
        // first packet.
        val payload = ByteArray(16)
        val packet = rtp(0xE0, payload)
        assertEquals(16, session().rtpPayload(packet, packet.size)!!.size)
    }

    @Test
    fun `anything that is not audio is refused rather than guessed at`() {
        val packet = rtp(0x54, ByteArray(16))
        assertNull(session().rtpPayload(packet, packet.size))
        assertNull(session().rtpPayload(ByteArray(8), 8))
    }

    @Test
    fun `only whole blocks are encrypted and the tail is left alone`() {
        // RAOP encrypts floor(n/16) blocks with no padding. The remaining
        // bytes travel in clear, and decrypting them corrupts the end of every
        // frame.
        val plain = ByteArray(70) { (it * 7).toByte() }        // 4 blocks + 6 bytes
        val cipher = Cipher.getInstance("AES/CBC/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
        val onWire = plain.copyOf()
        cipher.doFinal(plain, 0, 64, onWire, 0)               // tail stays as it was

        val out = session().decrypt(onWire)!!
        assertArrayEquals(plain, out)
    }

    @Test
    fun `a packet shorter than one block passes through untouched`() {
        val short = ByteArray(9) { it.toByte() }
        assertArrayEquals(short, session().decrypt(short))
    }

    @Test
    fun `the iv is not chained between packets`() {
        // Chaining would mean a single lost packet desynchronised everything
        // after it, with no way back.
        val plain = ByteArray(32) { it.toByte() }
        val cipher = Cipher.getInstance("AES/CBC/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
        val encrypted = cipher.doFinal(plain)
        val s = session()
        assertArrayEquals(plain, s.decrypt(encrypted))
        assertArrayEquals("second packet must decrypt identically",
            plain, s.decrypt(encrypted))
    }

    @Test
    fun `without a key nothing is claimed to have been decrypted`() {
        assertNull(RaopAudioSession(null, iv) { _, _ -> }.decrypt(ByteArray(32)))
        assertNull(RaopAudioSession(key, null) { _, _ -> }.decrypt(ByteArray(32)))
    }

    @Test
    fun `a stereo alac frame is recognisable as one`() {
        val cpe = byteArrayOf(0x20, 0x00, 0x00)
        assertTrue(session().describeAlac(cpe).contains("CPE"))
        assertTrue(session().describeAlac(ByteArray(0)).contains("empty"))
    }
}
