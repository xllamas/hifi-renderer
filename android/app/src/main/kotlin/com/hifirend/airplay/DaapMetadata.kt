package com.hifirend.airplay

/**
 * The track a guest is playing, as the sender describes it over SET_PARAMETER.
 *
 * AirPlay carries no metadata in the audio stream -- RAOP sends bare ALAC
 * frames and nothing else -- so everything the screen can say about a guest's
 * track arrives out of band, in a SET_PARAMETER request whose body is DMAP:
 * Apple's binary tag-length-value encoding, the same one DAAP serves iTunes
 * libraries with.
 *
 * Each item is a four-byte ASCII tag, a four-byte big-endian length, and that
 * many bytes of payload:
 *
 *     6d 6c 69 74  00 00 00 2a   mlit, 42 bytes, a listing item...
 *       6d 69 6e 6d  00 00 00 09   minm, 9 bytes
 *         "Chameleon"
 *       61 73 61 72  00 00 00 0f   asar, 15 bytes
 *         "Herbie Hancock"
 *
 * Parsed rather than scanned for, because the failure mode of guessing is
 * quiet. Lengths are what separate one field from the next, so a reader that
 * looks for `minm` and takes bytes until the next printable run will happily
 * return half a title, or a title with the next tag glued to it, and the
 * result looks like a metadata bug in the sender. Every length here is checked
 * against what is actually left in the buffer.
 *
 * Senders disagree about whether the fields are wrapped. iOS and macOS send a
 * `mlit` container; several third-party senders send the fields bare at the
 * top level. Both are read, because refusing one of them would mean a guest
 * whose music plays under "Unknown track" for no reason they could discover.
 */
data class DaapMetadata(
    val title: String? = null,
    val artist: String? = null,
    val album: String? = null,
    val genre: String? = null,
    /** From `astm`, which is milliseconds; 0 when the sender did not say. */
    val durationSeconds: Int = 0,
) {

    /**
     * True when the sender told us nothing worth putting on the screen.
     *
     * A SET_PARAMETER can legitimately carry only fields this does not read --
     * a persistent id, an item kind -- and publishing that over a title we
     * already have would blank the screen mid-track.
     */
    val isEmpty: Boolean
        get() = title == null && artist == null && album == null && durationSeconds == 0

    companion object {

        /** What the sender labels the DMAP body with. */
        const val CONTENT_TYPE = "application/x-dmap-tagged"

        private const val HEADER = 8

        /**
         * Containers whose payload is more DMAP rather than a value.
         *
         * A closed set, not a guess. There is no flag in the encoding saying
         * whether a payload is nested, so the alternative is to try parsing
         * every payload as items and recurse when it "looks like" DMAP -- and
         * a UTF-8 title of the right length looks exactly like DMAP often
         * enough to matter. Descending only into tags known to nest means an
         * unknown container is skipped whole, which loses fields but never
         * invents them.
         */
        private val CONTAINERS = setOf("mlit", "mlcl", "mshl", "msrv", "mlog", "adbs")

        /** Tags whose payload is a UTF-8 string, mapped to what they mean. */
        private const val TITLE = "minm"
        private const val ARTIST = "asar"
        private const val ALBUM = "asal"
        private const val GENRE = "asgn"

        /** Song time, in milliseconds, as a four-byte big-endian integer. */
        private const val DURATION_MS = "astm"

        /**
         * Reads a DMAP body, keeping the fields the screen can use.
         *
         * Never throws. A truncated or malformed body yields whatever was
         * readable before the damage, because a guest whose title is missing
         * should still get their artist rather than an exception that ends the
         * RTSP session over a cosmetic field.
         */
        fun parse(body: ByteArray): DaapMetadata {
            var title: String? = null
            var artist: String? = null
            var album: String? = null
            var genre: String? = null
            var durationMs = 0

            walk(body) { tag, offset, length ->
                when (tag) {
                    TITLE -> title = text(body, offset, length)
                    ARTIST -> artist = text(body, offset, length)
                    ALBUM -> album = text(body, offset, length)
                    GENRE -> genre = text(body, offset, length)
                    DURATION_MS -> durationMs = int32(body, offset, length)
                }
            }

            return DaapMetadata(
                title = title,
                artist = artist,
                album = album,
                genre = genre,
                // Rounded to the nearest second rather than truncated: a
                // 3:47.6 track shown as 3:47 stops one tick short of its own
                // end, which reads as a stall.
                durationSeconds = if (durationMs > 0) (durationMs + 500) / 1000 else 0,
            )
        }

        /**
         * Every tag in the body, outermost first, for the log.
         *
         * Worth having separately from [parse]: when a sender's metadata does
         * not appear on screen, the question is always whether the fields were
         * absent or merely unread, and those two have very different fixes.
         */
        fun tags(body: ByteArray): List<String> {
            val found = ArrayList<String>()
            walk(body) { tag, _, _ -> found.add(tag) }
            return found
        }

        /**
         * Visits every item, descending into containers.
         *
         * [visit] receives the tag, the offset of its payload, and the payload
         * length -- never the bytes, so no field is copied unless something
         * actually wants it.
         */
        private fun walk(body: ByteArray, visit: (String, Int, Int) -> Unit) {
            walkRange(body, 0, body.size, 0, visit)
        }

        private fun walkRange(
            body: ByteArray,
            from: Int,
            until: Int,
            depth: Int,
            visit: (String, Int, Int) -> Unit,
        ) {
            // A malformed body could in principle nest for ever. Nothing real
            // goes past two levels, and stopping is better than a stack
            // overflow on the RTSP thread.
            if (depth > 8) return
            var at = from
            while (at + HEADER <= until) {
                val tag = tagAt(body, at) ?: return
                val length = int32be(body, at + 4)
                val payload = at + HEADER
                // A length that runs past the end is where a hand-rolled
                // reader starts inventing data. Stop instead: what came before
                // is still good, and what comes after cannot be located.
                if (length < 0 || payload + length > until) return
                visit(tag, payload, length)
                if (tag in CONTAINERS) walkRange(body, payload, payload + length, depth + 1, visit)
                at = payload + length
            }
        }

        /** Four ASCII letters, or null for anything that is not a tag. */
        private fun tagAt(body: ByteArray, at: Int): String? {
            val sb = StringBuilder(4)
            for (i in at until at + 4) {
                val c = body[i].toInt() and 0xFF
                // Tags are lower-case ASCII letters and digits. Anything else
                // means we are no longer looking at an item boundary, and
                // carrying on would read lengths out of arbitrary bytes.
                if (c !in 'a'.code..'z'.code && c !in '0'.code..'9'.code) return null
                sb.append(c.toChar())
            }
            return sb.toString()
        }

        private fun int32be(body: ByteArray, at: Int): Int =
            ((body[at].toInt() and 0xFF) shl 24) or
                ((body[at + 1].toInt() and 0xFF) shl 16) or
                ((body[at + 2].toInt() and 0xFF) shl 8) or
                (body[at + 3].toInt() and 0xFF)

        /** A string field, or null when empty -- an empty title is not a title. */
        private fun text(body: ByteArray, at: Int, length: Int): String? {
            if (length <= 0) return null
            return String(body, at, length, Charsets.UTF_8).trim().takeIf { it.isNotEmpty() }
        }

        /**
         * A numeric field, tolerant of width.
         *
         * `astm` is four bytes everywhere it has been seen, but DMAP numbers
         * are sized by their length and a sender is entitled to send a
         * narrower one. Reading whatever is there beats returning nothing.
         */
        private fun int32(body: ByteArray, at: Int, length: Int): Int {
            if (length <= 0 || length > 8) return 0
            var v = 0L
            for (i in at until at + length) v = (v shl 8) or (body[i].toLong() and 0xFF)
            return if (v in 0..Int.MAX_VALUE.toLong()) v.toInt() else 0
        }
    }
}
