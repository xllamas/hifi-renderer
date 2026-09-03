package com.hifirend

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat
import com.hifirend.upnp.RendererUpnpService

private const val TAG = "hifirend"

/**
 * Brings the renderer up after a reboot, so a dedicated phone needs no
 * interaction to become available again.
 *
 * Starting a foreground service from a receiver is normally forbidden on
 * Android 12+, but BOOT_COMPLETED is one of the documented exemptions. It is
 * still wrapped: vendors restrict this differently, and failing to start must
 * never crash at boot.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.i(TAG, "boot: received ${intent.action}")
        try {
            ContextCompat.startForegroundService(
                context, Intent(context, RendererUpnpService::class.java)
            )
            ServiceHealth(context).recordBootStart()
        } catch (e: Throwable) {
            // Typically a vendor autostart restriction. Recorded so the app can
            // tell the user its boot-start is being blocked rather than
            // silently never appearing on the network.
            Log.e(TAG, "boot: could not start renderer: ${e::class.java.simpleName}: ${e.message}")
            ServiceHealth(context).recordBootBlocked(e.javaClass.simpleName)
        }
    }
}
