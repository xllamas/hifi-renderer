package com.hifirend.upnp

import android.content.Context
import android.util.Log
import com.hifirend.R
import org.jupnp.model.meta.Icon

private const val TAG = "hifirend"

/**
 * The icon a controller shows next to the renderer's name.
 *
 * UPnP puts these in the device description's iconList and then serves the
 * image data itself, so the bytes have to be loaded and handed to jUPnP rather
 * than pointed at.
 *
 * Four entries, because DLNA asks for PNG *and* JPEG at both 48x48 and
 * 120x120, and controllers differ in which they take: some pick the first
 * entry, some the largest, some only understand one of the two formats. The
 * cost of the extra three is a few kilobytes in a description that is fetched
 * once, and the failure mode of getting it wrong is a renderer that shows up
 * as a generic grey box.
 *
 * They are raw resources rather than mipmaps on purpose: a mipmap would be
 * decoded and re-encoded at whatever density the phone happens to be, whereas
 * these must be exactly the dimensions and format the description claims.
 * Depth is 24 -- the source is fully opaque, so nothing is lost flattening it,
 * and DLNA asks for 24-bit.
 */
object DeviceIcons {

    private data class Spec(
        val resId: Int,
        val mimeType: String,
        val size: Int,
        val fileName: String,
    )

    private val SPECS = listOf(
        Spec(R.raw.upnp_icon_png_48, "image/png", 48, "icon48.png"),
        Spec(R.raw.upnp_icon_png_120, "image/png", 120, "icon120.png"),
        Spec(R.raw.upnp_icon_jpg_48, "image/jpeg", 48, "icon48.jpg"),
        Spec(R.raw.upnp_icon_jpg_120, "image/jpeg", 120, "icon120.jpg"),
    )

    /**
     * Empty rather than throwing if anything cannot be read: a renderer with no
     * icon is a cosmetic problem, and failing to register the device over one
     * would take the whole thing off the network.
     */
    fun load(context: Context): Array<Icon> {
        val icons = mutableListOf<Icon>()
        for (spec in SPECS) {
            try {
                val bytes = context.resources.openRawResource(spec.resId).use { it.readBytes() }
                icons += Icon(spec.mimeType, spec.size, spec.size, 24, spec.fileName, bytes)
            } catch (e: Throwable) {
                Log.w(TAG, "device icon ${spec.fileName} unavailable: " +
                    "${e::class.java.simpleName}: ${e.message}")
            }
        }
        Log.i(TAG, "device icons: ${icons.size} of ${SPECS.size} loaded")
        return icons.toTypedArray()
    }
}
