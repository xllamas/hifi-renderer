package com.hifirend.upnp

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import com.hifirend.MainActivity
import com.hifirend.R

/**
 * The persistent notification that keeps the renderer alive.
 *
 * Android requires a foreground service to show one, but it is also the only
 * place a user sees the renderer while the app is closed, so it carries the
 * current track rather than a generic "service running" line.
 */
object RendererNotification {

    const val CHANNEL_ID = "hifirend_renderer"
    const val NOTIFICATION_ID = 1

    fun ensureChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Renderer",
                // Low: this is a status notification for an always-on service,
                // not something to interrupt anyone with.
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Keeps the DLNA renderer available on the network"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
        )
    }

    fun build(
        context: Context,
        rendererName: String,
        title: String?,
        subtitle: String?,
        playing: Boolean,
    ): Notification {
        val open = PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title ?: rendererName)
            .setContentText(
                subtitle ?: if (playing) "Playing" else "Ready — waiting for a controller"
            )
            .setContentIntent(open)
            .setOngoing(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
    }
}
