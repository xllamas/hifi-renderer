package com.hifirend.airplay

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log

/**
 * Puts the renderer in an iPhone's AirPlay list.
 *
 * RAOP is found over mDNS as `_raop._tcp`, and two details are not optional.
 * The instance name must be `<twelve hex digits>@<friendly name>` -- senders
 * parse that prefix as the receiver's hardware address and some refuse a name
 * without it. And the TXT record is not decoration: it is the whole capability
 * negotiation, declaring the codec, the encryption and the channel layout
 * before any RTSP is spoken. A receiver with a plausible name and an empty TXT
 * record appears in Control Centre and then fails on connect, which is a much
 * worse failure than not appearing at all.
 *
 * The hardware address is derived from the renderer's UDN rather than read
 * from the Wi-Fi interface: Android stopped handing out the real MAC years ago
 * and returns a placeholder, while the UDN is already stable across restarts
 * and already the renderer's identity everywhere else. It only has to be
 * stable and unique on the network, and the UDN is both.
 */
class RaopAdvertiser(private val context: Context) {

    private var nsd: NsdManager? = null
    private var listener: NsdManager.RegistrationListener? = null

    /** The 12 hex digits senders read as a hardware address. */
    fun hardwareId(udn: String): String {
        val hex = udn.filter { it.isDigit() || it in 'a'..'f' || it in 'A'..'F' }.uppercase()
        return (hex + "000000000000").substring(0, 12)
    }

    fun hardwareAddressBytes(udn: String): ByteArray =
        hardwareId(udn).chunked(2).map { it.toInt(16).toByte() }.toByteArray()

    /**
     * The capability record. These values describe what this receiver will
     * actually accept, and each one is load-bearing:
     *
     *   `tp`   transports -- UDP only; we do not implement the TCP variant.
     *   `sm`   no metadata over the audio channel.
     *   `sv`   no volume control via this record (RTSP SET_PARAMETER carries it).
     *   `ek`   encryption key present: 1, because AirPlay 1 audio is AES.
     *   `et`   encryption types -- 0 (none) and 1 (RSA/AES), the pair every
     *          sender understands.
     *   `cn`   codecs -- 0 (PCM) and 1 (ALAC). AAC variants are deliberately
     *          absent: claiming them means being sent them.
     *   `ch`   two channels, `ss` 16 bits, `sr` 44100 -- AirPlay 1's only
     *          format, and exactly what the existing push-PCM path expects.
     *   `vn`   RSA version, always 3.
     *   `txtvers` record version, always 1.
     */
    fun txtRecords(): Map<String, String> = linkedMapOf(
        "txtvers" to "1",
        "ch" to "2",
        "cn" to "0,1",
        "et" to "0,1",
        "sv" to "false",
        "da" to "true",
        "sr" to "44100",
        "ss" to "16",
        "pw" to "false",
        "sm" to "false",
        "tp" to "UDP",
        "vn" to "3",
        "vs" to "105.1",
        "md" to "0,1,2",
        "am" to "AirPort10,115",
    )

    fun start(friendlyName: String, udn: String, port: Int) {
        stop()
        val manager = context.getSystemService(Context.NSD_SERVICE) as? NsdManager
        if (manager == null) {
            Log.w(TAG, "no NSD service; AirPlay cannot be advertised")
            return
        }
        val info = NsdServiceInfo().apply {
            serviceName = "${hardwareId(udn)}@$friendlyName"
            serviceType = "_raop._tcp"
            setPort(port)
            for ((k, v) in txtRecords()) setAttribute(k, v)
        }
        val reg = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(info: NsdServiceInfo) {
                Log.i(TAG, "AirPlay advertised as ${info.serviceName} on port $port")
            }
            override fun onRegistrationFailed(info: NsdServiceInfo, errorCode: Int) {
                Log.w(TAG, "AirPlay advertisement failed: error $errorCode")
            }
            override fun onServiceUnregistered(info: NsdServiceInfo) {
                Log.i(TAG, "AirPlay advertisement withdrawn")
            }
            override fun onUnregistrationFailed(info: NsdServiceInfo, errorCode: Int) {
                Log.w(TAG, "AirPlay withdrawal failed: error $errorCode")
            }
        }
        listener = reg
        nsd = manager
        runCatching { manager.registerService(info, NsdManager.PROTOCOL_DNS_SD, reg) }
            .onFailure { Log.w(TAG, "could not advertise AirPlay: ${it.message}") }
    }

    fun stop() {
        val manager = nsd
        val reg = listener
        if (manager != null && reg != null) {
            runCatching { manager.unregisterService(reg) }
        }
        nsd = null
        listener = null
    }

    private companion object {
        const val TAG = "hifirend"
    }
}
