package com.hifirend.upnp.openhome

import com.hifirend.RendererState
import org.jupnp.binding.annotations.UpnpAction
import org.jupnp.binding.annotations.UpnpOutputArgument
import org.jupnp.binding.annotations.UpnpService
import org.jupnp.binding.annotations.UpnpServiceId
import org.jupnp.binding.annotations.UpnpServiceType
import org.jupnp.binding.annotations.UpnpStateVariable
import org.jupnp.binding.annotations.UpnpStateVariables
import org.jupnp.model.types.UnsignedIntegerFourBytes

/**
 * av.openhome.org:Info:1 — what is playing, and in what form.
 *
 * The Details action is the one place this app's central claim reaches an
 * OpenHome controller: BitDepth, SampleRate and Lossless come from what the
 * decoder actually produced, not from what the server advertised. A controller
 * showing 24/96 here is showing a measurement.
 */
@UpnpService(
    serviceId = UpnpServiceId(namespace = "av-openhome-org", value = "Info"),
    serviceType = UpnpServiceType(namespace = "av-openhome-org", value = "Info", version = 1),
)
@UpnpStateVariables(
    UpnpStateVariable(name = "TrackCount", datatype = "ui4", sendEvents = true),
    UpnpStateVariable(name = "DetailsCount", datatype = "ui4", sendEvents = true),
    UpnpStateVariable(name = "MetatextCount", datatype = "ui4", sendEvents = true),
    UpnpStateVariable(name = "Uri", datatype = "string", sendEvents = true),
    UpnpStateVariable(name = "Metadata", datatype = "string", sendEvents = true),
    UpnpStateVariable(name = "Duration", datatype = "ui4", sendEvents = true),
    UpnpStateVariable(name = "BitRate", datatype = "ui4", sendEvents = true),
    UpnpStateVariable(name = "BitDepth", datatype = "ui4", sendEvents = true),
    UpnpStateVariable(name = "SampleRate", datatype = "ui4", sendEvents = true),
    UpnpStateVariable(name = "Lossless", datatype = "boolean", sendEvents = true),
    UpnpStateVariable(name = "CodecName", datatype = "string", sendEvents = true),
    UpnpStateVariable(name = "Metatext", datatype = "string", sendEvents = true),
)
class OpenHomeInfo(private val currentTrack: () -> OpenHomeTrack?) {

    private val propertyChangeSupport =
        org.jupnp.internal.compat.java.beans.PropertyChangeSupport(this)

    fun getPropertyChangeSupport() = propertyChangeSupport

    /** Bumped so a polling controller can tell one track from the next. */
    @Volatile private var trackCount = 0
    @Volatile private var detailsCount = 0

    @UpnpAction(
        name = "Counters",
        out = [
            UpnpOutputArgument(name = "TrackCount", stateVariable = "TrackCount", getterName = "getTrackCount"),
            UpnpOutputArgument(name = "DetailsCount", stateVariable = "DetailsCount", getterName = "getDetailsCount"),
            UpnpOutputArgument(name = "MetatextCount", stateVariable = "MetatextCount", getterName = "getMetatextCount"),
        ],
    )
    fun getCounters() = Counters(
        UnsignedIntegerFourBytes(trackCount.toLong()),
        UnsignedIntegerFourBytes(detailsCount.toLong()),
        UnsignedIntegerFourBytes(0L),
    )

    data class Counters(
        private val trackCount: UnsignedIntegerFourBytes,
        private val detailsCount: UnsignedIntegerFourBytes,
        private val metatextCount: UnsignedIntegerFourBytes,
    ) {
        fun getTrackCount() = trackCount
        fun getDetailsCount() = detailsCount
        fun getMetatextCount() = metatextCount
    }

    @UpnpAction(
        name = "Track",
        out = [
            UpnpOutputArgument(name = "Uri", stateVariable = "Uri", getterName = "getUri"),
            UpnpOutputArgument(name = "Metadata", stateVariable = "Metadata", getterName = "getMetadata"),
        ],
    )
    fun getTrack(): OpenHomePlaylist.TrackEntry {
        val t = currentTrack()
        return OpenHomePlaylist.TrackEntry(t?.uri ?: "", t?.metadata ?: "")
    }

    @UpnpAction(
        name = "Details",
        out = [
            UpnpOutputArgument(name = "Duration", stateVariable = "Duration", getterName = "getDuration"),
            UpnpOutputArgument(name = "BitRate", stateVariable = "BitRate", getterName = "getBitRate"),
            UpnpOutputArgument(name = "BitDepth", stateVariable = "BitDepth", getterName = "getBitDepth"),
            UpnpOutputArgument(name = "SampleRate", stateVariable = "SampleRate", getterName = "getSampleRate"),
            UpnpOutputArgument(name = "Lossless", stateVariable = "Lossless", getterName = "getLossless"),
            UpnpOutputArgument(name = "CodecName", stateVariable = "CodecName", getterName = "getCodecName"),
        ],
    )
    fun getDetails(): Details {
        val format = RendererState.sourceFormat
        return Details(
            UnsignedIntegerFourBytes((currentTrack()?.track?.durationSeconds ?: 0).toLong()),
            UnsignedIntegerFourBytes(0L),   // bit rate is not measured; 0 is the spec's "unknown"
            UnsignedIntegerFourBytes(RendererState.sourceBits.toLong()),
            UnsignedIntegerFourBytes(RendererState.sourceRate.toLong()),
            isLossless(format),
            format ?: "",
        )
    }

    data class Details(
        private val duration: UnsignedIntegerFourBytes,
        private val bitRate: UnsignedIntegerFourBytes,
        private val bitDepth: UnsignedIntegerFourBytes,
        private val sampleRate: UnsignedIntegerFourBytes,
        private val lossless: Boolean,
        private val codecName: String,
    ) {
        fun getDuration() = duration
        fun getBitRate() = bitRate
        fun getBitDepth() = bitDepth
        fun getSampleRate() = sampleRate
        fun getLossless() = lossless
        fun getCodecName() = codecName
    }

    @UpnpAction(name = "Metatext", out = [UpnpOutputArgument(name = "Value", stateVariable = "Metatext")])
    fun getMetatext(): String = ""

    // Accessors for the evented variables. jUPnP reads these to build the
    // NOTIFY a controller gets the moment it subscribes -- which for OpenHome
    // is how it learns what is playing, rather than by polling the actions.
    fun getTrackCount(): UnsignedIntegerFourBytes = UnsignedIntegerFourBytes(trackCount.toLong())
    fun getDetailsCount(): UnsignedIntegerFourBytes = UnsignedIntegerFourBytes(detailsCount.toLong())
    fun getMetatextCount(): UnsignedIntegerFourBytes = UnsignedIntegerFourBytes(0L)
    fun getUri(): String = currentTrack()?.uri ?: ""
    fun getMetadata(): String = currentTrack()?.metadata ?: ""
    fun getDuration(): UnsignedIntegerFourBytes =
        UnsignedIntegerFourBytes((currentTrack()?.track?.durationSeconds ?: 0).toLong())
    fun getBitRate(): UnsignedIntegerFourBytes = UnsignedIntegerFourBytes(0L)
    fun getBitDepth(): UnsignedIntegerFourBytes =
        UnsignedIntegerFourBytes(RendererState.sourceBits.coerceAtLeast(0).toLong())
    fun getSampleRate(): UnsignedIntegerFourBytes =
        UnsignedIntegerFourBytes(RendererState.sourceRate.coerceAtLeast(0).toLong())
    fun getLossless(): Boolean = isLossless(RendererState.sourceFormat)
    fun getCodecName(): String = RendererState.sourceFormat ?: ""

    /** The track changed; tell subscribers what it is now. */
    fun onTrackChanged() {
        trackCount++
        detailsCount++
        val t = currentTrack()
        runCatching {
            propertyChangeSupport.firePropertyChange("Uri", null, t?.uri ?: "")
            propertyChangeSupport.firePropertyChange("Metadata", null, t?.metadata ?: "")
            propertyChangeSupport.firePropertyChange(
                "TrackCount", null, UnsignedIntegerFourBytes(trackCount.toLong()))
        }
    }

    /**
     * Unknown counts as lossless: this app decodes nothing lossily of its own
     * accord, and the honest default for a format it has not identified yet is
     * the one that does not understate the path.
     */
    private fun isLossless(format: String?): Boolean =
        format == null || format.equals("FLAC", true) || format.equals("WAV", true) ||
            format.equals("ALAC", true) || format.equals("PCM", true)
}
