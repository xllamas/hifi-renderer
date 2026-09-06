package com.hifirend.upnp.openhome

import android.util.Log
import com.hifirend.RendererState
import com.hifirend.upnp.PlaybackController
import com.hifirend.upnp.Problem
import org.jupnp.binding.annotations.UpnpAction
import org.jupnp.binding.annotations.UpnpInputArgument
import org.jupnp.binding.annotations.UpnpOutputArgument
import org.jupnp.binding.annotations.UpnpService
import org.jupnp.binding.annotations.UpnpServiceId
import org.jupnp.binding.annotations.UpnpServiceType
import org.jupnp.binding.annotations.UpnpStateVariable
import org.jupnp.binding.annotations.UpnpStateVariables
import org.jupnp.model.types.UnsignedIntegerFourBytes

private const val TAG = "hifirend"

/**
 * av.openhome.org:Playlist:1 — the renderer's own playlist.
 *
 * The controller fills this once and is then free to go away, which is the
 * entire reason for the service and the one thing AVTransport cannot do.
 * Everything about advancing, repeating and shuffling happens here, on the
 * renderer, with no controller involved.
 *
 * State that controllers subscribe to is pushed through [propertyChangeSupport]
 * rather than a LastChange document: OpenHome events each variable directly,
 * unlike AVTransport. jUPnP finds this getter by reflection and wires GENA to
 * it (see DefaultServiceManager.createPropertyChangeSupport).
 */
@UpnpService(
    serviceId = UpnpServiceId(namespace = "av-openhome-org", value = "Playlist"),
    serviceType = UpnpServiceType(namespace = "av-openhome-org", value = "Playlist", version = 1),
)
@UpnpStateVariables(
    UpnpStateVariable(name = "TransportState", datatype = "string", sendEvents = true),
    UpnpStateVariable(name = "Repeat", datatype = "boolean", sendEvents = true),
    UpnpStateVariable(name = "Shuffle", datatype = "boolean", sendEvents = true),
    UpnpStateVariable(name = "Id", datatype = "ui4", sendEvents = true),
    UpnpStateVariable(name = "IdArray", datatype = "bin.base64", sendEvents = true),
    UpnpStateVariable(name = "TracksMax", datatype = "ui4", sendEvents = true),
    UpnpStateVariable(name = "ProtocolInfo", datatype = "string", sendEvents = true),
    // Argument-only variables. UPnP requires every action argument to name a
    // related state variable even when nothing ever subscribes to it, so these
    // exist purely to satisfy the description; sendEvents = false keeps them
    // out of the event message.
    UpnpStateVariable(name = "Uri", datatype = "string", sendEvents = false),
    UpnpStateVariable(name = "Metadata", datatype = "string", sendEvents = false),
    UpnpStateVariable(name = "IdList", datatype = "string", sendEvents = false),
    UpnpStateVariable(name = "TrackList", datatype = "string", sendEvents = false),
    UpnpStateVariable(name = "Index", datatype = "ui4", sendEvents = false),
    UpnpStateVariable(name = "Token", datatype = "ui4", sendEvents = false),
    UpnpStateVariable(name = "Changed", datatype = "boolean", sendEvents = false),
    UpnpStateVariable(name = "Seconds", datatype = "ui4", sendEvents = false),
    UpnpStateVariable(name = "SecondsRelative", datatype = "i4", sendEvents = false),
)
class OpenHomePlaylist(
    val list: OpenHomeTrackList,
    private val playback: PlaybackController? = null,
    /**
     * Called before anything starts playing, so the appliance can hand this
     * source the audio engine and stop whatever else was using it. Two
     * protocols share one DAC; without this they would both drive it.
     */
    private val claimSource: () -> Unit = {},
) {

    private val propertyChangeSupport =
        org.jupnp.internal.compat.java.beans.PropertyChangeSupport(this)

    fun getPropertyChangeSupport() = propertyChangeSupport

    /** OpenHome spells these Playing / Paused / Stopped / Buffering. */
    @Volatile
    var transportState: String = "Stopped"
        private set

    // ---- Transport ---------------------------------------------------------

    @UpnpAction(name = "Play")
    fun playAction() {
        Log.i(TAG, "OH.Playlist.Play")
        claimSource()
        if (transportState == "Paused") {
            playback?.resume()
            setTransportState("Playing")
            return
        }
        val track = list.current() ?: list.atIndex(0)
        if (track == null) {
            setTransportState("Stopped")
            return
        }
        startTrack(track, explicit = true)
    }

    @UpnpAction(name = "Pause")
    fun pauseAction() {
        Log.i(TAG, "OH.Playlist.Pause")
        playback?.pause()
        setTransportState("Paused")
    }

    @UpnpAction(name = "Stop")
    fun stopAction() {
        Log.i(TAG, "OH.Playlist.Stop")
        playback?.stop()
        setTransportState("Stopped")
    }

    @UpnpAction(name = "Next")
    fun nextAction() {
        Log.i(TAG, "OH.Playlist.Next")
        val n = list.next()
        if (n == null) {
            stopAction()
            return
        }
        claimSource()
        startTrack(n)
    }

    @UpnpAction(name = "Previous")
    fun previousAction() {
        Log.i(TAG, "OH.Playlist.Previous")
        val p = list.previous() ?: return
        claimSource()
        startTrack(p)
    }

    @UpnpAction(name = "SeekId")
    fun seekId(@UpnpInputArgument(name = "Value", stateVariable = "Id") value: UnsignedIntegerFourBytes?) {
        val id = value?.value?.toInt() ?: return
        Log.i(TAG, "OH.Playlist.SeekId $id")
        val t = list.byId(id) ?: return
        claimSource()
        startTrack(t, explicit = true)
    }

    @UpnpAction(name = "SeekIndex")
    fun seekIndex(@UpnpInputArgument(name = "Value", stateVariable = "Index") value: UnsignedIntegerFourBytes?) {
        val index = value?.value?.toInt() ?: return
        Log.i(TAG, "OH.Playlist.SeekIndex $index")
        val t = list.atIndex(index) ?: return
        claimSource()
        startTrack(t, explicit = true)
    }

    @UpnpAction(name = "SeekSecondAbsolute")
    fun seekSecondAbsolute(
        @UpnpInputArgument(name = "Value", stateVariable = "Seconds") value: UnsignedIntegerFourBytes?,
    ) {
        val seconds = value?.value?.toInt() ?: return
        val t = list.current() ?: return
        Log.i(TAG, "OH.Playlist.SeekSecondAbsolute $seconds")
        val result = playback?.seek(t.uri, seconds, t.track.durationSeconds)
        if (result != null && !result.contains("\"ok\":true")) {
            Log.e(TAG, "OH seek failed: $result")
            return
        }
        setTransportState("Playing")
    }

    @UpnpAction(name = "SeekSecondRelative")
    fun seekSecondRelative(
        @UpnpInputArgument(name = "Value", stateVariable = "SecondsRelative") value: Int?,
    ) {
        val delta = value ?: return
        val target = ((playback?.positionSeconds() ?: 0) + delta).coerceAtLeast(0)
        seekSecondAbsolute(UnsignedIntegerFourBytes(target.toLong()))
    }

    @UpnpAction(name = "TransportState", out = [UpnpOutputArgument(name = "Value", stateVariable = "TransportState")])
    fun transportStateAction(): String = transportState

    // ---- The list ----------------------------------------------------------

    @UpnpAction(name = "Id", out = [UpnpOutputArgument(name = "Value", stateVariable = "Id")])
    fun getId(): UnsignedIntegerFourBytes = UnsignedIntegerFourBytes(list.currentId.toLong())

    @UpnpAction(
        name = "Read",
        out = [
            UpnpOutputArgument(name = "Uri", stateVariable = "Uri", getterName = "getUri"),
            UpnpOutputArgument(name = "Metadata", stateVariable = "Metadata", getterName = "getMetadata"),
        ],
    )
    fun read(@UpnpInputArgument(name = "Id", stateVariable = "Id") id: UnsignedIntegerFourBytes?): TrackEntry {
        val t = list.byId(id?.value?.toInt() ?: 0)
        return TrackEntry(t?.uri ?: "", t?.metadata ?: "")
    }

    /** Read returns two values, which jUPnP takes from getters on a holder. */
    data class TrackEntry(private val uri: String, private val metadata: String) {
        fun getUri() = uri
        fun getMetadata() = metadata
    }

    @UpnpAction(name = "ReadList", out = [UpnpOutputArgument(name = "TrackList", stateVariable = "TrackList")])
    fun readList(@UpnpInputArgument(name = "IdList", stateVariable = "IdList") idList: String?): String =
        list.readListXml(idList ?: "")

    @UpnpAction(name = "Insert", out = [UpnpOutputArgument(name = "NewId", stateVariable = "Id")])
    fun insert(
        @UpnpInputArgument(name = "AfterId", stateVariable = "Id") afterId: UnsignedIntegerFourBytes?,
        @UpnpInputArgument(name = "Uri", stateVariable = "Uri") uri: String?,
        @UpnpInputArgument(name = "Metadata", stateVariable = "Metadata") metadata: String?,
    ): UnsignedIntegerFourBytes {
        val newId = list.insert(afterId?.value?.toInt() ?: 0, uri ?: "", metadata ?: "")
        if (newId == null) {
            // 800 is the spec's "invalid id"; a full playlist is 801. Both are
            // reported as faults so the controller can say which happened
            // rather than silently dropping the track.
            throw org.jupnp.model.action.ActionException(
                org.jupnp.model.types.ErrorCode.ARGUMENT_VALUE_INVALID,
                if (list.size >= list.tracksMax) "Playlist full" else "Invalid AfterId",
            )
        }
        publishIdArray()
        return UnsignedIntegerFourBytes(newId.toLong())
    }

    @UpnpAction(name = "DeleteId")
    fun deleteId(@UpnpInputArgument(name = "Value", stateVariable = "Id") value: UnsignedIntegerFourBytes?) {
        val id = value?.value?.toInt() ?: return
        // Deleting the track that is playing has to stop it. Leaving the engine
        // running on a track no longer in the list is the stale-state failure
        // the rest of this app works hard to avoid.
        val wasCurrent = id == list.currentId
        if (!list.delete(id)) return
        if (wasCurrent) {
            playback?.stop()
            setTransportState("Stopped")
        }
        publishIdArray()
    }

    @UpnpAction(name = "DeleteAll")
    fun deleteAll() {
        Log.i(TAG, "OH.Playlist.DeleteAll")
        list.deleteAll()
        playback?.stop()
        setTransportState("Stopped")
        RendererState.clearTrack()
        publishIdArray()
    }

    @UpnpAction(name = "TracksMax", out = [UpnpOutputArgument(name = "Value", stateVariable = "TracksMax")])
    fun getTracksMax(): UnsignedIntegerFourBytes = UnsignedIntegerFourBytes(list.tracksMax.toLong())

    @UpnpAction(
        name = "IdArray",
        out = [
            UpnpOutputArgument(name = "Token", stateVariable = "Token", getterName = "getToken"),
            UpnpOutputArgument(name = "Array", stateVariable = "IdArray", getterName = "getArray"),
        ],
    )
    fun idArrayAction(): IdArrayResult =
        IdArrayResult(UnsignedIntegerFourBytes(list.token.toLong()), list.idArrayBytes())

    /**
     * The evented accessor for IdArray, which must be the bare bytes.
     *
     * jUPnP reads this to build the initial event a controller gets when it
     * subscribes; the action above answers with the token as well, and letting
     * one method serve both binds cleanly and then fails at the first event.
     */
    fun getIdArray(): ByteArray = list.idArrayBytes()

    data class IdArrayResult(
        private val token: UnsignedIntegerFourBytes,
        private val array: ByteArray,
    ) {
        fun getToken() = token
        fun getArray() = array
    }

    /**
     * Lets a controller find out whether its cached list is stale without
     * transferring it. Controllers poll this constantly, so it must stay a
     * comparison of two integers.
     */
    @UpnpAction(name = "IdArrayChanged", out = [UpnpOutputArgument(name = "Value", stateVariable = "Changed")])
    fun idArrayChanged(
        @UpnpInputArgument(name = "Token", stateVariable = "Token") token: UnsignedIntegerFourBytes?,
    ): Boolean = (token?.value?.toInt() ?: -1) != list.token

    @UpnpAction(name = "ProtocolInfo", out = [UpnpOutputArgument(name = "Value", stateVariable = "ProtocolInfo")])
    fun protocolInfoAction(): String = protocolInfo

    @Volatile
    var protocolInfo: String = ""

    // ---- Modes -------------------------------------------------------------

    @UpnpAction(name = "SetRepeat")
    fun setRepeat(@UpnpInputArgument(name = "Value", stateVariable = "Repeat") value: Boolean?) {
        list.repeat = value ?: false
        fire("Repeat", list.repeat)
    }

    @UpnpAction(name = "Repeat", out = [UpnpOutputArgument(name = "Value", stateVariable = "Repeat")])
    fun getRepeat(): Boolean = list.repeat

    @UpnpAction(name = "SetShuffle")
    fun setShuffle(@UpnpInputArgument(name = "Value", stateVariable = "Shuffle") value: Boolean?) {
        list.shuffle = value ?: false
        fire("Shuffle", list.shuffle)
    }

    @UpnpAction(name = "Shuffle", out = [UpnpOutputArgument(name = "Value", stateVariable = "Shuffle")])
    fun getShuffle(): Boolean = list.shuffle

    // ---- Engine-driven transitions ----------------------------------------

    /**
     * Starts [track] and takes the screen with it.
     *
     * The refusal before fetching mirrors AVTransport's: a playlist that
     * reaches a rate the DAC cannot clock should say so rather than pull
     * megabytes of a track that was never going to play.
     */
    private fun startTrack(track: OpenHomeTrack, explicit: Boolean = false) {
        list.setCurrent(track.id, anchorShuffle = explicit)
        publishTrack()
        unplayableRate(track.track.sampleFrequency)?.let { why ->
            Log.i(TAG, "OH refusing before fetch: $why")
            RendererState.lastError = why
            RendererState.lastErrorDetail = null
            playback?.stop()
            setTransportState("Stopped")
            return
        }
        playback?.onTrackChanged()
        val result = playback?.play(track.uri, track.track.mimeType)
        if (result != null && !result.contains("\"ok\":true")) {
            Log.e(TAG, "OH play failed: $result")
            setTransportState("Stopped")
            return
        }
        setTransportState("Playing")
    }

    /** A track ended naturally; advance without anyone asking us to. */
    fun onTrackFinished() {
        val n = list.next()
        if (n == null) {
            Log.i(TAG, "OH playlist exhausted; stopping")
            playback?.stop()
            setTransportState("Stopped")
            return
        }
        Log.i(TAG, "OH auto-advancing to ${n.uri}")
        startTrack(n)
    }

    /**
     * The decoder ran out of source while the tail is still playing, so the
     * next track can be handed over inaudibly. Same contract as AVTransport's:
     * false means "could not", and the normal end-of-track path then runs.
     */
    fun onSourceExhausted(): Boolean {
        val n = list.next() ?: return false
        if (unplayableRate(n.track.sampleFrequency) != null) return false
        val previousId = list.currentId
        list.setCurrent(n.id)
        val result = playback?.playGapless(n.uri, n.track.mimeType)
        if (result != null && !result.contains("\"ok\":true")) {
            Log.e(TAG, "OH gapless advance failed: $result")
            list.setCurrent(previousId)
            return false
        }
        publishTrack()
        fire("Id", list.currentId)
        return true
    }

    fun onPlaybackFailed(message: String) {
        Log.e(TAG, "OH engine failed: $message")
        Problem.describe(message).let {
            RendererState.lastError = it.headline
            RendererState.lastErrorDetail = it.detail
        }
        playback?.stop()
        setTransportState("Stopped")
    }

    fun onDeviceLost() {
        if (transportState == "Playing" || transportState == "Paused") {
            playback?.stop()
            setTransportState("Stopped")
        }
    }

    private fun unplayableRate(announced: Int): String? {
        val rates = RendererState.dacRates
        if (rates.isEmpty() || announced <= 0 || rates.contains(announced)) return null
        val ceiling = rates.max()
        return "This DAC cannot play ${khz(announced)}; its highest rate is ${khz(ceiling)}."
    }

    private fun khz(hz: Int): String {
        val k = hz / 1000.0
        return if (k == k.toInt().toDouble()) "${k.toInt()} kHz" else "%.1f kHz".format(k)
    }

    // ---- Eventing ----------------------------------------------------------

    fun setTransportState(state: String) {
        if (transportState == state) return
        transportState = state
        // One source of truth with the DLNA path: the screen and the widget
        // read RendererState, and they must not care which protocol is driving.
        RendererState.transportState = when (state) {
            "Playing" -> "PLAYING"
            "Paused" -> "PAUSED_PLAYBACK"
            "Buffering" -> "TRANSITIONING"
            else -> "STOPPED"
        }
        fire("TransportState", state)
    }

    private fun publishTrack() {
        val t = list.current()?.track
        RendererState.let { st ->
            if (t == null) st.clearTrack() else {
                st.title = t.title
                st.artist = t.artist
                st.album = t.album
                st.albumArtUri = t.albumArtUri
                st.durationSeconds = t.durationSeconds
            }
        }
        fire("Id", list.currentId)
    }

    fun publishIdArray() {
        fire("IdArray", list.idArrayBytes())
    }

    private fun fire(name: String, value: Any?) {
        // Eventing must never break playback -- the same rule AVTransport's
        // LastChange publish follows, for the same reason.
        runCatching { propertyChangeSupport.firePropertyChange(name, null, value) }
            .onFailure { Log.w(TAG, "OH event $name failed: ${it.message}") }
    }
}
