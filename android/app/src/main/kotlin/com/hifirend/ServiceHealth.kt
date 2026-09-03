package com.hifirend

import android.content.Context

/**
 * Tracks whether the renderer actually stays alive.
 *
 * The device matrix cannot be tested directly — every OEM kills background
 * services differently and the workarounds are undocumented — so the app has to
 * be able to notice and report its own failures rather than assume its
 * mitigations worked.
 */
class ServiceHealth(context: Context) {

    private val prefs = context.getSharedPreferences("hifirend_health", Context.MODE_PRIVATE)

    /** Service started while a previous run had not recorded a clean stop. */
    val unexpectedDeaths: Int get() = prefs.getInt(KEY_DEATHS, 0)

    val bootStarts: Int get() = prefs.getInt(KEY_BOOT_STARTS, 0)

    val lastBootBlockReason: String? get() = prefs.getString(KEY_BOOT_BLOCKED, null)

    fun recordServiceStart() {
        if (prefs.getBoolean(KEY_RUNNING, false)) {
            // Previous run never recorded a stop, so it was killed.
            prefs.edit()
                .putInt(KEY_DEATHS, unexpectedDeaths + 1)
                .putLong(KEY_LAST_DEATH, System.currentTimeMillis())
                .apply()
        }
        prefs.edit().putBoolean(KEY_RUNNING, true).apply()
    }

    fun recordServiceStop() = prefs.edit().putBoolean(KEY_RUNNING, false).apply()

    fun recordBootStart() = prefs.edit()
        .putInt(KEY_BOOT_STARTS, bootStarts + 1)
        .remove(KEY_BOOT_BLOCKED)
        .apply()

    fun recordBootBlocked(reason: String) =
        prefs.edit().putString(KEY_BOOT_BLOCKED, reason).apply()

    fun toJson(): String = """
        {"unexpectedDeaths":$unexpectedDeaths,"bootStarts":$bootStarts,
         "lastBootBlocked":${lastBootBlockReason?.let { "\"$it\"" } ?: "null"}}
    """.trimIndent().replace("\n", "").replace("  ", "")

    private companion object {
        const val KEY_RUNNING = "running"
        const val KEY_DEATHS = "unexpected_deaths"
        const val KEY_LAST_DEATH = "last_death"
        const val KEY_BOOT_STARTS = "boot_starts"
        const val KEY_BOOT_BLOCKED = "boot_blocked"
    }
}
