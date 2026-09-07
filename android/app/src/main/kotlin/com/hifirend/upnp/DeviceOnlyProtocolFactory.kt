package com.hifirend.upnp

import android.util.Log
import org.jupnp.model.message.IncomingDatagramMessage
import org.jupnp.model.message.UpnpRequest
import org.jupnp.protocol.ProtocolFactory
import org.jupnp.protocol.ReceivingAsync

private const val TAG = "hifirend"

/** How often the SSDP census is logged. Often enough to watch, rare enough to ignore. */
private const val CENSUS_INTERVAL_MS = 60_000L

/**
 * Stops the renderer behaving like a control point.
 *
 * jUPnP runs both halves of UPnP: it answers for our device *and* it discovers
 * everyone else's. This app only ever needed the first. The second turned out
 * to be actively harmful.
 *
 * Every `ssdp:alive` on the network made jUPnP fetch that device's description
 * — and a media server may advertise addresses nothing can reach. BubbleUPnP
 * announced `127.0.0.1` and a VPN address alongside its real one, so each
 * announcement queued fetches that blocked for six or seven seconds before
 * failing, over and over, for ever.
 *
 * Incoming M-SEARCH is handled on the same async executor as those fetches. A
 * search has to be answered inside the controller's MX window, a second or
 * two, so once enough dead fetches were queued ahead of it the renderer simply
 * stopped being found — while everything already connected kept working
 * perfectly, because SOAP is served by Jetty's own thread pool. The symptom
 * was a renderer that played on happily and vanished from every controller.
 *
 * So remote-device chatter is dropped at the door, before it can occupy a
 * thread. Searches *for* us are untouched, which is the traffic that matters.
 * Returning null is the supported way to decline: RouterImpl logs it at trace
 * and moves on.
 */
class DeviceOnlyProtocolFactory(
    private val delegate: ProtocolFactory,
) : ProtocolFactory by delegate {

    override fun createReceivingAsync(message: IncomingDatagramMessage<*>?): ReceivingAsync<*>? {
        val operation = message?.operation
        if (operation is UpnpRequest && operation.method == UpnpRequest.Method.MSEARCH) {
            // Counted, never dropped. This is the traffic the renderer exists
            // to answer, and knowing whether it *arrives* is what separates
            // "the network stopped delivering to us" from "we stopped
            // replying" -- two faults that look identical from a controller
            // and have completely different cures.
            searchesSeen++
            lastMulticastAt = System.currentTimeMillis()
        }
        if (operation is UpnpRequest) {
            // NOTIFY is another device announcing itself, which is the whole
            // source of the problem. M-SEARCH is a controller looking for us,
            // and is the one thing here that must always get through.
            if (operation.method == UpnpRequest.Method.NOTIFY) {
                // Dropped, but counted first. A NOTIFY is by definition sent to
                // the SSDP group, so seeing one is proof that multicast is
                // still reaching this phone -- which is the one thing that
                // stops working, and the reason for [lastMulticastAt].
                ignored++
                lastMulticastAt = System.currentTimeMillis()
                return null
            }
        } else if (operation != null) {
            // A response to a search. We never search, so anything arriving
            // here is an answer to somebody else's question.
            ignored++
            return null
        }
        return delegate.createReceivingAsync(message)
    }

    @Volatile
    var ignored: Long = 0
        private set

    /**
     * When multicast last reached us, or 0 if it never has.
     *
     * The renderer stops being discoverable long before anything in it fails:
     * measured, unicast M-SEARCH to port 1900 is still answered while
     * multicast to the same socket gets nothing, so the packets are not being
     * delivered at all. The socket is alive, the group is joined as far as
     * `/proc/net/igmp` is concerned, and the multicast lock is held -- the
     * membership has lapsed somewhere above us, in the Wi-Fi driver or the
     * access point's IGMP snooping. Restarting the app rejoins the group and
     * cures it, which is why this looked intermittent for so long.
     *
     * Nothing in the app can see that directly. What it can see is that other
     * people's announcements have stopped arriving, on a network where they
     * arrive constantly.
     */
    @Volatile
    var lastMulticastAt: Long = 0
        private set

    /** Incoming M-SEARCH requests, the traffic a renderer must answer. */
    @Volatile
    var searchesSeen: Long = 0
        private set

    /**
     * Logged at the first announcement and then rarely.
     *
     * The first one matters on its own: it is the proof that multicast is
     * reaching this phone at all, and so that the silence watchdog has a
     * baseline to compare against. Without that line a network where nothing
     * ever arrives looks exactly like one where everything is fine.
     */
    @Volatile private var loggedFirst = false

    fun logIfDue() {
        val n = ignored
        // Not `n == 1`: the tick samples twice a second and several
        // announcements can arrive between two samples, so an equality test
        // silently never fires.
        if (n > 0 && !loggedFirst) {
            loggedFirst = true
            Log.i(TAG, "ssdp: multicast is reaching us; first remote-device " +
                "announcement seen (this is a renderer, not a control point)")
            return
        }
        // A periodic census. On a network with other UPnP devices both
        // numbers climb steadily; a stalled search count with announcements
        // still arriving would mean something quite different from both
        // stalling together.
        val now = System.currentTimeMillis()
        if (now - lastCensusAt >= CENSUS_INTERVAL_MS) {
            lastCensusAt = now
            // The silence figure is the watchdog's own input, printed beside
            // the counters it is derived from. On 2026-09-07 the counters
            // froze for five minutes and no rejoin fired, which the log could
            // not explain: a frozen census is consistent both with the
            // watchdog never being asked and with it being asked and saying
            // no. These two numbers disagreeing -- counters still, silence
            // not growing -- points at one; agreeing and still no rejoin
            // points at the other. That is a counter telling two mechanisms
            // apart, which is cheaper than picking one and being wrong.
            val silence = if (lastMulticastAt == 0L) -1
                          else (now - lastMulticastAt) / 1000
            Log.i(TAG, "ssdp census: $searchesSeen searches seen, " +
                "$n announcements ignored, silent ${silence}s")
        }
    }

    @Volatile private var lastCensusAt = 0L
}
