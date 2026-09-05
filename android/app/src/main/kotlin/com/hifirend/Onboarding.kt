package com.hifirend

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.util.Log

private const val TAG = "hifirend"

/**
 * First-run setup: the permissions a renderer needs before it can behave like
 * an appliance.
 *
 * None of them can be taken for granted and none of them can be required. The
 * generic Android path is necessary but not sufficient — most OEMs kill
 * background services regardless — and the vendor screens that fix that are
 * undocumented Intents that can vanish between OS versions. So every step here
 * is offered, checked, and skippable, and the flow never blocks on one
 * succeeding.
 *
 * That is also why completion is recorded as "the user has been through this"
 * rather than "the permissions are granted". A device where a step is
 * impossible must still be able to leave setup, and the settings screen keeps
 * every check available afterwards.
 */
object Onboarding {

    private const val PREFS = "hifirend_onboarding"
    private const val KEY_SEEN = "seen"
    private const val KEY_ASKED_NOTIFICATIONS = "asked_notifications"

    const val NOTIFICATION_REQUEST = 4801

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun hasRun(context: Context): Boolean = prefs(context).getBoolean(KEY_SEEN, false)

    fun setHasRun(context: Context, done: Boolean) =
        prefs(context).edit().putBoolean(KEY_SEEN, done).apply()

    /**
     * Whether the foreground-service notification can actually be shown.
     *
     * Read from the notification manager rather than from the permission,
     * because a user who granted POST_NOTIFICATIONS and later switched the
     * app's notifications off in settings is in the same position as one who
     * never granted it, and the renderer's only visible sign of life is that
     * notification.
     */
    fun notificationsEnabled(context: Context): Boolean =
        context.getSystemService(NotificationManager::class.java)
            ?.areNotificationsEnabled() ?: false

    /**
     * Asks for notification permission, or sends the user somewhere they can
     * still say yes.
     *
     * Android stops showing the dialog once a permission has been refused, and
     * a button that silently does nothing is worse than no button. So a second
     * refusal falls through to the app's own notification settings, which
     * always work. Returns what it did, for the UI to describe.
     */
    fun requestNotifications(activity: Activity): String {
        if (notificationsEnabled(activity)) return "granted"

        val canAsk = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
        val askedBefore = prefs(activity).getBoolean(KEY_ASKED_NOTIFICATIONS, false)
        val wouldShowDialog = canAsk &&
            (!askedBefore ||
                activity.shouldShowRequestPermissionRationale(
                    Manifest.permission.POST_NOTIFICATIONS))

        if (wouldShowDialog) {
            prefs(activity).edit().putBoolean(KEY_ASKED_NOTIFICATIONS, true).apply()
            activity.requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST)
            return "requested"
        }
        return if (openNotificationSettings(activity)) "settings" else "unavailable"
    }

    /**
     * The app's own notification settings. Falls back to the app detail page,
     * and then gives up rather than crashing: this is an Intent that a vendor
     * ROM is entirely capable of not having.
     */
    fun openNotificationSettings(context: Context): Boolean {
        val candidates = listOf(
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName),
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(android.net.Uri.parse("package:${context.packageName}")),
        )
        for (intent in candidates) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (intent.resolveActivity(context.packageManager) == null) continue
            return runCatching { context.startActivity(intent); true }
                .onFailure { Log.w(TAG, "notification settings refused: ${it.message}") }
                .getOrDefault(false)
        }
        Log.w(TAG, "no notification settings screen on this device")
        return false
    }
}
