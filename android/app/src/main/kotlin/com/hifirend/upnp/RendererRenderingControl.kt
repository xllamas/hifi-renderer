package com.hifirend.upnp

import android.util.Log
import org.jupnp.model.types.UnsignedIntegerFourBytes
import org.jupnp.model.types.UnsignedIntegerTwoBytes
import org.jupnp.support.model.Channel
import org.jupnp.support.renderingcontrol.AbstractAudioRenderingControl

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
 * [volumeSink] is supplied by the audio engine in M4. While it is null, or
 * while the DAC exposes no volume control, this is bookkeeping only.
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
        Log.i(TAG, "RenderingControl.SetVolume $v reachedHardware=$lastSetReachedHardware")
    }

    override fun getCurrentInstanceIds(): Array<UnsignedIntegerFourBytes> =
        arrayOf(UnsignedIntegerFourBytes(0))
}
