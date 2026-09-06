package com.hifirend.upnp.openhome

import org.jupnp.binding.annotations.UpnpAction
import org.jupnp.binding.annotations.UpnpOutputArgument
import org.jupnp.binding.annotations.UpnpService
import org.jupnp.binding.annotations.UpnpServiceId
import org.jupnp.binding.annotations.UpnpServiceType
import org.jupnp.binding.annotations.UpnpStateVariable
import org.jupnp.binding.annotations.UpnpStateVariables
import org.jupnp.model.types.UnsignedIntegerFourBytes

/**
 * av.openhome.org:Time:1 — elapsed seconds and duration.
 *
 * Small, and load-bearing for the same reason GetPositionInfo is on the DLNA
 * side: a controller with no progress makes correct playback look broken. It
 * is evented on the service's tick rather than polled, which is the OpenHome
 * way round.
 */
@UpnpService(
    serviceId = UpnpServiceId(namespace = "av-openhome-org", value = "Time"),
    serviceType = UpnpServiceType(namespace = "av-openhome-org", value = "Time", version = 1),
)
@UpnpStateVariables(
    UpnpStateVariable(name = "TrackCount", datatype = "ui4", sendEvents = true),
    UpnpStateVariable(name = "Duration", datatype = "ui4", sendEvents = true),
    UpnpStateVariable(name = "Seconds", datatype = "ui4", sendEvents = true),
)
class OpenHomeTime(
    private val positionSeconds: () -> Int,
    private val durationSeconds: () -> Int,
) {

    private val propertyChangeSupport =
        org.jupnp.internal.compat.java.beans.PropertyChangeSupport(this)

    fun getPropertyChangeSupport() = propertyChangeSupport

    // Not named after the TrackCount state variable: jUPnP binds a matching
    // field in preference to the getter, and would then event a raw Int for a
    // ui4. See OpenHomeInfo for what that failure looks like from a controller.
    @Volatile private var trackChanges = 0
    @Volatile private var lastSeconds = -1

    @UpnpAction(
        name = "Time",
        out = [
            UpnpOutputArgument(name = "TrackCount", stateVariable = "TrackCount", getterName = "getTrackCount"),
            UpnpOutputArgument(name = "Duration", stateVariable = "Duration", getterName = "getDuration"),
            UpnpOutputArgument(name = "Seconds", stateVariable = "Seconds", getterName = "getSeconds"),
        ],
    )
    fun getTime() = TimeResult(
        UnsignedIntegerFourBytes(trackChanges.toLong()),
        UnsignedIntegerFourBytes(durationSeconds().coerceAtLeast(0).toLong()),
        UnsignedIntegerFourBytes(positionSeconds().coerceAtLeast(0).toLong()),
    )

    data class TimeResult(
        private val trackCount: UnsignedIntegerFourBytes,
        private val duration: UnsignedIntegerFourBytes,
        private val seconds: UnsignedIntegerFourBytes,
    ) {
        fun getTrackCount() = trackCount
        fun getDuration() = duration
        fun getSeconds() = seconds
    }

    // Accessors for the evented variables; see OpenHomeInfo for why.
    fun getTrackCount(): UnsignedIntegerFourBytes = UnsignedIntegerFourBytes(trackChanges.toLong())
    fun getDuration(): UnsignedIntegerFourBytes =
        UnsignedIntegerFourBytes(durationSeconds().coerceAtLeast(0).toLong())
    fun getSeconds(): UnsignedIntegerFourBytes =
        UnsignedIntegerFourBytes(positionSeconds().coerceAtLeast(0).toLong())

    fun onTrackChanged() {
        trackChanges++
        lastSeconds = -1
    }

    /**
     * Called from the service's existing 500 ms tick. Only events on a whole
     * second change: at twice a second an unguarded publish would double the
     * GENA traffic for a number that has not moved.
     */
    fun tick() {
        val seconds = positionSeconds().coerceAtLeast(0)
        if (seconds == lastSeconds) return
        lastSeconds = seconds
        runCatching {
            propertyChangeSupport.firePropertyChange(
                "Seconds", null, UnsignedIntegerFourBytes(seconds.toLong()))
            propertyChangeSupport.firePropertyChange(
                "Duration", null, UnsignedIntegerFourBytes(durationSeconds().coerceAtLeast(0).toLong()))
        }
    }
}
