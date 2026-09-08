package com.hifirend

import android.content.Context

/**
 * Which language the interface is in, when the user has chosen one.
 *
 * Empty means follow the phone, and that is the default for a reason rather
 * than by omission: this renderer is a box on a shelf, and the phone reading
 * it is often not the phone that set it up. A guest who picks it up should
 * find their own language with nobody having configured anything.
 *
 * The override exists for the opposite case, which is just as real. A renderer
 * set up on a spare phone inherits whatever language that phone happens to be
 * in -- frequently not the owner's -- and changing the whole phone to fix one
 * app is a poor trade.
 *
 * Kept here rather than in Dart because the widget and the notification are
 * drawn by the service with no Flutter engine running, so they cannot ask the
 * UI what language it settled on. Whatever reads this must be prepared for
 * empty, which is the normal state.
 */
object InterfaceLanguage {

    private const val PREFS = "hifirend_upnp"
    private const val KEY = "interface_language"

    /** A BCP-47-ish tag such as `es` or `pt_BR`, or empty for "follow the phone". */
    fun tag(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY, "") ?: ""

    fun setTag(context: Context, tag: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY, tag.trim())
            .apply()
    }
}
