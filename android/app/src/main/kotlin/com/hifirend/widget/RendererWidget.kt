package com.hifirend.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import com.hifirend.MainActivity
import com.hifirend.R
import com.hifirend.RendererState

private const val TAG = "hifirend"

/**
 * Draws the home-screen widget from [RendererState].
 *
 * Kept out of the provider because the provider is only a broadcast receiver:
 * the system instantiates it, calls one method and throws it away, so it is the
 * wrong place for anything that has to remember something between updates. This
 * object is the one the service calls.
 *
 * Deliberately Flutter-free. On a dedicated renderer the UI process spends most
 * of its life destroyed, and a widget that went stale whenever the app closed
 * would be showing the wrong track exactly when it is the only thing on screen.
 */
object RendererWidget {

    const val ACTION_PLAY_PAUSE = "com.hifirend.widget.PLAY_PAUSE"

    /**
     * Progress is quantised to this before it counts as a change. The service
     * calls [refresh] twice a second; redrawing that often would put a binder
     * transaction carrying a bitmap on the home screen every 500 ms for a bar
     * that moved less than a pixel. Five seconds is roughly one pixel of a
     * four-minute track on a 250dp widget.
     */
    private const val PROGRESS_STEP_SECONDS = 5

    @Volatile private var lastSignature: String? = null

    /**
     * Redraws the widget if anything it shows has changed.
     *
     * Cheap enough to call on a timer: an unchanged state costs one string
     * build and no binder traffic at all. [force] covers the cases the
     * signature cannot see -- a widget just added, or art that finished
     * downloading after the update that wanted it.
     */
    fun refresh(anyContext: Context, force: Boolean = false) {
        // The art fetch outlives the caller and holds this in a callback, and
        // callers here are receivers and services with short lives of their own.
        val context = anyContext.applicationContext
        val signature = signature()
        if (!force && signature == lastSignature) return

        val manager = try {
            AppWidgetManager.getInstance(context)
        } catch (e: Throwable) {
            Log.w(TAG, "widget manager unavailable: ${e.message}")
            null
        } ?: return

        val ids = runCatching {
            manager.getAppWidgetIds(ComponentName(context, RendererWidgetProvider::class.java))
        }.getOrNull() ?: return

        // Nothing on any home screen: record the signature anyway so this stays
        // a no-op until the state actually moves again.
        if (ids.isEmpty()) {
            lastSignature = signature
            return
        }

        runCatching { manager.updateAppWidget(ids, build(context)) }
            .onFailure {
                // A TransactionTooLargeException here would mean the size guard
                // in AlbumArt had been defeated. Either way the renderer carries
                // on; a stale widget is not worth a crash.
                Log.w(TAG, "widget update failed: ${it::class.java.simpleName}: ${it.message}")
            }
        lastSignature = signature
    }

    /** Everything the widget draws, in one comparable string. */
    private fun signature(): String = RendererState.let { st ->
        listOf(
            st.rendererName,
            st.transportState,
            st.title, st.artist, st.album, st.albumArtUri,
            st.formatBadge(), st.bitPerfect,
            st.durationSeconds,
            st.positionSeconds / PROGRESS_STEP_SECONDS,
            st.dacConnected,
        ).joinToString("|")
    }

    fun build(context: Context): RemoteViews {
        val st = RendererState
        val views = RemoteViews(context.packageName, R.layout.renderer_widget)
        // Read once: these are volatile fields written by the decoder, USB and
        // jUPnP threads, and a widget built from a half-changed track would
        // pair one song's title with another's artist.
        val title = st.title

        views.setOnClickPendingIntent(R.id.widget_root, openApp(context))

        if (title == null) {
            views.setTextViewText(R.id.widget_title, st.rendererName)
            views.setTextViewText(
                R.id.widget_subtitle,
                if (st.dacConnected) "Ready — waiting for a controller" else "No DAC connected",
            )
            placeholderArt(context, views)
            views.setViewVisibility(R.id.widget_progress, View.GONE)
            views.setViewVisibility(R.id.widget_footer, View.GONE)
            // A transport button with no track to act on is worse than none.
            views.setViewVisibility(R.id.widget_play_pause, View.GONE)
            return views
        }

        views.setTextViewText(R.id.widget_title, title)
        views.setTextViewText(
            R.id.widget_subtitle,
            listOfNotNull(st.artist, st.album).joinToString(" — "),
        )

        val art = AlbumArt.forUri(st.albumArtUri) { refresh(context, force = true) }
        if (art != null) {
            views.setImageViewBitmap(R.id.widget_art, art)
            views.setViewPadding(R.id.widget_art, 0, 0, 0, 0)
        } else {
            placeholderArt(context, views)
        }

        views.setViewVisibility(R.id.widget_progress, View.VISIBLE)
        val progress = if (st.durationSeconds > 0)
            (1000L * st.positionSeconds / st.durationSeconds).toInt().coerceIn(0, 1000) else 0
        // Never indeterminate: an animation running forever on the home screen
        // is not what a renderer that may sit idle for days should be doing.
        views.setProgressBar(R.id.widget_progress, 1000, progress, false)

        views.setViewVisibility(R.id.widget_footer, View.VISIBLE)
        views.setTextViewText(R.id.widget_position, formatTime(st.positionSeconds))
        views.setTextViewText(
            R.id.widget_duration,
            if (st.durationSeconds > 0) formatTime(st.durationSeconds) else "",
        )

        val badge = st.formatBadge()
        views.setTextViewText(R.id.widget_format, badge ?: "")
        views.setViewVisibility(
            R.id.widget_verified,
            if (badge != null && st.bitPerfect) View.VISIBLE else View.GONE,
        )

        views.setViewVisibility(R.id.widget_play_pause, View.VISIBLE)
        views.setImageViewResource(
            R.id.widget_play_pause,
            if (st.isPlaying) R.drawable.ic_widget_pause else R.drawable.ic_widget_play,
        )
        views.setOnClickPendingIntent(R.id.widget_play_pause, playPause(context))
        return views
    }

    /**
     * The album glyph, inset so it reads as an icon in the art slot rather than
     * as a stretched image. The inset is applied here rather than left to the
     * layout because real art has to fill the slot edge to edge, and
     * setViewPadding takes pixels -- RemoteViews resolves no dimen resources.
     */
    private fun placeholderArt(context: Context, views: RemoteViews) {
        views.setImageViewResource(R.id.widget_art, R.drawable.ic_widget_album)
        val inset = (30 * context.resources.displayMetrics.density).toInt()
        views.setViewPadding(R.id.widget_art, inset, inset, inset, inset)
    }

    private fun openApp(context: Context): PendingIntent = PendingIntent.getActivity(
        context, 0,
        Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun playPause(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context, 1,
        Intent(context, RendererWidgetProvider::class.java).setAction(ACTION_PLAY_PAUSE),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    /** h:mm:ss only once there are hours; most tracks are m:ss. */
    private fun formatTime(seconds: Int): String {
        val s = seconds.coerceAtLeast(0)
        return if (s >= 3600) "%d:%02d:%02d".format(s / 3600, (s % 3600) / 60, s % 60)
        else "%d:%02d".format(s / 60, s % 60)
    }
}
