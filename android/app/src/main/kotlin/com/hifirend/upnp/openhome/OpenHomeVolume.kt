package com.hifirend.upnp.openhome

import android.util.Log
import com.hifirend.RendererState
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
 * av.openhome.org:Volume:1 — the DAC's volume, not a software fader.
 *
 * The same rule as RenderingControl, for the same reason: when the attached
 * DAC exposes no host-controllable volume the value is tracked and reported
 * honestly but nothing is attenuated, because scaling samples in software
 * would quietly end the bit-perfect claim this app exists to make.
 *
 * Balance and Fade are reported as unsupported (max 0) rather than accepted
 * and ignored -- both would mean touching samples, and a controller that is
 * told the maximum is zero hides the control instead of offering one that
 * does nothing.
 */
@UpnpService(
    serviceId = UpnpServiceId(namespace = "av-openhome-org", value = "Volume"),
    serviceType = UpnpServiceType(namespace = "av-openhome-org", value = "Volume", version = 1),
)
@UpnpStateVariables(
    UpnpStateVariable(name = "Volume", datatype = "ui4", sendEvents = true),
    UpnpStateVariable(name = "Mute", datatype = "boolean", sendEvents = true),
    UpnpStateVariable(name = "Balance", datatype = "i4", sendEvents = true),
    UpnpStateVariable(name = "Fade", datatype = "i4", sendEvents = true),
    UpnpStateVariable(name = "VolumeLimit", datatype = "ui4", sendEvents = true),
    UpnpStateVariable(name = "VolumeMax", datatype = "ui4", sendEvents = true),
    UpnpStateVariable(name = "VolumeUnity", datatype = "ui4", sendEvents = true),
    UpnpStateVariable(name = "VolumeSteps", datatype = "ui4", sendEvents = true),
    UpnpStateVariable(name = "VolumeMilliDbPerStep", datatype = "ui4", sendEvents = true),
    UpnpStateVariable(name = "BalanceMax", datatype = "ui4", sendEvents = true),
    UpnpStateVariable(name = "FadeMax", datatype = "ui4", sendEvents = true),
)
class OpenHomeVolume(
    /** Returns false when the DAC would not take the value. */
    private val volumeSink: (Int) -> Boolean,
) {

    private val propertyChangeSupport =
        org.jupnp.internal.compat.java.beans.PropertyChangeSupport(this)

    fun getPropertyChangeSupport() = propertyChangeSupport

    @Volatile private var muted = false
    @Volatile private var volumeBeforeMute = 0

    /** Percent, matching the DAC's own scale so nothing has to be re-mapped. */
    private fun currentVolume(): Int = RendererState.dacVolume.coerceAtLeast(0)

    @UpnpAction(
        name = "Characteristics",
        out = [
            UpnpOutputArgument(name = "VolumeMax", stateVariable = "VolumeMax", getterName = "getVolumeMax"),
            UpnpOutputArgument(name = "VolumeUnity", stateVariable = "VolumeUnity", getterName = "getVolumeUnity"),
            UpnpOutputArgument(name = "VolumeSteps", stateVariable = "VolumeSteps", getterName = "getVolumeSteps"),
            UpnpOutputArgument(
                name = "VolumeMilliDbPerStep",
                stateVariable = "VolumeMilliDbPerStep",
                getterName = "getVolumeMilliDbPerStep",
            ),
            UpnpOutputArgument(name = "BalanceMax", stateVariable = "BalanceMax", getterName = "getBalanceMax"),
            UpnpOutputArgument(name = "FadeMax", stateVariable = "FadeMax", getterName = "getFadeMax"),
        ],
    )
    fun getCharacteristics() = Characteristics(
        UnsignedIntegerFourBytes(100L),
        UnsignedIntegerFourBytes(100L),
        UnsignedIntegerFourBytes(100L),
        // The DAC's own steps are its business and are not uniformly dB, so
        // claiming a figure here would be inventing one.
        UnsignedIntegerFourBytes(0L),
        UnsignedIntegerFourBytes(0L),
        UnsignedIntegerFourBytes(0L),
    )

    data class Characteristics(
        private val volumeMax: UnsignedIntegerFourBytes,
        private val volumeUnity: UnsignedIntegerFourBytes,
        private val volumeSteps: UnsignedIntegerFourBytes,
        private val volumeMilliDbPerStep: UnsignedIntegerFourBytes,
        private val balanceMax: UnsignedIntegerFourBytes,
        private val fadeMax: UnsignedIntegerFourBytes,
    ) {
        fun getVolumeMax() = volumeMax
        fun getVolumeUnity() = volumeUnity
        fun getVolumeSteps() = volumeSteps
        fun getVolumeMilliDbPerStep() = volumeMilliDbPerStep
        fun getBalanceMax() = balanceMax
        fun getFadeMax() = fadeMax
    }

    @UpnpAction(name = "Volume", out = [UpnpOutputArgument(name = "Value", stateVariable = "Volume")])
    fun getVolume(): UnsignedIntegerFourBytes = UnsignedIntegerFourBytes(currentVolume().toLong())

    @UpnpAction(name = "SetVolume")
    fun setVolume(@UpnpInputArgument(name = "Value", stateVariable = "Volume") value: UnsignedIntegerFourBytes?) {
        val percent = (value?.value?.toInt() ?: return).coerceIn(0, 100)
        Log.i(TAG, "OH.Volume.SetVolume $percent")
        if (volumeSink(percent)) publishVolume(percent)
    }

    @UpnpAction(name = "VolumeInc")
    fun volumeInc() = setVolume(UnsignedIntegerFourBytes((currentVolume() + 1).coerceAtMost(100).toLong()))

    @UpnpAction(name = "VolumeDec")
    fun volumeDec() = setVolume(UnsignedIntegerFourBytes((currentVolume() - 1).coerceAtLeast(0).toLong()))

    @UpnpAction(name = "VolumeLimit", out = [UpnpOutputArgument(name = "Value", stateVariable = "VolumeLimit")])
    fun getVolumeLimit(): UnsignedIntegerFourBytes = UnsignedIntegerFourBytes(100L)

    // Accessors for the evented variables; see OpenHomeInfo for why. The scale
    // is the DAC's own percent, so nothing here needs re-mapping.
    fun getVolumeMax(): UnsignedIntegerFourBytes = UnsignedIntegerFourBytes(100L)
    fun getVolumeUnity(): UnsignedIntegerFourBytes = UnsignedIntegerFourBytes(100L)
    fun getVolumeSteps(): UnsignedIntegerFourBytes = UnsignedIntegerFourBytes(100L)
    fun getVolumeMilliDbPerStep(): UnsignedIntegerFourBytes = UnsignedIntegerFourBytes(0L)
    fun getBalanceMax(): UnsignedIntegerFourBytes = UnsignedIntegerFourBytes(0L)
    fun getFadeMax(): UnsignedIntegerFourBytes = UnsignedIntegerFourBytes(0L)

    @UpnpAction(name = "Mute", out = [UpnpOutputArgument(name = "Value", stateVariable = "Mute")])
    fun getMute(): Boolean = muted

    @UpnpAction(name = "SetMute")
    fun setMute(@UpnpInputArgument(name = "Value", stateVariable = "Mute") value: Boolean?) {
        val wanted = value ?: return
        if (wanted == muted) return
        muted = wanted
        // Unmuting has to go back where the user was, which means remembering
        // it -- the DAC only knows the level it is on now.
        if (wanted) {
            volumeBeforeMute = currentVolume()
            volumeSink(0)
        } else {
            volumeSink(volumeBeforeMute)
        }
        runCatching { propertyChangeSupport.firePropertyChange("Mute", null, muted) }
    }

    // Balance and fade would both mean altering samples. Reported, refused.
    @UpnpAction(name = "Balance", out = [UpnpOutputArgument(name = "Value", stateVariable = "Balance")])
    fun getBalance(): Int = 0

    @UpnpAction(name = "SetBalance")
    fun setBalance(@UpnpInputArgument(name = "Value", stateVariable = "Balance") value: Int?) = Unit

    @UpnpAction(name = "BalanceInc")
    fun balanceInc() = Unit

    @UpnpAction(name = "BalanceDec")
    fun balanceDec() = Unit

    @UpnpAction(name = "Fade", out = [UpnpOutputArgument(name = "Value", stateVariable = "Fade")])
    fun getFade(): Int = 0

    @UpnpAction(name = "SetFade")
    fun setFade(@UpnpInputArgument(name = "Value", stateVariable = "Fade") value: Int?) = Unit

    @UpnpAction(name = "FadeInc")
    fun fadeInc() = Unit

    @UpnpAction(name = "FadeDec")
    fun fadeDec() = Unit

    /**
     * Volume is shared -- the DAC's own knob, the app's screen and either
     * protocol can all move it -- so subscribers are told about changes they
     * did not make. Called from the service tick that already watches for this.
     */
    fun publishVolume(percent: Int) {
        runCatching {
            propertyChangeSupport.firePropertyChange(
                "Volume", null, UnsignedIntegerFourBytes(percent.coerceIn(0, 100).toLong()))
        }
    }
}
