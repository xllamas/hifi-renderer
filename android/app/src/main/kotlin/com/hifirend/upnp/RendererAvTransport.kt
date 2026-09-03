package com.hifirend.upnp

import android.util.Log
import org.jupnp.model.types.UnsignedIntegerFourBytes
import org.jupnp.support.avtransport.AbstractAVTransportService
import org.jupnp.support.model.DeviceCapabilities
import org.jupnp.support.model.MediaInfo
import org.jupnp.support.model.PositionInfo
import org.jupnp.support.model.StorageMedium
import org.jupnp.support.model.TransportAction
import org.jupnp.support.model.TransportInfo
import org.jupnp.support.model.TransportSettings
import org.jupnp.support.model.TransportState
import org.jupnp.support.model.TransportStatus

private const val TAG = "hifirend"

/**
 * AVTransport:1 — the service a DLNA controller drives.
 *
 * The controller pushes one track at a time via SetAVTransportURI /
 * SetNextAVTransportURI. Those are accumulated into a local queue so playback
 * continues after the controller disappears, which is an explicit requirement:
 * the phone is the renderer, not a remote-controlled speaker.
 *
 * M3 wires transport state and metadata only; hooking these to the USB engine
 * is M4. Every command is logged so real controllers' actual call sequences can
 * be observed rather than guessed at — they differ from each other considerably.
 */
class RendererAvTransport(
    private val queue: PlaylistQueue,
) : AbstractAVTransportService() {

    @Volatile
    var transportState: TransportState = TransportState.NO_MEDIA_PRESENT
        private set

    override fun setAVTransportURI(instanceId: UnsignedIntegerFourBytes?, uri: String?, metaData: String?) {
        Log.i(TAG, "AVTransport.SetAVTransportURI uri=$uri")
        if (uri.isNullOrBlank()) return
        queue.setCurrent(uri, metaData)
        transportState = TransportState.STOPPED
    }

    override fun setNextAVTransportURI(instanceId: UnsignedIntegerFourBytes?, uri: String?, metaData: String?) {
        Log.i(TAG, "AVTransport.SetNextAVTransportURI uri=$uri")
        if (uri.isNullOrBlank()) return
        queue.setNext(uri, metaData)
    }

    override fun getMediaInfo(instanceId: UnsignedIntegerFourBytes?): MediaInfo {
        val c = queue.current
        return MediaInfo(
            c?.uri ?: "",
            c?.metaData ?: "",
            UnsignedIntegerFourBytes(if (c == null) 0 else 1),
            "00:00:00",
            StorageMedium.NETWORK,
        )
    }

    override fun getTransportInfo(instanceId: UnsignedIntegerFourBytes?): TransportInfo =
        TransportInfo(transportState, TransportStatus.OK, "1")

    override fun getPositionInfo(instanceId: UnsignedIntegerFourBytes?): PositionInfo {
        val c = queue.current
        return PositionInfo(1, c?.metaData ?: "", c?.uri ?: "")
    }

    override fun getDeviceCapabilities(instanceId: UnsignedIntegerFourBytes?): DeviceCapabilities =
        DeviceCapabilities(arrayOf(StorageMedium.NETWORK))

    override fun getTransportSettings(instanceId: UnsignedIntegerFourBytes?): TransportSettings =
        TransportSettings()

    override fun stop(instanceId: UnsignedIntegerFourBytes?) {
        Log.i(TAG, "AVTransport.Stop")
        transportState = TransportState.STOPPED
    }

    override fun play(instanceId: UnsignedIntegerFourBytes?, speed: String?) {
        Log.i(TAG, "AVTransport.Play speed=$speed current=${queue.current?.uri}")
        transportState = if (queue.current == null) TransportState.NO_MEDIA_PRESENT
                         else TransportState.PLAYING
    }

    override fun pause(instanceId: UnsignedIntegerFourBytes?) {
        Log.i(TAG, "AVTransport.Pause")
        transportState = TransportState.PAUSED_PLAYBACK
    }

    override fun seek(instanceId: UnsignedIntegerFourBytes?, unit: String?, target: String?) {
        Log.i(TAG, "AVTransport.Seek unit=$unit target=$target")
    }

    override fun next(instanceId: UnsignedIntegerFourBytes?) {
        Log.i(TAG, "AVTransport.Next")
        queue.advance()
    }

    override fun previous(instanceId: UnsignedIntegerFourBytes?) {
        Log.i(TAG, "AVTransport.Previous")
    }

    // Recording is meaningless for a renderer, but the service definition
    // requires the actions to exist.
    override fun record(instanceId: UnsignedIntegerFourBytes?) = Unit

    override fun setPlayMode(instanceId: UnsignedIntegerFourBytes?, newPlayMode: String?) {
        Log.i(TAG, "AVTransport.SetPlayMode $newPlayMode")
    }

    override fun setRecordQualityMode(instanceId: UnsignedIntegerFourBytes?, newMode: String?) = Unit

    override fun getCurrentTransportActions(instanceId: UnsignedIntegerFourBytes?): Array<TransportAction> =
        when (transportState) {
            TransportState.PLAYING ->
                arrayOf(TransportAction.Stop, TransportAction.Pause, TransportAction.Seek, TransportAction.Next)
            TransportState.PAUSED_PLAYBACK ->
                arrayOf(TransportAction.Play, TransportAction.Stop, TransportAction.Seek)
            TransportState.STOPPED ->
                arrayOf(TransportAction.Play, TransportAction.Seek)
            else -> arrayOf(TransportAction.Play)
        }

    override fun getCurrentInstanceIds(): Array<UnsignedIntegerFourBytes> =
        arrayOf(getDefaultInstanceID())
}
