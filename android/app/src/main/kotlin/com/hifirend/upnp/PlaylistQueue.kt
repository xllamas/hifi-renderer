package com.hifirend.upnp

import android.util.Log

private const val TAG = "hifirend"

data class QueueItem(val uri: String, val metaData: String?)

/**
 * The local queue behind AVTransport.
 *
 * Exists to satisfy an explicit requirement: playback must continue when the
 * DLNA controller goes away. Controllers only ever tell us about the current
 * and next track, so those are accumulated here rather than being fetched from
 * the controller on demand — once it is gone, there is nobody to ask.
 *
 * Persistence across process death is M6.
 */
class PlaylistQueue {

    @Volatile
    var current: QueueItem? = null
        private set

    @Volatile
    var next: QueueItem? = null
        private set

    private val played = mutableListOf<QueueItem>()

    @Synchronized
    fun setCurrent(uri: String, metaData: String?) {
        current?.let { played += it }
        current = QueueItem(uri, metaData)
        // A controller setting a new current track invalidates any queued next.
        next = null
    }

    @Synchronized
    fun setNext(uri: String, metaData: String?) {
        next = QueueItem(uri, metaData)
    }

    /** Moves to the queued next track. Returns null when the queue is exhausted. */
    @Synchronized
    fun advance(): QueueItem? {
        val n = next
        if (n == null) {
            Log.i(TAG, "queue: nothing queued after ${current?.uri}")
            return null
        }
        current?.let { played += it }
        current = n
        next = null
        Log.i(TAG, "queue: advanced to ${n.uri}")
        return n
    }

    @Synchronized
    fun clear() {
        current = null
        next = null
        played.clear()
    }

    val playedCount: Int get() = played.size
}
