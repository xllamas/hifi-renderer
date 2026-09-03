package com.hifirend.power

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log

private const val TAG = "hifirend"

/**
 * Deep links into the vendor screen that controls whether an app may run in the
 * background and start at boot.
 *
 * Standard Android permissions are necessary but not sufficient: most OEMs add
 * their own killer, and an app that has done everything correctly still fails
 * to survive a reboot without a setting only the user can reach.
 *
 * Every entry here is an undocumented internal Intent that can vanish between
 * OS versions, so each is resolve-checked and falls back to the generic
 * battery-optimisation dialog. This is deliberately a data table rather than
 * branching logic: adding a vendor is one line, and the untestable surface
 * stays small. Only Xiaomi/MIUI can be verified directly here.
 */
object VendorAutostart {

    data class Target(val label: String, val component: ComponentName)

    private val targets: Map<String, List<Target>> = mapOf(
        "xiaomi" to listOf(
            Target("MIUI autostart", ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity")),
        ),
        "samsung" to listOf(
            Target("Device Care battery", ComponentName(
                "com.samsung.android.lool",
                "com.samsung.android.sm.ui.battery.BatteryActivity")),
        ),
        "huawei" to listOf(
            Target("Startup manager", ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity")),
        ),
        "honor" to listOf(
            Target("Startup manager", ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity")),
        ),
        "oppo" to listOf(
            Target("Startup manager", ComponentName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.startupapp.StartupAppListActivity")),
        ),
        "realme" to listOf(
            Target("Startup manager", ComponentName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.startupapp.StartupAppListActivity")),
        ),
        "vivo" to listOf(
            Target("Background app manager", ComponentName(
                "com.vivo.permissionmanager",
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity")),
        ),
        "oneplus" to listOf(
            Target("Battery optimisation", ComponentName(
                "com.oneplus.security",
                "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity")),
        ),
    )

    fun manufacturer(): String = Build.MANUFACTURER.lowercase()

    /** True when this device is one of the OEMs known to need extra permission. */
    fun hasVendorSettings(context: Context): Boolean = resolveTarget(context) != null

    private fun resolveTarget(context: Context): Target? {
        val list = targets[manufacturer()] ?: return null
        return list.firstOrNull { t ->
            Intent().setComponent(t.component)
                .resolveActivity(context.packageManager) != null
        }
    }

    /**
     * Opens the vendor screen, or the generic battery settings if there is
     * none. Returns the label shown, or null if nothing could be opened.
     */
    fun open(context: Context): String? {
        resolveTarget(context)?.let { t ->
            return try {
                context.startActivity(
                    Intent().setComponent(t.component)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                Log.i(TAG, "autostart: opened ${t.label}")
                t.label
            } catch (e: Throwable) {
                Log.w(TAG, "autostart: ${t.label} refused: ${e.message}")
                openBatterySettings(context)
            }
        }
        return openBatterySettings(context)
    }

    private fun openBatterySettings(context: Context): String? = try {
        context.startActivity(
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        "Battery optimisation settings"
    } catch (e: Throwable) {
        Log.w(TAG, "autostart: no settings screen available: ${e.message}")
        null
    }

    fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    /** The system dialog; only shows once per app unless the user clears data. */
    @Suppress("BatteryLife")
    fun requestIgnoreBatteryOptimizations(context: Context): Boolean = try {
        context.startActivity(
            Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:${context.packageName}"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        true
    } catch (e: Throwable) {
        Log.w(TAG, "autostart: battery exemption request failed: ${e.message}")
        false
    }
}
