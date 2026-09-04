package com.hifirend.upnp

import android.util.Log
import org.jupnp.model.types.UnsignedIntegerFourBytes
import org.jupnp.model.types.UnsignedIntegerTwoBytes
import org.jupnp.support.model.Channel
import org.jupnp.support.renderingcontrol.AbstractAudioRenderingControl
import org.jupnp.support.renderingcontrol.lastchange.ChannelMute
import org.jupnp.support.renderingcontrol.lastchange.ChannelVolume
import org.jupnp.support.renderingcontrol.lastchange.RenderingControlVariable

private const val TAG = "hifirend"

/**
 * RenderingControl:1 — volume and mute.
 *
 * Controllers call GetVolume/SetVolume unconditionally, so this must always
 * answer sensibly even when the attached DAC has no host-controllable volume at
 * all (the reference AL400 has none: no Feature Unit, and its HID interface is
 * input-only). In that case the value is tracked and reported honestly, but
 * nothing is sent to the hardware — attenuating in software would silently stop
 * playback being bit-perfect, which is the entire point of the app.
 *
 * Volume is a *shared* quantity, and that shapes this class. It can be changed
 * from a DLNA controller, from the app's own screen, or from the DAC's own knob
 * or remote, and every one of those has to end up visible in the other two.
 * So the value reported here is whatever was last observed from any source, and
 * [publish] fires the LastChange event that tells subscribed controllers about
 * changes they did not make themselves.
 */
class RendererRenderingControl(
    private val volumeSink: ((Int) -> Boolean)? = null,
) : AbstractAudioRenderingControl() {

    @Volatile
    private var volume = 100

    @Volatile
    private var muted = false

    /** False when the DAC could not accept the value, so the UI can say so. */
    @Volatile
    var lastSetReachedHardware = false
        private set

    override fun getCurrentChannels(): Array<Channel> = arrayOf(Channel.Master)

    override fun getMute(instanceId: UnsignedIntegerFourBytes?, channelName: String?): Boolean = muted

    override fun setMute(instanceId: UnsignedIntegerFourBytes?, channelName: String?, desiredMute: Boolean) {
        Log.i(TAG, "RenderingControl.SetMute $desiredMute")
        muted = desiredMute
        lastSetReachedHardware = volumeSink?.invoke(if (desiredMute) 0 else volume) ?: false
        publish()
    }

    override fun getVolume(instanceId: UnsignedIntegerFourBytes?, channelName: String?): UnsignedIntegerTwoBytes =
        UnsignedIntegerTwoBytes(volume.toLong())

    override fun setVolume(
        instanceId: UnsignedIntegerFourBytes?,
        channelName: String?,
        desiredVolume: UnsignedIntegerTwoBytes?,
    ) {
        val v = (desiredVolume?.value ?: 100L).toInt().coerceIn(0, 100)
        volume = v
        lastSetReachedHardware = volumeSink?.invoke(v) ?: false
        if (lastSetReachedHardware) com.hifirend.RendererState.dacVolume = v
        Log.i(TAG, "RenderingControl.SetVolume $v reachedHardware=$lastSetReachedHardware")
        publish()
    }

    /**
     * The volume changed somewhere other than here — the app's own screen, or
     * the DAC's physical knob.
     *
     * Without this a controller's slider silently disagrees with the hardware
     * for as long as it stays connected, because a controller only learns about
     * volume from its own SetVolume calls and from LastChange.
     */
    fun onVolumeObserved(percent: Int) {
        val v = percent.coerceIn(0, 100)
        if (v == volume) return
        volume = v
        publish()
    }

    /**
     * jUPnP only accumulates evented values; the service's flusher turns them
     * into the NOTIFY that actually reaches subscribers.
     */
    private fun publish() {
        try {
            lastChange.setEventedValue(
                getDefaultInstanceID(),
                RenderingControlVariable.Volume(ChannelVolume(Channel.Master, volume)),
                RenderingControlVariable.Mute(ChannelMute(Channel.Master, muted)),
            )
        } catch (e: Throwable) {
            // Eventing must never break playback or a SOAP response.
            Log.w(TAG, "RenderingControl LastChange failed: ${e::class.java.simpleName}: ${e.message}")
        }
    }

    override fun getCurrentInstanceIds(): Array<UnsignedIntegerFourBytes> =
        arrayOf(UnsignedIntegerFourBytes(0))
}
