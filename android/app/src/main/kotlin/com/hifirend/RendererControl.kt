package com.hifirend

/**
 * Lets the UI drive the renderer.
 *
 * Commands go through the same AVTransport the network controllers use, so
 * pressing play on the phone and pressing play in BubbleUPnP take one code
 * path and produce one state — including the LastChange events that tell every
 * subscribed controller what happened.
 *
 * The service registers itself here on creation; the field is null whenever the
 * renderer is not running, and every call tolerates that.
 */
object RendererControl {

    @Volatile
    var transport: TransportCommands? = null

    /**
     * Set by the service. The renderer advertises what the *attached DAC* can
     * accept, so changing the output device changes the renderer's advertised
     * capabilities and controllers have to be told.
     */
    @Volatile
    var onOutputDeviceChanged: ((Boolean) -> Unit)? = null

    /**
     * [force] for a deliberate change by the user -- picking a device, or
     * changing the conversion policy. Those alter what is advertised even when
     * the device itself is the same, so they must not be skipped.
     */
    fun outputDeviceChanged(force: Boolean = true) {
        runCatching { onOutputDeviceChanged?.invoke(force) }
    }

    interface TransportCommands {
        fun play()
        fun pause()
        fun stop()
        /** Percent, or null when the DAC has no host-controllable volume. */
        fun dacVolume(): Int?
        fun setDacVolume(percent: Int): Boolean
    }

    fun playPause(): Boolean {
        val t = transport ?: return false
        if (RendererState.isPlaying) t.pause() else t.play()
        return true
    }

    fun stop(): Boolean {
        transport?.stop() ?: return false
        return true
    }
}
