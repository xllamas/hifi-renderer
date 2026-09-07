package com.hifirend.airplay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream

/**
 * The framing, which is where a receiver fails silently.
 *
 * None of these are visible on a device: a lost CSeq, an over-read head or a
 * body length nobody honoured all end the session with the sender saying only
 * that it could not connect. They are all decidable from the bytes, so they
 * are decided here.
 */
class RtspMessageTest {

    private fun bytes(s: String) = ByteArrayInputStream(s.toByteArray(Charsets.UTF_8))

    @Test
    fun `reads a request with no body`() {
        val r = Rtsp.read(bytes("OPTIONS * RTSP/1.0\r\nCSeq: 1\r\n\r\n"))!!
        assertEquals("OPTIONS", r.method)
        assertEquals("*", r.uri)
        assertEquals("1", r.cseq)
        assertEquals(0, r.body.size)
    }

    @Test
    fun `header lookup ignores case`() {
        // iOS sends CSeq; several third-party senders send Cseq. Losing the
        // sequence number ends the session immediately.
        val r = Rtsp.read(bytes("OPTIONS * RTSP/1.0\r\nCseq: 7\r\nAPPLE-CHALLENGE: abc\r\n\r\n"))!!
        assertEquals("7", r.cseq)
        assertEquals("abc", r["Apple-Challenge"])
    }

    @Test
    fun `reads exactly the announced body and no more`() {
        // The body is binary and length-delimited, and the next request
        // follows it on the same socket. A reader that buffers past the blank
        // line eats the front of the body and the SDP parse fails somewhere
        // unrelated to the actual mistake.
        val input = bytes(
            "ANNOUNCE rtsp://x RTSP/1.0\r\nCSeq: 2\r\nContent-Length: 5\r\n\r\n" +
                "HELLO" + "OPTIONS * RTSP/1.0\r\nCSeq: 3\r\n\r\n")
        val first = Rtsp.read(input)!!
        assertEquals("HELLO", String(first.body))
        val second = Rtsp.read(input)!!
        assertEquals("OPTIONS", second.method)
        assertEquals("3", second.cseq)
    }

    @Test
    fun `end of stream reads as null rather than throwing`() {
        assertNull(Rtsp.read(bytes("")))
    }

    @Test
    fun `a truncated body is an error, not a short read`() {
        val e = runCatching {
            Rtsp.read(bytes("ANNOUNCE x RTSP/1.0\r\nCSeq: 1\r\nContent-Length: 10\r\n\r\nshort"))
        }.exceptionOrNull()
        assertTrue("expected an IOException, got $e", e is java.io.IOException)
    }

    @Test
    fun `a response writes its own content length`() {
        // Trusting a caller-supplied length leaves the sender waiting for
        // bytes that never arrive, which hangs rather than failing.
        val out = String(RtspResponse().header("CSeq", "1").let {
            RtspResponse("200 OK", it.headers, "body".toByteArray()).toBytes()
        })
        assertTrue(out, out.contains("Content-Length: 4"))
        assertTrue(out, out.startsWith("RTSP/1.0 200 OK\r\n"))
        assertTrue(out, out.endsWith("\r\n\r\nbody"))
    }

    @Test
    fun `parses the sdp attributes an ANNOUNCE carries`() {
        val sdp = """
            v=0
            o=iTunes 3467 0 IN IP4 192.168.1.5
            m=audio 0 RTP/AVP 96
            a=rtpmap:96 AppleLossless
            a=fmtp:96 352 0 16 40 10 14 2 255 0 0 44100
            a=rsaaeskey:AAAA
            a=aesiv:BBBB
        """.trimIndent()
        val a = Rtsp.parseSdpAttributes(sdp)
        assertEquals("AAAA", a["rsaaeskey"])
        assertEquals("BBBB", a["aesiv"])
        assertTrue(a["fmtp"]!!.endsWith("44100"))
    }

    @Test
    fun `base64 padding is restored for the wire format`() {
        // RAOP strips it; the decoder wants it.
        assertEquals("AAAA", RaopCrypto.pad("AAAA"))
        assertEquals("AAA=", RaopCrypto.pad("AAA"))
        assertEquals("AA==", RaopCrypto.pad("AA"))
    }
}
