package com.hifirend.upnp.openhome

import android.util.Log
import org.jupnp.binding.annotations.UpnpAction
import org.jupnp.binding.annotations.UpnpInputArgument
import org.jupnp.binding.annotations.UpnpOutputArgument
import org.jupnp.binding.annotations.UpnpService
import org.jupnp.binding.annotations.UpnpServiceId
import org.jupnp.binding.annotations.UpnpServiceType
import org.jupnp.binding.annotations.UpnpStateVariable
import org.jupnp.binding.annotations.UpnpStateVariables
import org.jupnp.model.types.UnsignedIntegerFourBytes

private const val TAG = "hifirend"

/** One selectable input, in OpenHome's vocabulary. */
data class OpenHomeSource(
    val systemName: String,
    val type: String,
    val name: String,
    val visible: Boolean = true,
)

/**
 * av.openhome.org:Product:1 — identity, and which source is playing.
 *
 * OpenHome controllers find a device by this service, so without it the rest
 * is invisible however correct it is.
 *
 * It also settles a question this app had not had to answer. Two protocols now
 * want the same DAC, and `UsbPlayback` force-claims the interfaces — so
 * "who wins" needs a policy rather than a race. OpenHome already has one: a
 * device has *sources*, exactly one is active, and selecting a source stops
 * the last. So the DLNA path becomes a source alongside the playlist, and the
 * arbitration is the spec's rather than something invented here. A controller
 * of either kind can see which is live, and the screen shows one track either
 * way.
 */
@UpnpService(
    serviceId = UpnpServiceId(namespace = "av-openhome-org", value = "Product"),
    serviceType = UpnpServiceType(namespace = "av-openhome-org", value = "Product", version = 1),
)
@UpnpStateVariables(
    UpnpStateVariable(name = "ManufacturerName", datatype = "string", sendEvents = true),
    UpnpStateVariable(name = "ManufacturerInfo", datatype = "string", sendEvents = true),
    UpnpStateVariable(name = "ManufacturerUrl", datatype = "string", sendEvents = true),
    UpnpStateVariable(name = "ManufacturerImageUri", datatype = "string", sendEvents = true),
    UpnpStateVariable(name = "ModelName", datatype = "string", sendEvents = true),
    UpnpStateVariable(name = "ModelInfo", datatype = "string", sendEvents = true),
    UpnpStateVariable(name = "ModelUrl", datatype = "string", sendEvents = true),
    UpnpStateVariable(name = "ModelImageUri", datatype = "string", sendEvents = true),
    UpnpStateVariable(name = "ProductRoom", datatype = "string", sendEvents = true),
    UpnpStateVariable(name = "ProductName", datatype = "string", sendEvents = true),
    UpnpStateVariable(name = "ProductInfo", datatype = "string", sendEvents = true),
    UpnpStateVariable(name = "ProductUrl", datatype = "string", sendEvents = true),
    UpnpStateVariable(name = "ProductImageUri", datatype = "string", sendEvents = true),
    UpnpStateVariable(name = "Standby", datatype = "boolean", sendEvents = true),
    UpnpStateVariable(name = "SourceIndex", datatype = "ui4", sendEvents = true),
    UpnpStateVariable(name = "SourceCount", datatype = "ui4", sendEvents = true),
    UpnpStateVariable(name = "SourceXml", datatype = "string", sendEvents = true),
    UpnpStateVariable(name = "Attributes", datatype = "string", sendEvents = true),
    UpnpStateVariable(name = "SourceXmlChangeCount", datatype = "ui4", sendEvents = true),
    // Argument-only.
    UpnpStateVariable(name = "SourceIndexArg", datatype = "ui4", sendEvents = false),
    UpnpStateVariable(name = "SourceSystemName", datatype = "string", sendEvents = false),
    UpnpStateVariable(name = "SourceType", datatype = "string", sendEvents = false),
    UpnpStateVariable(name = "SourceName", datatype = "string", sendEvents = false),
    UpnpStateVariable(name = "SourceVisible", datatype = "boolean", sendEvents = false),
)
class OpenHomeProduct(
    private val roomName: () -> String,
    private val sources: List<OpenHomeSource>,
    /** Told the index the user picked; returns nothing, the device obeys. */
    private val onSourceSelected: (Int) -> Unit = {},
) {

    private val propertyChangeSupport =
        org.jupnp.internal.compat.java.beans.PropertyChangeSupport(this)

    fun getPropertyChangeSupport() = propertyChangeSupport

    @Volatile
    var activeIndex: Int = 0
        private set

    @Volatile
    private var standby: Boolean = false

    // ---- Identity ----------------------------------------------------------

    @UpnpAction(
        name = "Manufacturer",
        out = [
            UpnpOutputArgument(name = "Name", stateVariable = "ManufacturerName", getterName = "getName"),
            UpnpOutputArgument(name = "Info", stateVariable = "ManufacturerInfo", getterName = "getInfo"),
            UpnpOutputArgument(name = "Url", stateVariable = "ManufacturerUrl", getterName = "getUrl"),
            UpnpOutputArgument(name = "ImageUri", stateVariable = "ManufacturerImageUri", getterName = "getImageUri"),
        ],
    )
    fun getManufacturer() = Identity(MANUFACTURER, DESCRIPTION, "", "")

    @UpnpAction(
        name = "Model",
        out = [
            UpnpOutputArgument(name = "Name", stateVariable = "ModelName", getterName = "getName"),
            UpnpOutputArgument(name = "Info", stateVariable = "ModelInfo", getterName = "getInfo"),
            UpnpOutputArgument(name = "Url", stateVariable = "ModelUrl", getterName = "getUrl"),
            UpnpOutputArgument(name = "ImageUri", stateVariable = "ModelImageUri", getterName = "getImageUri"),
        ],
    )
    fun getModel() = Identity(MODEL, DESCRIPTION, "", "")

    data class Identity(
        private val name: String,
        private val info: String,
        private val url: String,
        private val imageUri: String,
    ) {
        fun getName() = name
        fun getInfo() = info
        fun getUrl() = url
        fun getImageUri() = imageUri
    }

    @UpnpAction(
        name = "Product",
        out = [
            UpnpOutputArgument(name = "Room", stateVariable = "ProductRoom", getterName = "getRoom"),
            UpnpOutputArgument(name = "Name", stateVariable = "ProductName", getterName = "getName"),
            UpnpOutputArgument(name = "Info", stateVariable = "ProductInfo", getterName = "getInfo"),
            UpnpOutputArgument(name = "Url", stateVariable = "ProductUrl", getterName = "getUrl"),
            UpnpOutputArgument(name = "ImageUri", stateVariable = "ProductImageUri", getterName = "getImageUri"),
        ],
    )
    fun getProduct() = Product(roomName(), MODEL, DESCRIPTION, "", "")

    data class Product(
        private val room: String,
        private val name: String,
        private val info: String,
        private val url: String,
        private val imageUri: String,
    ) {
        fun getRoom() = room
        fun getName() = name
        fun getInfo() = info
        fun getUrl() = url
        fun getImageUri() = imageUri
    }

    /**
     * Which optional OpenHome services this device offers. Controllers read
     * this to decide what to draw -- omit "Volume" and the volume slider
     * disappears even though the service is right there in the description.
     */
    @UpnpAction(name = "Attributes", out = [UpnpOutputArgument(name = "Value", stateVariable = "Attributes")])
    fun getAttributes(): String = "Info Time Volume"

    // ---- Standby -----------------------------------------------------------

    @UpnpAction(name = "Standby", out = [UpnpOutputArgument(name = "Value", stateVariable = "Standby")])
    fun getStandby(): Boolean = standby

    /**
     * Standby is a real command on a hi-fi, and here it means stop -- there is
     * no lower power state to enter, and pretending otherwise would leave the
     * DAC clocking a stream nobody is listening to.
     */
    @UpnpAction(name = "SetStandby")
    fun setStandby(@UpnpInputArgument(name = "Value", stateVariable = "Standby") value: Boolean?) {
        val wanted = value ?: false
        if (standby == wanted) return
        standby = wanted
        Log.i(TAG, "OH.Product.SetStandby $wanted")
        if (wanted) onStandby()
        fire("Standby", standby)
    }

    /** Set by the host so standby can stop whatever is playing. */
    @Volatile
    var onStandby: () -> Unit = {}

    // ---- Sources -----------------------------------------------------------

    @UpnpAction(name = "SourceCount", out = [UpnpOutputArgument(name = "Value", stateVariable = "SourceCount")])
    fun getSourceCount(): UnsignedIntegerFourBytes = UnsignedIntegerFourBytes(sources.size.toLong())

    // Evented state variables need an accessor jUPnP can read to build the
    // initial event a subscriber gets. These are constant for the life of the
    // device, but a controller still expects them in that first NOTIFY rather
    // than having to call the actions.
    fun getManufacturerName(): String = MANUFACTURER
    fun getManufacturerInfo(): String = DESCRIPTION
    fun getManufacturerUrl(): String = ""
    fun getManufacturerImageUri(): String = ""
    fun getModelName(): String = MODEL
    fun getModelInfo(): String = DESCRIPTION
    fun getModelUrl(): String = ""
    fun getModelImageUri(): String = ""
    fun getProductRoom(): String = roomName()
    fun getProductName(): String = MODEL
    fun getProductInfo(): String = DESCRIPTION
    fun getProductUrl(): String = ""
    fun getProductImageUri(): String = ""

    @UpnpAction(name = "SourceXml", out = [UpnpOutputArgument(name = "Value", stateVariable = "SourceXml")])
    fun getSourceXml(): String = buildString {
        append("<SourceList>")
        for (s in sources) {
            append("<Source>")
            append("<Name>").append(OpenHomeTrackList.escape(s.name)).append("</Name>")
            append("<Type>").append(OpenHomeTrackList.escape(s.type)).append("</Type>")
            append("<Visible>").append(s.visible).append("</Visible>")
            append("<SystemName>").append(OpenHomeTrackList.escape(s.systemName)).append("</SystemName>")
            append("</Source>")
        }
        append("</SourceList>")
    }

    @UpnpAction(
        name = "SourceXmlChangeCount",
        out = [UpnpOutputArgument(name = "Value", stateVariable = "SourceXmlChangeCount")],
    )
    fun getSourceXmlChangeCount(): UnsignedIntegerFourBytes = UnsignedIntegerFourBytes(0L)

    @UpnpAction(name = "SourceIndex", out = [UpnpOutputArgument(name = "Value", stateVariable = "SourceIndex")])
    fun getSourceIndex(): UnsignedIntegerFourBytes = UnsignedIntegerFourBytes(activeIndex.toLong())

    @UpnpAction(name = "SetSourceIndex")
    fun setSourceIndex(
        @UpnpInputArgument(name = "Value", stateVariable = "SourceIndexArg") value: UnsignedIntegerFourBytes?,
    ) {
        val index = value?.value?.toInt() ?: return
        selectSource(index)
    }

    @UpnpAction(name = "SetSourceIndexByName")
    fun setSourceIndexByName(
        @UpnpInputArgument(name = "Value", stateVariable = "SourceName") value: String?,
    ) {
        val index = sources.indexOfFirst { it.name.equals(value, ignoreCase = true) }
        if (index >= 0) selectSource(index)
    }

    @UpnpAction(
        name = "Source",
        out = [
            UpnpOutputArgument(name = "SystemName", stateVariable = "SourceSystemName", getterName = "getSystemName"),
            UpnpOutputArgument(name = "Type", stateVariable = "SourceType", getterName = "getType"),
            UpnpOutputArgument(name = "Name", stateVariable = "SourceName", getterName = "getName"),
            UpnpOutputArgument(name = "Visible", stateVariable = "SourceVisible", getterName = "getVisible"),
        ],
    )
    fun source(
        @UpnpInputArgument(name = "Index", stateVariable = "SourceIndexArg") index: UnsignedIntegerFourBytes?,
    ): SourceDetail {
        val s = sources.getOrNull(index?.value?.toInt() ?: 0)
            ?: return SourceDetail("", "", "", true)
        return SourceDetail(s.systemName, s.type, s.name, s.visible)
    }

    data class SourceDetail(
        private val systemName: String,
        private val type: String,
        private val name: String,
        private val visible: Boolean,
    ) {
        fun getSystemName() = systemName
        fun getType() = type
        fun getName() = name
        fun getVisible() = visible
    }

    /**
     * The single place the active source changes, whether a controller asked
     * or a protocol claimed it by starting to play.
     */
    fun selectSource(index: Int) {
        if (index !in sources.indices || index == activeIndex) return
        Log.i(TAG, "OH.Product source -> ${sources[index].name}")
        activeIndex = index
        standby = false
        onSourceSelected(index)
        fire("SourceIndex", index)
    }

    private fun fire(name: String, value: Any?) {
        runCatching { propertyChangeSupport.firePropertyChange(name, null, value) }
            .onFailure { Log.w(TAG, "OH event $name failed: ${it.message}") }
    }

    private companion object {
        const val MANUFACTURER = "HiFi Renderer"
        const val MODEL = "HiFi Renderer"
        const val DESCRIPTION = "Bit-perfect USB audio renderer"
    }
}
