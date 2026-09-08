package com.hifirend.airplay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream

/**
 * DMAP is length-delimited binary, and every interesting failure is silent.
 *
 * A misread length does not throw -- it returns a string that looks like
 * metadata, so the bug surfaces as "the sender's title is wrong" and gets
 * blamed on the sender. These tests are mostly about the boundaries rather
 * than the happy path: truncation, a length that overruns, a field that is not
 * a string, and the two different shapes senders use.
 */
class DaapMetadataTest {

    /** Builds one DMAP item, the way a sender does. */
    private fun item(tag: String, payload: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        out.write(tag.toByteArray(Charsets.US_ASCII))
        out.write(byteArrayOf(
            (payload.size ushr 24).toByte(), (payload.size ushr 16).toByte(),
            (payload.size ushr 8).toByte(), payload.size.toByte(),
        ))
        out.write(payload)
        return out.toByteArray()
    }

    private fun str(tag: String, value: String) = item(tag, value.toByteArray(Charsets.UTF_8))

    private fun int32(tag: String, value: Int) = item(tag, byteArrayOf(
        (value ushr 24).toByte(), (value ushr 16).toByte(),
        (value ushr 8).toByte(), value.toByte(),
    ))

    private fun bytes(vararg parts: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        parts.forEach { out.write(it) }
        return out.toByteArray()
    }

    @Test
    fun `reads a track from the mlit container macOS sends`() {
        val body = item("mlit", bytes(
            item("mikd", byteArrayOf(2)),
            str("minm", "Chameleon"),
            str("asar", "Herbie Hancock"),
            str("asal", "Head Hunters"),
            str("asgn", "Jazz"),
            int32("astm", 945_000),
        ))

        val m = DaapMetadata.parse(body)
        assertEquals("Chameleon", m.title)
        assertEquals("Herbie Hancock", m.artist)
        assertEquals("Head Hunters", m.album)
        assertEquals("Jazz", m.genre)
        assertEquals(945, m.durationSeconds)
        assertFalse(m.isEmpty)
    }

    @Test
    fun `reads fields sent bare, without a container`() {
        // Several third-party senders omit the mlit wrapper. Refusing them
        // would mean a guest playing under "Unknown track" with no way to tell
        // why.
        val body = bytes(
            str("minm", "Ai giochi addio"),
            str("asar", "Fausto Mesolella"),
        )

        val m = DaapMetadata.parse(body)
        assertEquals("Ai giochi addio", m.title)
        assertEquals("Fausto Mesolella", m.artist)
    }

    @Test
    fun `a length running past the end stops rather than inventing a field`() {
        // The failure this whole parser exists to avoid. A reader that trusted
        // the length would return 200 bytes of whatever followed in memory,
        // or throw on the RTSP thread and drop the session over a title.
        val good = str("minm", "Real Title")
        val lying = bytes(
            "asar".toByteArray(Charsets.US_ASCII),
            byteArrayOf(0x00, 0x00, 0x00, 0x7F),   // claims 127 bytes
            "short".toByteArray(Charsets.UTF_8),   // provides 5
        )

        val m = DaapMetadata.parse(bytes(good, lying))
        assertEquals("what was readable before the damage survives",
            "Real Title", m.title)
        assertNull("the overrunning field is dropped, not guessed at", m.artist)
    }

    @Test
    fun `a body truncated mid-header keeps what came before`() {
        val body = bytes(str("minm", "Chameleon"), "asa".toByteArray(Charsets.US_ASCII))
        val m = DaapMetadata.parse(body)
        assertEquals("Chameleon", m.title)
        assertNull(m.artist)
    }

    @Test
    fun `junk where a tag should be ends the walk`() {
        // Non-letter bytes mean we have lost the item boundary. Continuing
        // would read a length out of arbitrary bytes and produce a field from
        // nowhere.
        val body = bytes(
            str("minm", "Chameleon"),
            byteArrayOf(0xFF.toByte(), 0x00, 0x11, 0x7A, 0x00, 0x00, 0x00, 0x04),
            str("asar", "Never Reached"),
        )
        val m = DaapMetadata.parse(body)
        assertEquals("Chameleon", m.title)
        assertNull(m.artist)
    }

    @Test
    fun `an empty title is not a title`() {
        // Senders send an empty minm between tracks. Taking it literally
        // replaces a good title with a blank line rather than leaving the
        // previous one alone.
        val m = DaapMetadata.parse(bytes(str("minm", ""), str("asar", "   ")))
        assertNull(m.title)
        assertNull(m.artist)
        assertTrue(m.isEmpty)
    }

    @Test
    fun `metadata carrying nothing readable reports itself empty`() {
        // A SET_PARAMETER with only a persistent id is legitimate, and
        // publishing it over a title already on screen would blank it
        // mid-track.
        val body = item("mlit", bytes(
            item("mper", ByteArray(8)),
            item("mikd", byteArrayOf(2)),
        ))
        assertTrue(DaapMetadata.parse(body).isEmpty)
    }

    @Test
    fun `duration rounds rather than truncating`() {
        // 3:47.6 shown as 3:47 stops a tick short of its own end, which reads
        // as a stall on the progress bar.
        assertEquals(228, DaapMetadata.parse(int32("astm", 227_600)).durationSeconds)
        assertEquals(0, DaapMetadata.parse(int32("astm", 0)).durationSeconds)
    }

    @Test
    fun `UTF-8 survives the round trip`() {
        // Track titles are not ASCII, and a parser that read bytes as Latin-1
        // would mangle exactly the titles the owner is most likely to notice.
        val m = DaapMetadata.parse(str("minm", "Björk — Jóga"))
        assertEquals("Björk — Jóga", m.title)
    }

    @Test
    fun `an empty body is empty rather than an error`() {
        assertTrue(DaapMetadata.parse(ByteArray(0)).isEmpty)
        assertTrue(DaapMetadata.parse(ByteArray(3)).isEmpty)
    }

    @Test
    fun `tags lists what arrived, for when nothing shows on screen`() {
        val body = item("mlit", bytes(str("minm", "X"), int32("astm", 1000)))
        val tags = DaapMetadata.tags(body)
        assertTrue(tags.contains("mlit"))
        assertTrue(tags.contains("minm"))
        assertTrue(tags.contains("astm"))
    }
}
