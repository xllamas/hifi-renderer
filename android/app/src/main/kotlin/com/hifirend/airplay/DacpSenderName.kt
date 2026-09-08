package com.hifirend.airplay

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log
import java.net.InetAddress
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Works out who is streaming to us, so the screen can say so.
 *
 * AirPlay 1 does not tell a receiver the sender's name. Measured against
 * macOS 26: every request carries `CSeq`, `DACP-ID`, `Active-Remote` and
 * `User-Agent: AirPlay/960.13.1`, and nothing else -- no `X-Apple-Client-Name`,
 * no `Client-Instance`. So the name has to be found on the network instead,
 * and it takes two hops.
 *
 * **One: which address is the sender?** `DACP-ID` names a Bonjour service the
 * sender advertises for its own remote control, and resolving it gives an
 * address:
 *
 *     DACP-ID: 20BC6070E22D669E
 *     -> iTunes_Ctrl_20BC6070E22D669E._dacp._tcp   -> 192.168.100.134
 *
 * An address and not a name, and that is the whole reason for the second hop.
 * `dns-sd` shows this service pointing at `Walrus.local`, but that hostname
 * lives in the SRV record's target, which `NsdManager` resolves away and never
 * exposes. Reading it would mean writing an mDNS client, and the two obvious
 * shortcuts are both dead ends -- measured: the phone cannot resolve
 * `Walrus.local` at all (`ping: unknown host`), and the Mac answers a reverse
 * PTR for its own address with `No Such Record`.
 *
 * **Two: what is that address called?** `_companion-link._tcp` -- Apple's
 * Continuity service, advertised by Macs and iPhones alike -- carries the
 * friendly name as its *instance name*, which `NsdManager` does give us. So
 * the instances are resolved and matched against the address from the first
 * hop:
 *
 *     _companion-link._tcp  "Walrus"  -> 192.168.100.134  -- match
 *
 * Both hops are anchored on addresses that came back through the same resolver,
 * rather than on the RTSP peer address. The sender may well have connected over
 * IPv6 -- macOS was seen doing exactly that -- and comparing an IPv6 peer
 * against an IPv4 advertisement would never match.
 *
 * Best-effort throughout. Every step can fail and the screen simply keeps the
 * fallback it already had. Nothing here is on the audio path, and a name is
 * never worth delaying playback for.
 */
class DacpSenderName(private val context: Context) {

    private var manager: NsdManager? = null
    private val active = ArrayList<NsdManager.DiscoveryListener>()
    private val finished = AtomicBoolean(false)

    /**
     * Finds the name behind [dacpId] and calls [onName] if there is one.
     *
     * [onName] fires at most once, off the calling thread, and only ever with
     * a real name -- never a placeholder, because a placeholder on screen is
     * worse than the honest fallback it replaces.
     */
    fun resolve(dacpId: String, onName: (String) -> Unit) {
        stop()
        if (dacpId.isBlank()) return
        val nsd = context.getSystemService(Context.NSD_SERVICE) as? NsdManager ?: return
        manager = nsd
        finished.set(false)
        findSenderAddress(nsd, serviceName(dacpId)) { address ->
            nameForAddress(nsd, address, onName)
        }
    }

    /** Hop one: the sender's own remote-control service, resolved to an address. */
    private fun findSenderAddress(
        nsd: NsdManager,
        wanted: String,
        onAddress: (InetAddress) -> Unit,
    ) {
        val hit = AtomicBoolean(false)
        discover(nsd, DACP_TYPE) { info, listener ->
            if (info.serviceName != wanted || !hit.compareAndSet(false, true)) return@discover
            resolveService(nsd, info) { resolved ->
                stopOne(nsd, listener)
                val address = resolved.host
                if (address == null) {
                    Log.i(TAG, "airplay: $wanted resolved to no address")
                    stop()
                } else {
                    onAddress(address)
                }
            }
        }
    }

    /** Hop two: whichever Continuity advertisement shares that address. */
    private fun nameForAddress(
        nsd: NsdManager,
        address: InetAddress,
        onName: (String) -> Unit,
    ) {
        discover(nsd, COMPANION_TYPE) { info, listener ->
            val candidate = friendlyName(info.serviceName) ?: return@discover
            resolveService(nsd, info) { resolved ->
                if (resolved.host != address || !finished.compareAndSet(false, true)) return@resolveService
                Log.i(TAG, "airplay: sender is '$candidate' at ${address.hostAddress}")
                stopOne(nsd, listener)
                runCatching { onName(candidate) }
                stop()
            }
        }
    }

    /**
     * Browses [type], handing each found service to [onFound].
     *
     * Discovery is used rather than resolving a hand-built [NsdServiceInfo]:
     * the documented flow is discover-then-resolve, and a manually built info
     * resolves on some Android versions and silently never calls back on
     * others -- a callback that never fires reads as "the feature just does
     * not work sometimes", which is the worst kind of bug to be handed.
     */
    private fun discover(
        nsd: NsdManager,
        type: String,
        onFound: (NsdServiceInfo, NsdManager.DiscoveryListener) -> Unit,
    ) {
        lateinit var listener: NsdManager.DiscoveryListener
        listener = object : NsdManager.DiscoveryListener {
            override fun onServiceFound(info: NsdServiceInfo) = onFound(info, listener)
            override fun onServiceLost(info: NsdServiceInfo) {}
            override fun onDiscoveryStarted(t: String) {}
            override fun onDiscoveryStopped(t: String) {}
            override fun onStartDiscoveryFailed(t: String, errorCode: Int) {
                Log.i(TAG, "airplay: $t discovery would not start (error $errorCode)")
            }
            override fun onStopDiscoveryFailed(t: String, errorCode: Int) {}
        }
        synchronized(active) { active.add(listener) }
        runCatching { nsd.discoverServices(type, NsdManager.PROTOCOL_DNS_SD, listener) }
            .onFailure {
                Log.i(TAG, "airplay: $type discovery failed: ${it.message}")
                synchronized(active) { active.remove(listener) }
            }
    }

    private fun resolveService(
        nsd: NsdManager,
        info: NsdServiceInfo,
        onResolved: (NsdServiceInfo) -> Unit,
    ) {
        @Suppress("DEPRECATION")   // the callback API is API 34+; minSdk here is 26
        nsd.resolveService(info, object : NsdManager.ResolveListener {
            override fun onServiceResolved(resolved: NsdServiceInfo) {
                // Off the callback thread: this ends in a resolver comparison
                // and then a UI-visible write, and the callback may be on the
                // main looper.
                Thread({ runCatching { onResolved(resolved) } }, "raop-sender-name").start()
            }

            override fun onResolveFailed(failed: NsdServiceInfo, errorCode: Int) {
                Log.i(TAG, "airplay: could not resolve ${failed.serviceName} (error $errorCode)")
            }
        })
    }

    private fun stopOne(nsd: NsdManager, listener: NsdManager.DiscoveryListener) {
        val removed = synchronized(active) { active.remove(listener) }
        if (removed) runCatching { nsd.stopServiceDiscovery(listener) }
    }

    fun stop() {
        val nsd = manager ?: return
        val listeners = synchronized(active) { ArrayList(active).also { active.clear() } }
        listeners.forEach { runCatching { nsd.stopServiceDiscovery(it) } }
    }

    companion object {
        private const val TAG = "hifirend"
        const val DACP_TYPE = "_dacp._tcp"

        /** Apple's Continuity service, whose instance name is the device's name. */
        const val COMPANION_TYPE = "_companion-link._tcp"

        /** The instance name a sender advertises its remote-control service under. */
        fun serviceName(dacpId: String): String = "iTunes_Ctrl_$dacpId"

        /**
         * Turns an advertised instance name into something worth showing, or
         * null.
         *
         * Two things get rejected. A trailing `.local` is Bonjour's, not part
         * of what anybody calls their computer. And an address is not a name --
         * a resolver hands one back when it has nothing better, and "AirPlay
         * from 192.168.100.134" tells the owner less than the honest "Unknown
         * track" it would have replaced.
         */
        fun friendlyName(host: String?): String? {
            val trimmed = host?.trim()?.trimEnd('.') ?: return null
            if (trimmed.isEmpty()) return null
            val name = trimmed.removeSuffix(".local").trim()
            if (name.isEmpty()) return null
            if (looksLikeAddress(name)) return null
            return name
        }

        private fun looksLikeAddress(s: String): Boolean {
            if (s.contains(':')) return true                    // IPv6
            val parts = s.split('.')
            return parts.size == 4 && parts.all { p ->
                p.isNotEmpty() && p.all { it.isDigit() }
            }
        }
    }
}
