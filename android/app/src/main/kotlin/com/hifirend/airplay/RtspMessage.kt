package com.hifirend.airplay

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream

/**
 * RTSP as AirPlay 1 speaks it.
 *
 * The wire format is HTTP's, but this is deliberately not built on an HTTP
 * library. RAOP sends methods no HTTP server will route -- `ANNOUNCE`,
 * `SETUP`, `RECORD`, `FLUSH`, `TEARDOWN` -- against a `rtsp://` URI, and it
 * expects the reply to say `RTSP/1.0`. It is a small enough grammar that
 * parsing it directly is less work than persuading something else not to
 * normalise it.
 *
 * Header lookup is case-insensitive because senders disagree: `CSeq` is spelled
 * that way by iOS and `Cseq` by several third-party senders, and getting that
 * wrong loses the sequence number, which ends the session immediately.
 */
data class RtspRequest(
    val method: String,
    val uri: String,
    val headers: Map<String, String>,
    val body: ByteArray,
) {
    operator fun get(name: String): String? = headers[name.lowercase()]

    /** The sequence number every reply must echo, or null if the sender omitted it. */
    val cseq: String? get() = this["CSeq"]

    // Generated equals/hashCode would compare the body by identity, which makes
    // every test that constructs an expected request fail for the wrong reason.
    override fun equals(other: Any?): Boolean =
        other is RtspRequest && method == other.method && uri == other.uri &&
            headers == other.headers && body.contentEquals(other.body)

    override fun hashCode(): Int =
        ((method.hashCode() * 31 + uri.hashCode()) * 31 + headers.hashCode()) * 31 +
            body.contentHashCode()
}

class RtspResponse(
    val status: String = "200 OK",
    val headers: LinkedHashMap<String, String> = LinkedHashMap(),
    val body: ByteArray = ByteArray(0),
) {
    fun header(name: String, value: String): RtspResponse {
        headers[name] = value
        return this
    }

    fun toBytes(): ByteArray {
        val head = StringBuilder("RTSP/1.0 ").append(status).append("\r\n")
        // Content-Length is written from the body rather than trusted from the
        // caller: a mismatch leaves the sender waiting for bytes that never
        // come, and the session simply hangs rather than failing visibly.
        if (body.isNotEmpty()) headers["Content-Length"] = body.size.toString()
        for ((k, v) in headers) head.append(k).append(": ").append(v).append("\r\n")
        head.append("\r\n")
        val out = ByteArrayOutputStream()
        out.write(head.toString().toByteArray(Charsets.UTF_8))
        out.write(body)
        return out.toByteArray()
    }
}

object Rtsp {

    /** The largest body worth accepting; ANNOUNCE's SDP is well under a kilobyte. */
    const val MAX_BODY = 64 * 1024

    /**
     * Splits a complete head into its request line and headers.
     *
     * Kept separate from the socket so it can be tested without one: the
     * framing bugs that matter here -- a missing CSeq, a folded header, a body
     * length that disagrees with the body -- are all decidable from the text.
     */
    fun parseHead(head: String): Pair<Pair<String, String>, Map<String, String>>? {
        val lines = head.split("\r\n").filter { it.isNotEmpty() }
        if (lines.isEmpty()) return null
        val request = lines[0].split(' ')
        if (request.size < 2) return null
        val headers = LinkedHashMap<String, String>()
        for (line in lines.drop(1)) {
            val colon = line.indexOf(':')
            if (colon <= 0) continue
            headers[line.substring(0, colon).trim().lowercase()] =
                line.substring(colon + 1).trim()
        }
        return (request[0] to request[1]) to headers
    }

    /**
     * Reads one request, or null at end of stream.
     *
     * Reads a byte at a time to the blank line rather than buffering ahead,
     * because the body that follows is binary and length-delimited: a reader
     * that over-reads the head swallows the front of the body and the SDP
     * parse fails somewhere unrelated.
     */
    @Throws(IOException::class)
    fun read(input: InputStream): RtspRequest? {
        val head = ByteArrayOutputStream()
        var state = 0        // how much of \r\n\r\n has been seen
        while (state < 4) {
            val b = input.read()
            if (b < 0) return null
            head.write(b)
            state = when {
                b == '\r'.code && (state == 0 || state == 2) -> state + 1
                b == '\n'.code && (state == 1 || state == 3) -> state + 1
                else -> 0
            }
            if (head.size() > MAX_BODY) throw IOException("RTSP head too long")
        }

        val text = head.toString("UTF-8")
        val (line, headers) = parseHead(text) ?: return null
        val length = headers["content-length"]?.trim()?.toIntOrNull() ?: 0
        if (length < 0 || length > MAX_BODY) throw IOException("bad Content-Length $length")

        val body = ByteArray(length)
        var read = 0
        while (read < length) {
            val n = input.read(body, read, length - read)
            if (n < 0) throw IOException("stream ended $read/$length bytes into the body")
            read += n
        }
        return RtspRequest(line.first.uppercase(), line.second, headers, body)
    }

    /**
     * The `a=` and `m=` lines of the SDP an ANNOUNCE carries, flattened.
     *
     * Only the attribute lines matter here and they are all `a=name:value`,
     * so this returns those; the media lines are not needed to set a session
     * up. Keys repeat in principle but not in any RAOP announcement seen, so
     * last-wins is fine and simpler than a multimap nobody reads twice.
     */
    fun parseSdpAttributes(sdp: String): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        for (raw in sdp.split('\n')) {
            val line = raw.trim()
            if (!line.startsWith("a=")) continue
            val rest = line.substring(2)
            val colon = rest.indexOf(':')
            if (colon <= 0) continue
            out[rest.substring(0, colon)] = rest.substring(colon + 1)
        }
        return out
    }
}
