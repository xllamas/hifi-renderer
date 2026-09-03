package com.hifirend.upnp

import android.content.Context
import android.util.Log
import com.hifirend.usb.HttpStreamPlayback
import org.jupnp.android.AndroidUpnpServiceImpl
import org.jupnp.binding.annotations.AnnotationLocalServiceBinder
import org.jupnp.model.DefaultServiceManager
import org.jupnp.model.meta.DeviceDetails
import org.jupnp.model.meta.DeviceIdentity
import org.jupnp.model.meta.LocalDevice
import org.jupnp.model.meta.LocalService
import org.jupnp.model.meta.ManufacturerDetails
import org.jupnp.model.meta.ModelDetails
import org.jupnp.model.types.UDADeviceType
import org.jupnp.model.types.UDN
import org.jupnp.support.avtransport.lastchange.AVTransportLastChangeParser
import org.jupnp.support.connectionmanager.ConnectionManagerService
import org.jupnp.support.lastchange.LastChangeAwareServiceManager
import org.jupnp.support.model.ProtocolInfo
import org.jupnp.support.model.ProtocolInfos
import org.jupnp.support.renderingcontrol.lastchange.RenderingControlLastChangeParser
import java.util.UUID

private const val TAG = "hifirend"
private const val PREFS = "hifirend_upnp"
private const val KEY_UDN = "udn"
private const val KEY_NAME = "friendly_name"

/**
 * Hosts the UPnP MediaRenderer device.
 *
 * Lives in a Service rather than the Flutter engine because the renderer must
 * keep answering the network when the UI is gone — the Flutter engine can be
 * destroyed at any moment, so nothing load-bearing may live in Dart.
 *
 * M3 stands this up and gets it discovered. Promotion to a foreground service
 * with a notification, boot-start and the always-on lifecycle is M6.
 */
class RendererUpnpService : AndroidUpnpServiceImpl() {

    val queue = PlaylistQueue()
    private var avTransport: RendererAvTransport? = null
    private val playback by lazy { HttpStreamPlayback(applicationContext) }

    /** Bridges AVTransport commands to the USB audio engine. */
    private val controller = object : PlaybackController {
        override fun play(uri: String): String = playback.play(uri)
        override fun stop() = playback.stop()
        override fun positionSeconds(): Int = playback.positionSeconds()
    }

    override fun onDestroy() {
        playback.stop()
        super.onDestroy()
    }

    override fun onCreate() {
        super.onCreate()
        try {
            // jUPnP 3.x separates construction from startup: the base class
            // creates the UpnpService but leaves it inactive, so the registry
            // does not exist yet. Cling 2.x started in the constructor, which is
            // why examples inherited from it omit this call.
            upnpService.startup()

            val device = buildDevice()
            upnpService.registry.addDevice(device)
            Log.i(TAG, "UPnP renderer registered: ${device.details.friendlyName} udn=${device.identity.udn}")
        } catch (e: Throwable) {
            // A renderer that fails to register must not take the app down; the
            // USB engine is independent and still useful.
            Log.e(TAG, "UPnP registration failed: ${e::class.java.simpleName}: ${e.message}", e)
        }
    }

    /**
     * The UDN must be stable across restarts, or controllers treat every launch
     * as a brand-new device and accumulate stale entries.
     */
    private fun stableUdn(): UDN {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val existing = prefs.getString(KEY_UDN, null)
        if (existing != null) return UDN(existing)
        val fresh = UUID.randomUUID().toString()
        prefs.edit().putString(KEY_UDN, fresh).apply()
        return UDN(fresh)
    }

    private fun friendlyName(): String =
        getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_NAME, null)
            ?: "HiFi Renderer"

    private fun buildDevice(): LocalDevice {
        val binder = AnnotationLocalServiceBinder()

        @Suppress("UNCHECKED_CAST")
        val avService =
            binder.read(RendererAvTransport::class.java) as LocalService<RendererAvTransport>
        val av = RendererAvTransport(queue, controller)
        avTransport = av
        // The manager creates its own instance by default; supply ours so the
        // queue and (from M4) the audio engine share one object.
        avService.manager = object : LastChangeAwareServiceManager<RendererAvTransport>(
            avService, AVTransportLastChangeParser()
        ) {
            override fun createServiceInstance(): RendererAvTransport = av
        }

        @Suppress("UNCHECKED_CAST")
        val rcService =
            binder.read(RendererRenderingControl::class.java) as LocalService<RendererRenderingControl>
        val rc = RendererRenderingControl()
        rcService.manager = object : LastChangeAwareServiceManager<RendererRenderingControl>(
            rcService, RenderingControlLastChangeParser()
        ) {
            override fun createServiceInstance(): RendererRenderingControl = rc
        }

        @Suppress("UNCHECKED_CAST")
        val cmService =
            binder.read(ConnectionManagerService::class.java) as LocalService<ConnectionManagerService>
        // (source, sink) -- a renderer is a SINK: it receives streams, it does
        // not serve them. Getting this backwards leaves GetProtocolInfo's Sink
        // empty, and controllers then refuse to send anything while still
        // showing the device as discovered, which looks like a broken renderer.
        val cm = ConnectionManagerService(ProtocolInfos(), sinkFormats())
        cmService.manager = object : DefaultServiceManager<ConnectionManagerService>(
            cmService, ConnectionManagerService::class.java
        ) {
            override fun createServiceInstance(): ConnectionManagerService = cm
        }

        return LocalDevice(
            DeviceIdentity(stableUdn()),
            UDADeviceType("MediaRenderer", 1),
            DeviceDetails(
                friendlyName(),
                ManufacturerDetails("HiFi Renderer"),
                ModelDetails("HiFi Renderer", "Bit-perfect USB audio renderer", "1"),
            ),
            arrayOf(avService, rcService, cmService),
        )
    }

    /**
     * GetProtocolInfo. Controllers consult this before sending anything, and
     * will refuse to send formats that are absent — so a missing entry here
     * looks like "the renderer is broken" rather than "that format is
     * unsupported".
     *
     * Declared for what M4 will decode. FLAC is the format that matters for a
     * hi-fi renderer; LPCM is what a bit-perfect path handles natively.
     */
    private fun sinkFormats(): ProtocolInfos = ProtocolInfos(
        ProtocolInfo("http-get:*:audio/L16:*"),
        ProtocolInfo("http-get:*:audio/L24:*"),
        ProtocolInfo("http-get:*:audio/wav:*"),
        ProtocolInfo("http-get:*:audio/x-wav:*"),
        ProtocolInfo("http-get:*:audio/flac:*"),
        ProtocolInfo("http-get:*:audio/x-flac:*"),
        ProtocolInfo("http-get:*:audio/mpeg:*"),
        ProtocolInfo("http-get:*:audio/mp4:*"),
        ProtocolInfo("http-get:*:audio/aac:*"),
        ProtocolInfo("http-get:*:audio/x-aiff:*"),
    )
}
