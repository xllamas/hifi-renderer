package com.hifirend.upnp

import android.content.Context
import android.util.Log
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.BroadcastReceiver
import android.content.IntentFilter
import android.hardware.usb.UsbManager
import android.net.ConnectivityManager
import android.net.Network
import androidx.core.app.ServiceCompat
import com.hifirend.NativeBridge
import com.hifirend.RendererControl
import com.hifirend.ServiceHealth
import com.hifirend.power.ScreenPolicy
import com.hifirend.usb.HttpStreamPlayback
import com.hifirend.widget.RendererWidget
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
private const val KEY_SERVER_CONVERSION = "allow_server_conversion"

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
    private var renderingControl: RendererRenderingControl? = null
    private var connectionManager: ConnectionManagerService? = null
    /** Last volume announced to controllers, to avoid re-eventing every tick. */
    @Volatile private var publishedVolume = -1
    /** The output device the advertised capabilities currently describe. */
    @Volatile private var advertisedDeviceKey: String? = null
    private var eventFlusher: ScheduledExecutorService? = null

    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private val networkExecutor: ScheduledExecutorService =
        Executors.newSingleThreadScheduledExecutor { r ->
            Thread(r, "upnp-network").apply { isDaemon = true }
        }
    @Volatile private var lastRebindAt = 0L
    private var usbReceiver: BroadcastReceiver? = null
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
     * Watches the DAC coming and going.
     *
     * Hot-plugging is normal for this app -- people switch DACs, and a DAC on a
     * shared hub loses power when the amp does. On detach the stream has to be
     * torn down deliberately, otherwise the engine keeps writing to a file
     * descriptor that no longer has a device behind it.
     */
    private fun startUsbWatcher() {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                val probe = com.hifirend.usb.UsbAudioProbe(applicationContext)
                when (intent.action) {
                    UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                        Log.i(TAG, "USB device detached; stopping playback")
                        runCatching { playback.stop() }
                        avTransport?.let { it.onDeviceLost() }
                    }
                    UsbManager.ACTION_USB_DEVICE_ATTACHED ->
                        Log.i(TAG, "USB device attached")
                }
                runCatching { probe.refreshDacPresence() }
                refreshNotification(playing = false)
                runCatching { RendererWidget.refresh(applicationContext, force = true) }
                // A different DAC accepts different formats, and a controller
                // that discovered us before the swap still believes the old set.
                // No-ops when the selected device is unchanged.
                runCatching { onOutputDeviceChanged() }
            }
        }
        usbReceiver = receiver
        val filter = IntentFilter().apply {
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        // These are system broadcasts, so the receiver must be exported-safe;
        // NOT_EXPORTED is correct because nothing else should reach it.
        androidx.core.content.ContextCompat.registerReceiver(
            this, receiver, filter,
            androidx.core.content.ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        Log.i(TAG, "USB attach/detach watcher registered")
    }

    /**
     * Rebinds the UPnP router when the network changes.
     *
     * jUPnP enumerates interfaces once at startup and binds what it finds. On a
     * dedicated phone that is almost always too early: the service starts at
     * boot before Wi-Fi associates, finds no multicast-capable interface, and
     * the renderer is silently absent from the network for the rest of the
     * session. It also never notices a reconnect or an address change.
     *
     * jUPnP's own AndroidRouter watches for this using the legacy
     * CONNECTIVITY_ACTION broadcast and NetworkInfo, neither of which is
     * delivered reliably on modern Android, so this uses the current callback
     * API instead.
     */
    private fun startNetworkWatcher() {
        val cm = getSystemService(ConnectivityManager::class.java) ?: return
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = rebindRouter("network available")
            override fun onLost(network: Network) = rebindRouter("network lost")
        }
        networkCallback = cb
        try {
            cm.registerDefaultNetworkCallback(cb)
            Log.i(TAG, "network watcher registered")
        } catch (e: Throwable) {
            Log.w(TAG, "network watcher unavailable: ${e.message}")
            networkCallback = null
        }
    }

    private fun rebindRouter(reason: String) {
        // Connectivity callbacks arrive in bursts while an interface settles;
        // rebinding on each one would restart the stack repeatedly.
        val now = System.currentTimeMillis()
        if (now - lastRebindAt < 2_000) return
        lastRebindAt = now

        networkExecutor.schedule({
            try {
                val router = upnpService.router
                router.disable()
                router.enable()
                // Re-announce, or controllers that saw the old address keep it.
                upnpService.registry.localDevices.forEach {
                    runCatching { upnpService.registry.removeDevice(it) }
                    runCatching { upnpService.registry.addDevice(it) }
                }
                Log.i(TAG, "router rebound after $reason")
            } catch (e: Throwable) {
                Log.e(TAG, "router rebind failed: ${e::class.java.simpleName}: ${e.message}")
            }
        }, 1500, TimeUnit.MILLISECONDS)   // let the interface settle first
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
                // The home-screen widget is fed from the same tick: it needs
                // the position to move, and this is the one timer the service
                // already runs. refresh() compares what it would draw and
                // returns without any binder traffic when nothing changed, so
                // an idle renderer costs a string comparison twice a second.
                runCatching { RendererWidget.refresh(applicationContext) }
                    .onFailure { Log.w(TAG, "widget refresh failed: ${it.message}") }

                // And the same tick carries volume the other way. The engine
                // reads the DAC's actual volume as it plays, so this is the one
                // place that sees a change made on the DAC's own knob, or from
                // the app's screen, and can tell subscribed controllers about
                // it. Guarded by the last published value so an unchanging
                // volume events nothing.
                runCatching { publishVolumeIfChanged() }
                    .onFailure { Log.w(TAG, "volume publish failed: ${it.message}") }
            }, 500, 500, TimeUnit.MILLISECONDS)
        }
        Log.i(TAG, "LastChange event flusher started")
    }

    private fun publishVolumeIfChanged() {
        val rc = renderingControl ?: return
        val v = com.hifirend.RendererState.dacVolume
        if (v < 0 || v == publishedVolume) return
        publishedVolume = v
        rc.onVolumeObserved(v)
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
    fun updateNotification(title: String?, subtitle: String?, playing: Boolean) {
        startForegroundSafely(title, subtitle, playing)
        // Not only for promptness: if UPnP registration failed there is no
        // event flusher, and this becomes the widget's only source of updates.
        runCatching { RendererWidget.refresh(applicationContext) }
    }

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
        networkCallback?.let { cb ->
            runCatching {
                getSystemService(ConnectivityManager::class.java)?.unregisterNetworkCallback(cb)
            }
        }
        usbReceiver?.let { runCatching { unregisterReceiver(it) } }
        networkExecutor.shutdownNow()
        RendererControl.transport = null
        RendererControl.onOutputDeviceChanged = null
        screenPolicy.shutdown()
        eventFlusher?.shutdownNow()
        playback.stop()
        // The widget outlives the service. Leaving it showing a paused track
        // that nothing can resume is the stale-state failure the whole
        // push-from-the-service design exists to avoid.
        com.hifirend.RendererState.transportState = "STOPPED"
        com.hifirend.RendererState.clearTrack()
        runCatching { RendererWidget.refresh(applicationContext, force = true) }
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
            startNetworkWatcher()
            startUsbWatcher()
            advertisedDeviceKey = runCatching {
                com.hifirend.usb.UsbAudioProbe(applicationContext).let { p ->
                    p.findAudioDevice()?.let { p.deviceKey(it) }
                }
            }.getOrNull()
            RendererWidget.refresh(applicationContext, force = true)
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
                if (ok) {
                    com.hifirend.RendererState.dacVolume = percent
                    // Opens the settle window so the status poll does not read
                    // back a stale value and undo this a moment later.
                    playback.noteVolumeSet()
                }
                return ok
            }
        }
        RendererControl.onOutputDeviceChanged = { force -> onOutputDeviceChanged(force) }
        playback.onTrackFinished = { av.onTrackFinished() }
        playback.onPlaybackError = { av.onPlaybackFailed(it) }
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
        // Wire the controller's volume to the DAC. Without this, SetVolume from
        // a DLNA controller was tracked and reported back but never reached the
        // hardware -- the spec's "pass volume changes to the DAC if accepted by
        // the device" was only ever half implemented.
        val rc = RendererRenderingControl { percent ->
            RendererControl.transport?.setDacVolume(percent) ?: false
        }
        renderingControl = rc
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
        connectionManager = cm
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
    private fun sinkFormats(): ProtocolInfos = SinkFormats.build(
        runCatching { com.hifirend.usb.UsbAudioProbe(applicationContext).selectedCapabilities() }
            .getOrNull(),
        // Off by default: advertising the formats we decode is what keeps
        // playback bit-perfect, and giving that up is the user's call, not a
        // default. See ServerConversion.
        allowNativeFormats = !ServerConversion.isEnabled(applicationContext),
    )

    /**
     * The output device changed, so what this renderer can accept changed with
     * it.
     *
     * Two things have to happen, because controllers learn protocolInfo two
     * different ways. Subscribers are told through the ConnectionManager's
     * evented SinkProtocolInfo. Everyone else read GetProtocolInfo once when
     * they discovered the device and will never ask again, so the device is
     * re-announced -- a byebye followed by an alive -- which is the only thing
     * that makes those controllers look again.
     */
    fun onOutputDeviceChanged(force: Boolean = false) {
        val cm = connectionManager ?: return

        // Re-announcing drops every controller's subscription, so it must not
        // happen on USB traffic that has nothing to do with the output -- a
        // phone running this is on a hub with Ethernet and whatever else, and
        // the watcher fires for all of it.
        val probe = com.hifirend.usb.UsbAudioProbe(applicationContext)
        val key = runCatching { probe.findAudioDevice()?.let { probe.deviceKey(it) } }.getOrNull()
        if (!force && key == advertisedDeviceKey) return
        advertisedDeviceKey = key

        val fresh = sinkFormats()
        try {
            val sink = cm.sinkProtocolInfo
            synchronized(cm) {
                sink.clear()
                sink.addAll(fresh)
            }
            // The evented variable, for controllers that subscribed.
            cm.propertyChangeSupport.firePropertyChange("SinkProtocolInfo", null, sink)
            Log.i(TAG, "sink protocolInfo updated for the new output device")
        } catch (e: Throwable) {
            Log.w(TAG, "could not update sink protocolInfo: ${e::class.java.simpleName}: ${e.message}")
        }
        reannounce("output device changed")
    }

    /**
     * Withdraws and re-advertises the device on SSDP.
     *
     * A controller caches the description and the protocol info from discovery.
     * Short of it re-discovering us, nothing we change afterwards reaches it.
     */
    private fun reannounce(reason: String) {
        networkExecutor.execute {
            try {
                upnpService.registry.localDevices.forEach {
                    runCatching { upnpService.registry.removeDevice(it) }
                    runCatching { upnpService.registry.addDevice(it) }
                }
                Log.i(TAG, "device re-announced after $reason")
            } catch (e: Throwable) {
                Log.e(TAG, "re-announce failed: ${e::class.java.simpleName}: ${e.message}")
            }
        }
    }
}
