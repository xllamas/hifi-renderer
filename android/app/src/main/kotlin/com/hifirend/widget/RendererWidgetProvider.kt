package com.hifirend.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import androidx.core.content.ContextCompat
import com.hifirend.RendererControl
import com.hifirend.RendererState
import com.hifirend.upnp.RendererUpnpService

private const val TAG = "hifirend"

/**
 * The 4x2 home-screen widget.
 *
 * Only the system's entry points live here; the drawing is [RendererWidget] and
 * the pushing is the service, because a provider is a broadcast receiver and is
 * gone again the moment each callback returns.
 *
 * The widget is also a way into the renderer, not just a view of it: on a phone
 * dedicated to this job the app may never be opened at all, so both the widget
 * being placed and its play button being pressed will start the service if it
 * is not already running. Both are user interactions with an app widget, which
 * is one of the documented exemptions from the background foreground-service
 * start restriction on Android 12+.
 */
class RendererWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        // Forced: a widget just placed, or restored after a reboot, has no idea
        // what the last drawn state was.
        RendererWidget.refresh(context, force = true)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle?,
    ) {
        RendererWidget.refresh(context, force = true)
    }

    /** First widget placed. */
    override fun onEnabled(context: Context) {
        startRenderer(context)
        RendererWidget.refresh(context, force = true)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != RendererWidget.ACTION_PLAY_PAUSE) {
            super.onReceive(context, intent)
            return
        }
        Log.i(TAG, "widget: play/pause tapped (state=${RendererState.transportState})")

        // playPause() returns false when no transport is registered, which
        // means the service is not running -- the renderer cannot play until it
        // is, so bring it up rather than silently doing nothing.
        if (!RendererControl.playPause()) {
            Log.i(TAG, "widget: play/pause with no renderer running; starting it")
            startRenderer(context)
        }
        RendererWidget.refresh(context, force = true)
    }

    private fun startRenderer(context: Context) {
        try {
            ContextCompat.startForegroundService(
                context, Intent(context, RendererUpnpService::class.java)
            )
        } catch (e: Throwable) {
            // Typically a vendor background restriction. The widget still shows
            // whatever the last known state was; it must not crash the launcher.
            Log.w(TAG, "widget: could not start renderer: ${e::class.java.simpleName}: ${e.message}")
        }
    }
}
