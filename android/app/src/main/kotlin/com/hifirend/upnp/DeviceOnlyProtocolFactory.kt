package com.hifirend.upnp

import android.util.Log
import org.jupnp.model.message.IncomingDatagramMessage
import org.jupnp.model.message.UpnpRequest
import org.jupnp.protocol.ProtocolFactory
import org.jupnp.protocol.ReceivingAsync

private const val TAG = "hifirend"

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
        if (operation is UpnpRequest) {
            // NOTIFY is another device announcing itself, which is the whole
            // source of the problem. M-SEARCH is a controller looking for us,
            // and is the one thing here that must always get through.
            if (operation.method == UpnpRequest.Method.NOTIFY) {
                ignored++
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

    /** Logged occasionally: silence would make this impossible to tell from a dead network. */
    fun logIfDue() {
        val n = ignored
        if (n > 0 && n % 500 == 0L) {
            Log.i(TAG, "upnp: ignored $n remote-device announcements (renderer, not control point)")
        }
    }
}
