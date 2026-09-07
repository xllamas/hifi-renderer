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
     * Set by the service so a settings change reaches the running policy.
     * Without it the new timeout would only take effect at the next restart.
     */
    @Volatile
    var onScreenTimeoutChanged: ((Int) -> Unit)? = null

    /**
     * Set by the service. Called when USB permission arrives, which on this
     * hardware is several seconds *after* the attach broadcast.
     *
     * Measured on the test phone: attach at 12:27:20, permission with the
     * activity launch at 12:27:27. Anything that needs an openable device
     * therefore cannot do its work in the attach handler alone -- it looks,
     * finds no permission, and gives up seven seconds before the answer
     * arrives. This is the second chance.
     */
    @Volatile
    var onUsbPermissionGranted: (() -> Unit)? = null

    fun usbPermissionGranted() {
        runCatching { onUsbPermissionGranted?.invoke() }
    }

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
        /** Only meaningful for a source that holds a playlist; false if it cannot. */
        fun next(): Boolean
        fun previous(): Boolean
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

    fun next(): Boolean = transport?.next() ?: false

    fun previous(): Boolean = transport?.previous() ?: false
}
