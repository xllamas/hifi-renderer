package com.hifirend.upnp

import android.util.Log
import org.jupnp.model.types.UnsignedIntegerFourBytes
import java.net.URI
import org.jupnp.support.avtransport.AbstractAVTransportService
import org.jupnp.support.avtransport.lastchange.AVTransportVariable
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
/** What AVTransport needs from the audio engine. */
interface PlaybackController {
    /** Returns a JSON result; failures are reported, not thrown. */
    fun play(uri: String, mimeType: String?): String
    /**
     * Starts a track into the stream already running, so the change of track
     * is inaudible. Only possible when the new track is the same rate, depth
     * and channel count; the engine falls back to a normal start otherwise.
     */
    fun playGapless(uri: String, mimeType: String?): String
    fun stop()
    fun pause()
    fun resume()
    fun seek(uri: String, seconds: Int, durationSeconds: Int): String
    fun onTrackChanged()
    fun positionSeconds(): Int
}

class RendererAvTransport(
    private val queue: PlaylistQueue,
    private val playback: PlaybackController? = null,
    /**
     * Called before this transport starts using the audio engine.
     *
     * A second protocol now wants the same DAC, and `UsbPlayback` force-claims
     * the interfaces -- so the appliance is told who is about to play and
     * stops whoever was. No-op while DLNA is the only source.
     */
    private val claimSource: () -> Unit = {},
) : AbstractAVTransportService() {

    private val positionProvider: (() -> Int)? = playback?.let { { it.positionSeconds() } }

    @Volatile
    var transportState: TransportState = TransportState.NO_MEDIA_PRESENT
        private set(value) {
            val changed = field != value
            field = value
            if (changed) publishState()
        }

    /**
     * Push the current state into LastChange.
     *
     * Controllers subscribe to these events and wait for them: without any
     * notification BubbleUPnP reports "Event Timeout" and a playlist stalls,
     * because it learns a track ended from an event rather than by polling.
     * jUPnP only accumulates here -- the service flushes with fireLastChange().
     */
    private fun publishState() {
        // Mirror into the process-wide snapshot the UI reads. Doing it here
        // keeps one source of truth: whatever controllers are told, the screen
        // shows.
        com.hifirend.RendererState.let { st ->
            st.transportState = transportState.name
            // Same rule as the OpenHome source: a badge describes a running
            // stream, and stopped is not one. Paused keeps it.
            if (transportState != TransportState.PLAYING &&
                transportState != TransportState.PAUSED_PLAYBACK &&
                transportState != TransportState.TRANSITIONING) st.clearFormat()
            queue.current?.track?.let { t ->
                st.title = t.title
                st.artist = t.artist
                st.album = t.album
                st.albumArtUri = t.albumArtUri
                st.durationSeconds = t.durationSeconds
            }
            if (queue.current == null) st.clearTrack()
            // Only ask the engine where it is while it is somewhere. Reading a
            // stopped engine hands back whatever it last held, which would put
            // the elapsed time straight back after clearFormat() zeroed it.
            st.positionSeconds = when (transportState) {
                TransportState.PLAYING,
                TransportState.PAUSED_PLAYBACK,
                TransportState.TRANSITIONING -> playback?.positionSeconds() ?: 0
                else -> 0
            }
        }

        try {
            val c = queue.current
            val values = mutableListOf<org.jupnp.support.lastchange.EventedValue<*>>(
                AVTransportVariable.TransportState(transportState),
                AVTransportVariable.CurrentTransportActions(getCurrentTransportActions(null)),
            )
            if (c != null) {
                runCatching { values += AVTransportVariable.CurrentTrackURI(URI(c.uri)) }
                values += AVTransportVariable.CurrentTrackMetaData(c.metaData ?: "")
                values += AVTransportVariable.CurrentTrackDuration(c.track.upnpDuration)
                values += AVTransportVariable.CurrentMediaDuration(c.track.upnpDuration)
            }
            lastChange.setEventedValue(getDefaultInstanceID(), *values.toTypedArray())
        } catch (e: Throwable) {
            // Eventing must never break playback.
            Log.w(TAG, "LastChange publish failed: ${e::class.java.simpleName}: ${e.message}")
        }
    }

    override fun setAVTransportURI(instanceId: UnsignedIntegerFourBytes?, uri: String?, metaData: String?) {
        Log.i(TAG, "AVTransport.SetAVTransportURI uri=$uri")
        if (uri.isNullOrBlank()) return
        claimSource()
        queue.setCurrent(uri, metaData)
        playback?.onTrackChanged()
        transportState = TransportState.STOPPED
        publishState()
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
            c?.track?.upnpDuration ?: "00:00:00",
            StorageMedium.NETWORK,
        )
    }

    override fun getTransportInfo(instanceId: UnsignedIntegerFourBytes?): TransportInfo =
        TransportInfo(transportState, TransportStatus.OK, "1")

    /**
     * Controllers poll this continuously — BubbleUPnP made 143 AVTransport
     * calls in one short test — so it must be cheap and must report a real
     * duration, or the controller's progress bar looks broken even when
     * playback is fine. [positionProvider] is supplied by the audio engine in
     * M4; until then elapsed time is reported as zero rather than faked.
     */
    override fun getPositionInfo(instanceId: UnsignedIntegerFourBytes?): PositionInfo {
        val c = queue.current ?: return PositionInfo()
        val duration = c.track.upnpDuration
        val elapsedSeconds = positionProvider?.invoke() ?: 0
        val elapsed = "%d:%02d:%02d".format(
            elapsedSeconds / 3600, (elapsedSeconds % 3600) / 60, elapsedSeconds % 60
        )
        // Use the 8-argument constructor. The 5-argument one skips
        // trackMetaData, so metadata silently lands in trackURI and the URI in
        // relTime -- the controller then shows XML where the track name goes.
        // relCount/absCount are Int.MAX_VALUE, the UPnP convention for
        // "counter not implemented".
        return PositionInfo(
            1L, duration, c.metaData ?: "", c.uri,
            elapsed, elapsed, Int.MAX_VALUE, Int.MAX_VALUE,
        )
    }

    override fun getDeviceCapabilities(instanceId: UnsignedIntegerFourBytes?): DeviceCapabilities =
        DeviceCapabilities(arrayOf(StorageMedium.NETWORK))

    override fun getTransportSettings(instanceId: UnsignedIntegerFourBytes?): TransportSettings =
        TransportSettings()

    override fun stop(instanceId: UnsignedIntegerFourBytes?) {
        Log.i(TAG, "AVTransport.Stop")
        playback?.stop()
        transportState = TransportState.STOPPED
    }

    /**
     * A track reached its natural end. If the controller queued a next track we
     * play it ourselves, which is what keeps the queue going after the
     * controller disconnects. Otherwise report STOPPED so a polling controller
     * knows to send the next one -- staying PLAYING forever is why playlists
     * appeared to stall.
     */
    /**
     * The audio engine failed after Play had already returned.
     *
     * Configuration happens on the decoder thread, once the file's real rate
     * and depth are known -- which is after SetAVTransportURI and Play have
     * both been answered. A failure there used to reach nobody: the transport
     * stayed PLAYING, the screen and the widget showed a running track, and the
     * only symptom was silence. Reporting STOPPED is what lets a controller,
     * and the user, see that something went wrong.
     */
    fun onPlaybackFailed(message: String) {
        Log.e(TAG, "engine failed during playback: $message")
        Problem.describe(message).let {
            com.hifirend.RendererState.lastError = it.code
            com.hifirend.RendererState.lastErrorArgs = it.args
            com.hifirend.RendererState.lastErrorDetail = it.detail
        }
        // Tear the stream down. Since a gapless hand-over leaves the sink
        // running, a failure after one would otherwise leave it playing an
        // empty ring for ever -- silence that reports itself as playback.
        playback?.stop()
        if (transportState == TransportState.PLAYING ||
            transportState == TransportState.PAUSED_PLAYBACK ||
            transportState == TransportState.TRANSITIONING) {
            transportState = TransportState.STOPPED
            publishState()
        }
    }

    /** The DAC went away mid-playback; report it rather than pretending. */
    fun onDeviceLost() {
        if (transportState == TransportState.PLAYING ||
            transportState == TransportState.PAUSED_PLAYBACK) {
            Log.i(TAG, "device lost while $transportState; reporting STOPPED")
            transportState = TransportState.STOPPED
            publishState()
        }
    }

    /**
     * The decoder has run out of source while the tail is still playing.
     *
     * Advancing here rather than at the end is the whole of gapless: the next
     * track is opened and decoding into the same ring while a second of the
     * last one is still on its way to the DAC. Returns false when there is
     * nothing to advance to, leaving the tail to play out and the normal
     * end-of-track path to report it.
     */
    fun onSourceExhausted(): Boolean {
        val next = queue.advance() ?: return false
        Log.i(TAG, "gapless advance to ${next.uri}")
        unplayableRate(next.track.sampleFrequency)?.let { why ->
            // Refusing mid-handover would leave the tail playing with no way
            // to report it, so let the tail finish and fail the normal way.
            Log.i(TAG, "next track cannot play ($why); not handing over")
            queue.putBack(next)
            return false
        }
        val result = playback?.playGapless(next.uri, next.track.mimeType)
        if (result != null && !result.contains("\"ok\":true")) {
            Log.e(TAG, "gapless advance failed: $result")
            queue.putBack(next)
            return false
        }
        publishState()
        return true
    }

    fun onTrackFinished() {
        val next = queue.advance()
        if (next != null) {
            Log.i(TAG, "auto-advancing to ${next.uri}")
            // The same refusal as an explicit Play. A playlist reaching a
            // track the DAC cannot clock should say so, not fetch megabytes of
            // it first, and not look like the renderer simply stopped.
            unplayableRate(next.track.sampleFrequency)?.let { why ->
                Log.i(TAG, "auto-advance refused before fetch: $why")
                com.hifirend.RendererState.lastError = why.code
                com.hifirend.RendererState.lastErrorArgs = why.args
                com.hifirend.RendererState.lastErrorDetail = null
                playback?.stop()
                transportState = TransportState.STOPPED
                publishState()
                return
            }
            val result = playback?.play(next.uri, next.track.mimeType)
            transportState = if (result != null && !result.contains("\"ok\":true")) {
                Log.e(TAG, "auto-advance failed: $result")
                TransportState.STOPPED
            } else {
                TransportState.PLAYING
            }
            publishState()
        } else {
            // Tear the engine down, not just the state. Leaving the sink
            // running on an empty ring makes it emit silence forever and count
            // an underrun per packet -- tens of thousands within a minute,
            // which also buries any real fault in noise.
            Log.i(TAG, "queue exhausted; stopping engine and reporting STOPPED")
            playback?.stop()
            transportState = TransportState.STOPPED
        }
    }

    override fun play(instanceId: UnsignedIntegerFourBytes?, speed: String?) {
        // Resuming from pause must continue, not restart: the stream is still
        // open and holding its position.
        if (transportState == TransportState.PAUSED_PLAYBACK) {
            Log.i(TAG, "AVTransport.Play (resume)")
            claimSource()
            playback?.resume()
            transportState = TransportState.PLAYING
            return
        }
        claimSource()

        val uri = queue.current?.uri
        Log.i(TAG, "AVTransport.Play speed=$speed current=$uri")
        if (uri == null) {
            transportState = TransportState.NO_MEDIA_PRESENT
            return
        }
        // Refuse before fetching anything, when the server has already said the
        // track is at a rate this DAC cannot clock.
        //
        // The alternative is to find out from the decoder, which means pulling
        // megabytes of a stream that was never going to play -- and a
        // controller that retries does it again each time. This is the
        // server's own claim rather than a measurement, so it is only acted on
        // when it is present and unambiguous; the decoder stays the authority
        // for everything else.
        unplayableRate(queue.current?.track?.sampleFrequency ?: 0)?.let { why ->
            Log.i(TAG, "refusing before fetch: $why")
            com.hifirend.RendererState.lastError = why.code
            com.hifirend.RendererState.lastErrorArgs = why.args
            com.hifirend.RendererState.lastErrorDetail = null
            transportState = TransportState.STOPPED
            publishState()
            return
        }

        val result = playback?.play(uri, queue.current?.track?.mimeType)
        if (result != null && !result.contains("\"ok\":true")) {
            // Report the failure through the transport state rather than
            // throwing: a SOAP fault here shows the controller a bare "501
            // Action Failed" with no explanation of what went wrong.
            Log.e(TAG, "AVTransport.Play failed: $result")
            transportState = TransportState.STOPPED
            // Explicit, because the setter only publishes on a *change* and
            // this path can already be STOPPED -- which would skip the mirror
            // that clears the format badge.
            publishState()
            return
        }
        transportState = TransportState.PLAYING
    }

    /**
     * A plain-language reason the announced track cannot play, or null when
     * there is no reason to think it cannot.
     */
    private fun unplayableRate(announced: Int): Problem.Described? {
        val rates = com.hifirend.RendererState.dacRates
        if (rates.isEmpty()) return null                    // capabilities unknown
        if (announced <= 0) return null                     // server said nothing
        if (rates.contains(announced)) return null
        return Problem.rateUnplayable(announced, rates.max())
    }

    private fun khz(hz: Int): String {
        val k = hz / 1000.0
        return if (k == k.toInt().toDouble()) "${k.toInt()} kHz" else "%.1f kHz".format(k)
    }

    override fun pause(instanceId: UnsignedIntegerFourBytes?) {
        Log.i(TAG, "AVTransport.Pause")
        playback?.pause()
        transportState = TransportState.PAUSED_PLAYBACK
    }

    override fun seek(instanceId: UnsignedIntegerFourBytes?, unit: String?, target: String?) {
        Log.i(TAG, "AVTransport.Seek unit=$unit target=$target")
        val c = queue.current ?: return
        // Controllers send REL_TIME for a slider drag; ABS_TIME is equivalent
        // for a single track. TRACK_NR is playlist navigation, not seeking.
        val seconds = when (unit?.uppercase()) {
            "REL_TIME", "ABS_TIME", null -> TrackMetadata.parseDuration(target)
            else -> {
                Log.i(TAG, "Seek unit $unit not supported")
                return
            }
        }
        val result = playback?.seek(c.uri, seconds, c.track.durationSeconds)
        if (result != null && !result.contains("\"ok\":true")) {
            Log.e(TAG, "Seek failed: $result")
            return
        }
        transportState = TransportState.PLAYING
        publishState()
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
