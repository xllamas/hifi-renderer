package com.hifirend.upnp.openhome

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64

/**
 * The playlist model, tested off-device.
 *
 * These are the parts that fail *silently* against a real controller rather
 * than throwing: a wrong IdArray byte order decodes into a list of absurd ids,
 * a reused id makes a controller act on a track the user deleted, and an
 * off-by-one in insert-after puts tracks in the wrong order. None of that
 * shows up as an error anywhere -- it shows up as a controller behaving oddly,
 * which is expensive to diagnose from the other end of a network.
 */
class OpenHomeTrackListTest {

    private fun listOfTracks(vararg uris: String): OpenHomeTrackList {
        val list = OpenHomeTrackList()
        var after = 0
        for (u in uris) after = list.insert(after, u, "")!!
        return list
    }

    @Test
    fun `insert after zero puts a track at the head`() {
        val list = OpenHomeTrackList()
        val first = list.insert(0, "a", "")!!
        val second = list.insert(0, "b", "")!!
        assertEquals(listOf(second, first), list.snapshot().map { it.id })
    }

    @Test
    fun `insert after an id puts the track directly behind it`() {
        val list = listOfTracks("a", "b", "c")
        val ids = list.snapshot().map { it.id }
        list.insert(ids[0], "between", "")
        assertEquals(listOf("a", "between", "b", "c"), list.snapshot().map { it.uri })
    }

    @Test
    fun `insert after an unknown id is refused rather than appended`() {
        val list = listOfTracks("a")
        assertNull(list.insert(9999, "b", ""))
        assertEquals(1, list.size)
    }

    @Test
    fun `ids are never reused after deletion`() {
        val list = listOfTracks("a", "b")
        val ids = list.snapshot().map { it.id }
        list.delete(ids[1])
        val fresh = list.insert(ids[0], "c", "")!!
        // A controller may still hold the old id; handing it out again would
        // make it act on the wrong track.
        assertFalse(fresh in ids)
    }

    @Test
    fun `IdArray packs each id as a big-endian uint32`() {
        val list = OpenHomeTrackList()
        list.insert(0, "a", "")
        list.insert(0, "b", "")
        // Ids 1 and 2, in list order: b (id 2) then a (id 1).
        assertArrayEquals(
            byteArrayOf(0, 0, 0, 2, 0, 0, 0, 1),
            list.idArrayBytes(),
        )
        assertArrayEquals(
            list.idArrayBytes(),
            Base64.getDecoder().decode(list.idArrayBase64()),
        )
    }

    @Test
    fun `IdArray of an empty playlist is empty, not absent`() {
        assertEquals(0, OpenHomeTrackList().idArrayBytes().size)
    }

    @Test
    fun `the token changes on every mutation so a poll can spot a stale cache`() {
        val list = OpenHomeTrackList()
        val start = list.token
        val id = list.insert(0, "a", "")!!
        val afterInsert = list.token
        assertTrue(afterInsert != start)
        list.delete(id)
        assertTrue(list.token != afterInsert)
    }

    @Test
    fun `next walks the list and stops at the end`() {
        val list = listOfTracks("a", "b")
        list.setCurrent(list.snapshot()[0].id)
        assertEquals("b", list.next()?.uri)
        list.setCurrent(list.snapshot()[1].id)
        assertNull(list.next())
    }

    @Test
    fun `repeat wraps from the last track to the first`() {
        val list = listOfTracks("a", "b")
        list.repeat = true
        list.setCurrent(list.snapshot()[1].id)
        assertEquals("a", list.next()?.uri)
    }

    @Test
    fun `previous stops at the start unless repeating`() {
        val list = listOfTracks("a", "b")
        list.setCurrent(list.snapshot()[0].id)
        assertNull(list.previous())
        list.repeat = true
        assertEquals("b", list.previous()?.uri)
    }

    @Test
    fun `a current id that is no longer in the list falls back to the top`() {
        val list = listOfTracks("a", "b")
        val id = list.snapshot()[0].id
        list.setCurrent(id)
        list.delete(id)
        // Deleting the playing track must not strand the playlist.
        assertEquals("b", list.next()?.uri)
    }

    @Test
    fun `shuffle is a permutation, so every track plays exactly once`() {
        val list = listOfTracks("a", "b", "c", "d", "e")
        list.shuffle = true
        // The user picking a track anchors the order on it, so the whole
        // playlist is still ahead of them.
        list.setCurrent(list.snapshot()[0].id, anchorShuffle = true)
        val seen = mutableListOf(list.current()!!.uri)
        while (true) {
            val n = list.next() ?: break
            seen += n.uri
            list.setCurrent(n.id)
        }
        assertEquals(listOf("a", "b", "c", "d", "e"), seen.sorted())
    }

    @Test
    fun `queueing a track mid-shuffle does not re-randomise what is left`() {
        val list = listOfTracks("a", "b", "c", "d", "e")
        list.shuffle = true
        val first = list.snapshot()[0].id
        list.setCurrent(first, anchorShuffle = true)

        fun walkFrom(id: Int): List<String> {
            list.setCurrent(id)
            val seen = mutableListOf<String>()
            while (true) {
                val n = list.next() ?: break
                seen += n.uri
                list.setCurrent(n.id)
            }
            return seen
        }

        val before = walkFrom(first)
        list.insert(first, "f", "")
        val after = walkFrom(first)

        // The order already being walked survives; the new track joins the end
        // rather than the listener hearing the rest of the album reshuffled.
        assertEquals(before, after.take(before.size))
        assertEquals("f", after.last())
    }

    @Test
    fun `ReadList returns only the ids asked for, in the order asked`() {
        val list = listOfTracks("a", "b", "c")
        val ids = list.snapshot().map { it.id }
        val xml = list.readListXml("${ids[2]} ${ids[0]}")
        assertTrue(xml.startsWith("<TrackList>"))
        assertEquals(2, Regex("<Entry>").findAll(xml).count())
        assertTrue(xml.indexOf("<Uri>c</Uri>") < xml.indexOf("<Uri>a</Uri>"))
    }

    @Test
    fun `ReadList skips unknown ids rather than failing the whole call`() {
        val list = listOfTracks("a")
        val id = list.snapshot()[0].id
        // A controller routinely asks about ids another controller just
        // deleted; faulting would leave it unable to draw any of the list.
        val xml = list.readListXml("$id 4242")
        assertEquals(1, Regex("<Entry>").findAll(xml).count())
    }

    @Test
    fun `metadata is escaped so DIDL survives being nested in the response`() {
        val list = OpenHomeTrackList()
        val id = list.insert(0, "http://h/a.flac", "<DIDL-Lite><item id=\"1\"/></DIDL-Lite>")!!
        val xml = list.readListXml("$id")
        assertTrue(xml.contains("&lt;DIDL-Lite&gt;"))
        assertFalse(xml.contains("<DIDL-Lite>"))
    }

    @Test
    fun `the playlist refuses to grow past TracksMax`() {
        val list = OpenHomeTrackList(tracksMax = 2)
        assertTrue(list.insert(0, "a", "") != null)
        assertTrue(list.insert(0, "b", "") != null)
        assertNull(list.insert(0, "c", ""))
        assertEquals(2, list.size)
    }

    @Test
    fun `deleteAll empties the list and forgets what was playing`() {
        val list = listOfTracks("a", "b")
        list.setCurrent(list.snapshot()[0].id)
        list.deleteAll()
        assertEquals(0, list.size)
        assertEquals(0, list.currentId)
        assertNull(list.current())
    }
}
