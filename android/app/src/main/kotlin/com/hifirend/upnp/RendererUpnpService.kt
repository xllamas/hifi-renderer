package com.hifirend.upnp

import android.content.Context
import android.util.Log
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import androidx.core.app.ServiceCompat
import com.hifirend.NativeBridge
import com.hifirend.RendererControl
import com.hifirend.ServiceHealth
import com.hifirend.power.ScreenPolicy
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
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

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

    // jUPnP only accumulates LastChange values; the NOTIFY is sent when
    // fireLastChange() is called, so it needs flushing on a timer.
    private val lastChangeManagers = mutableListOf<LastChangeAwareServiceManager<*>>()
    private var eventFlusher: ScheduledExecutorService? = null
    private val playback by lazy { HttpStreamPlayback(applicationContext) }

    /** Bridges AVTransport commands to the USB audio engine. */
    private val controller = object : PlaybackController {
        override fun play(uri: String, mimeType: String?): String {
            // Playback starting is exactly when the spec wants the screen back.
            screenPolicy.wakeForPlayback()
            val result = playback.play(uri, mimeHint = mimeType ?: "")
            refreshNotification(playing = result.contains("\"ok\":true"))
            return result
        }
        override fun stop() {
            playback.stop()
            refreshNotification(playing = false)
        }
        override fun pause() = playback.pause()
        override fun resume() = playback.resume()
        override fun seek(uri: String, seconds: Int, durationSeconds: Int): String =
            playback.seek(uri, seconds, durationSeconds)
        override fun onTrackChanged() = playback.resetHeaderCache()
        override fun positionSeconds(): Int = playback.positionSeconds()
    }

    /**
     * Flushes accumulated LastChange events. 500 ms is well inside the
     * patience of controllers that report "Event Timeout", while still
     * coalescing bursts of state changes into one notification.
     */
    private fun startEventFlusher() {
        eventFlusher = Executors.newSingleThreadScheduledExecutor { r ->
            Thread(r, "upnp-events").apply { isDaemon = true }
        }.also { exec ->
            exec.scheduleWithFixedDelay({
                for (m in lastChangeManagers) {
                    runCatching { m.fireLastChange() }
                        .onFailure { Log.w(TAG, "fireLastChange failed: ${it.message}") }
                }
            }, 500, 500, TimeUnit.MILLISECONDS)
        }
        Log.i(TAG, "LastChange event flusher started")
    }

    /** Rebuilds the notification from whatever the queue currently holds. */
    fun refreshNotification(playing: Boolean) {
        val t = queue.current?.track
        val title = t?.title ?: friendlyName()
        val subtitle = listOfNotNull(t?.artist, t?.album).joinToString(" — ")
            .ifBlank { if (playing) "Playing" else null }
        updateNotification(title, subtitle, playing)
    }

    /**
     * Updates the notification as the track changes, so the renderer shows what
     * it is playing while the app is closed.
     */
    fun updateNotification(title: String?, subtitle: String?, playing: Boolean) =
        startForegroundSafely(title, subtitle, playing)

    private fun startForegroundSafely(title: String?, subtitle: String?, playing: Boolean) {
        val notification = RendererNotification.build(
            this, friendlyName(), title, subtitle, playing
        )
        try {
            ServiceCompat.startForeground(
                this,
                RendererNotification.NOTIFICATION_ID,
                notification,
                if (android.os.Build.VERSION.SDK_INT >= 29)
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK else 0,
            )
        } catch (e: Throwable) {
            // Android 12+ can refuse a foreground start from the background, and
            // vendors add their own restrictions. The renderer still works while
            // the app is open, so this is reported rather than fatal.
            Log.e(TAG, "foreground start refused: ${e::class.java.simpleName}: ${e.message}")
        }
    }

    override fun onDestroy() {
        RendererControl.transport = null
        screenPolicy.shutdown()
        eventFlusher?.shutdownNow()
        playback.stop()
        health.recordServiceStop()
        super.onDestroy()
    }

    private val health by lazy { ServiceHealth(applicationContext) }
    val screenPolicy by lazy { ScreenPolicy(applicationContext) }

    /**
     * START_STICKY so Android brings the renderer back if it is killed for
     * memory. That is the difference between an appliance and an app.
     */
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return Service.START_STICKY
    }

    override fun onCreate() {
        super.onCreate()

        // Become a foreground service before anything else: the renderer has to
        // outlive the UI, and an ordinary started service is killed as soon as
        // the app leaves the screen -- MIUI especially.
        com.hifirend.RendererState.rendererName = friendlyName()
        RendererNotification.ensureChannel(this)
        startForegroundSafely(null, null, playing = false)
        health.recordServiceStart()

        try {
            // jUPnP 3.x separates construction from startup: the base class
            // creates the UpnpService but leaves it inactive, so the registry
            // does not exist yet. Cling 2.x started in the constructor, which is
            // why examples inherited from it omit this call.
            upnpService.startup()

            val device = buildDevice()
            upnpService.registry.addDevice(device)
            startEventFlusher()
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

        // The screen drives the renderer through the same transport the network
        // controllers use, so both produce identical state and events.
        RendererControl.transport = object : RendererControl.TransportCommands {
            override fun play() = av.play(null, "1")
            override fun pause() = av.pause(null)
            override fun stop() = av.stop(null)
            override fun dacVolume(): Int? = NativeBridge.getDacVolume().takeIf { it >= 0 }
            override fun setDacVolume(percent: Int): Boolean {
                val ok = NativeBridge.setDacVolume(percent)
                if (ok) com.hifirend.RendererState.dacVolume = percent
                return ok
            }
        }
        playback.onTrackFinished = { av.onTrackFinished() }
        // The manager creates its own instance by default; supply ours so the
        // queue and (from M4) the audio engine share one object.
        val avManager = object : LastChangeAwareServiceManager<RendererAvTransport>(
            avService, AVTransportLastChangeParser()
        ) {
            override fun createServiceInstance(): RendererAvTransport = av
        }
        avService.manager = avManager
        lastChangeManagers += avManager

        @Suppress("UNCHECKED_CAST")
        val rcService =
            binder.read(RendererRenderingControl::class.java) as LocalService<RendererRenderingControl>
        val rc = RendererRenderingControl()
        val rcManager = object : LastChangeAwareServiceManager<RendererRenderingControl>(
            rcService, RenderingControlLastChangeParser()
        ) {
            override fun createServiceInstance(): RendererRenderingControl = rc
        }
        rcService.manager = rcManager
        lastChangeManagers += rcManager

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
