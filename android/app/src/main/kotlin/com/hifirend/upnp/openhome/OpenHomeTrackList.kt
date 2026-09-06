package com.hifirend.upnp.openhome

import android.util.Log
import com.hifirend.upnp.TrackMetadata
import java.util.Base64

private const val TAG = "hifirend"

/** One entry in the renderer's own playlist. */
data class OpenHomeTrack(
    val id: Int,
    val uri: String,
    val metadata: String,
    val track: TrackMetadata = TrackMetadata.parse(metadata),
)

/**
 * The playlist an OpenHome controller fills and the renderer then owns.
 *
 * This is the whole reason OpenHome is worth building. AVTransport only ever
 * tells a renderer about the current track and, if the controller bothers,
 * the next one -- so `PlaylistQueue` has to accumulate what it is told and
 * depend on the controller staying alive to keep telling it. That dependency
 * is exactly what the spec asks this app not to have. Here the controller
 * pushes the entire list up front and may then be killed, walked out of the
 * house or run out of battery: everything needed to play to the end is already
 * on this side.
 *
 * Ids, not indices, are the identity of a track. Controllers cache them and
 * send them back in SeekId and DeleteId, so an id must never be reused within
 * a session -- reusing one makes a controller act on a track the user deleted.
 * Hence a monotonic counter rather than a position.
 *
 * Every mutation bumps [token]. Controllers poll IdArrayChanged(token) to find
 * out whether their cached copy is stale, which is much cheaper than shipping
 * the array on every poll.
 */
class OpenHomeTrackList(val tracksMax: Int = 1000) {

    private val tracks = mutableListOf<OpenHomeTrack>()
    private var nextId = 1

    /** Bumped on every change to the list; the IdArray poll compares it. */
    @Volatile
    var token: Int = 0
        private set

    /** Id of the track playback is on, or 0 for none -- 0 is never a real id. */
    @Volatile
    var currentId: Int = 0
        private set

    @Volatile var repeat: Boolean = false
    @Volatile var shuffle: Boolean = false
        set(value) {
            field = value
            synchronized(this) { reshuffle() }
        }

    /**
     * The order [next] follows while shuffling, as ids.
     *
     * Kept as a permutation rather than picking at random each time: a random
     * pick replays tracks and skips others, which on a long album is obvious
     * and looks like a bug rather than a shuffle.
     */
    private var shuffleOrder = listOf<Int>()

    @get:Synchronized
    val size: Int get() = tracks.size

    @Synchronized
    fun snapshot(): List<OpenHomeTrack> = tracks.toList()

    @Synchronized
    fun byId(id: Int): OpenHomeTrack? = tracks.firstOrNull { it.id == id }

    @Synchronized
    fun indexOfId(id: Int): Int = tracks.indexOfFirst { it.id == id }

    @Synchronized
    fun current(): OpenHomeTrack? = tracks.firstOrNull { it.id == currentId }

    /**
     * Inserts after [afterId], where 0 means the head of the list -- the
     * spec's convention, and how a controller adds the first track.
     *
     * Returns the new id, or null when [afterId] names nothing (the caller
     * turns that into the spec's error 800) and throws nothing on a full list;
     * the caller reports 801. Errors are values here so the service layer owns
     * the SOAP fault codes and this stays testable.
     */
    @Synchronized
    fun insert(afterId: Int, uri: String, metadata: String): Int? {
        if (tracks.size >= tracksMax) {
            Log.w(TAG, "openhome: playlist full at $tracksMax")
            return null
        }
        val at = when (afterId) {
            0 -> 0
            else -> {
                val i = indexOfId(afterId)
                if (i < 0) {
                    Log.w(TAG, "openhome: insert after unknown id $afterId")
                    return null
                }
                i + 1
            }
        }
        val id = nextId++
        tracks.add(at, OpenHomeTrack(id, uri, metadata))
        changed()
        return id
    }

    /** Returns false when the id is not in the list. */
    @Synchronized
    fun delete(id: Int): Boolean {
        val i = indexOfId(id)
        if (i < 0) return false
        tracks.removeAt(i)
        changed()
        return true
    }

    @Synchronized
    fun deleteAll() {
        tracks.clear()
        currentId = 0
        changed()
    }

    /**
     * [anchorShuffle] distinguishes the user picking a track from the playlist
     * simply moving on.
     *
     * Picking one while shuffling has to re-anchor the order on it, or the
     * tracks that happened to fall before it in the permutation never play at
     * all -- shuffle would drop part of the album silently. Advancing must
     * *not* re-anchor, because regenerating the order on every track is how a
     * shuffle ends up replaying songs and skipping others.
     */
    @Synchronized
    fun setCurrent(id: Int, anchorShuffle: Boolean = false) {
        currentId = if (indexOfId(id) >= 0) id else 0
        if (anchorShuffle && shuffle) reshuffle()
    }

    /**
     * The track after the current one, honouring repeat and shuffle, or null
     * at the end of a playlist that is not repeating.
     */
    @Synchronized
    fun next(): OpenHomeTrack? {
        if (tracks.isEmpty()) return null
        val order = if (shuffle) shuffleOrder else tracks.map { it.id }
        val at = order.indexOf(currentId)
        // A current id that is not in the order (nothing playing yet, or the
        // track was deleted under us) starts from the top rather than failing.
        if (at < 0) return byId(order.firstOrNull() ?: return null)
        val nextAt = at + 1
        if (nextAt < order.size) return byId(order[nextAt])
        if (repeat) {
            if (shuffle) reshuffle()
            return byId((if (shuffle) shuffleOrder else tracks.map { it.id }).firstOrNull() ?: return null)
        }
        return null
    }

    @Synchronized
    fun previous(): OpenHomeTrack? {
        if (tracks.isEmpty()) return null
        val order = if (shuffle) shuffleOrder else tracks.map { it.id }
        val at = order.indexOf(currentId)
        if (at < 0) return byId(order.firstOrNull() ?: return null)
        if (at > 0) return byId(order[at - 1])
        if (repeat) return byId(order.last())
        return null
    }

    @Synchronized
    fun atIndex(index: Int): OpenHomeTrack? = tracks.getOrNull(index)

    /**
     * The evented IdArray: every id in order, each as a big-endian uint32.
     * The packing is the spec's, not a choice -- a controller decodes it
     * blind, so a wrong byte order silently yields a playlist of absurd ids
     * rather than an error.
     */
    @Synchronized
    fun idArrayBytes(): ByteArray {
        val out = ByteArray(tracks.size * 4)
        for ((i, t) in tracks.withIndex()) {
            out[i * 4] = ((t.id ushr 24) and 0xFF).toByte()
            out[i * 4 + 1] = ((t.id ushr 16) and 0xFF).toByte()
            out[i * 4 + 2] = ((t.id ushr 8) and 0xFF).toByte()
            out[i * 4 + 3] = (t.id and 0xFF).toByte()
        }
        return out
    }

    /**
     * The same array as it goes on the wire. jUPnP base64-encodes a ByteArray
     * for a bin.base64 variable itself, so this exists for logging and for
     * tests to assert the encoding without a UPnP stack.
     */
    @Synchronized
    fun idArrayBase64(): String = Base64.getEncoder().encodeToString(idArrayBytes())

    /**
     * ReadList's answer: the requested ids as a TrackList document.
     *
     * Unknown ids are skipped rather than faulted. A controller routinely asks
     * about ids it cached just before another controller deleted them, and
     * failing the whole call would leave it unable to draw any of the list.
     */
    @Synchronized
    fun readListXml(idList: String): String = buildString {
        append("<TrackList>")
        for (token in idList.trim().split(Regex("\\s+"))) {
            val id = token.toIntOrNull() ?: continue
            val t = byId(id) ?: continue
            append("<Entry>")
            append("<Id>").append(t.id).append("</Id>")
            append("<Uri>").append(escape(t.uri)).append("</Uri>")
            append("<Metadata>").append(escape(t.metadata)).append("</Metadata>")
            append("</Entry>")
        }
        append("</TrackList>")
    }

    private fun changed() {
        token++
        if (shuffle) syncShuffleOrder()
    }

    /**
     * Keeps the shuffle order in step with the list without regenerating it.
     *
     * Adding a track mid-playlist must not re-randomise what is left to play:
     * the listener would hear tracks repeat and others vanish, from nothing
     * more than someone queueing a song.
     */
    private fun syncShuffleOrder() {
        val ids = tracks.map { it.id }
        val kept = shuffleOrder.filter { ids.contains(it) }
        val added = ids.filter { !kept.contains(it) }
        shuffleOrder = kept + added.shuffled()
    }

    /** Keeps the current track first so shuffling mid-track does not restart it. */
    private fun reshuffle() {
        val ids = tracks.map { it.id }.toMutableList()
        ids.shuffle()
        if (currentId != 0 && ids.remove(currentId)) ids.add(0, currentId)
        shuffleOrder = ids
    }

    companion object {
        fun escape(s: String): String = s
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
            .replace("'", "&apos;")
    }
}
