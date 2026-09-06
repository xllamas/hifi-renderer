package com.hifirend.power

/**
 * Carries the screen decision from the service, which owns playback, to the
 * activity, which owns the window.
 *
 * They are in the same process but neither reliably outlives the other: the
 * service runs with no UI at all, and the activity is created and destroyed
 * around it. A plain listener would therefore depend on which started first,
 * and getting that order wrong is exactly how the previous attempt at this
 * ended up with a flag nobody ever cleared.
 *
 * So the state lives here instead, and either side may arrive first. Setting
 * [apply] immediately hands it the current value, so an activity created long
 * after the policy decided still gets the right window flag.
 */
object ScreenState {

    @Volatile
    private var keepOn: Boolean = true

    @Volatile
    private var applier: ((Boolean) -> Unit)? = null

    var keepScreenOn: Boolean
        get() = keepOn
        set(value) {
            keepOn = value
            applier?.invoke(value)
        }

    /** The activity's window setter, or null when there is no UI. */
    var apply: ((Boolean) -> Unit)?
        get() = applier
        set(value) {
            applier = value
            value?.invoke(keepOn)
        }
}
