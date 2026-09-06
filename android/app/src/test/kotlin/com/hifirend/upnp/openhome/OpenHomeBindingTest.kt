package com.hifirend.upnp.openhome

import com.hifirend.RendererState
import org.jupnp.binding.annotations.AnnotationLocalServiceBinder
import org.jupnp.model.meta.LocalService
import org.jupnp.model.state.StateVariableValue
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That jUPnP can actually bind these services.
 *
 * This is the failure worth catching early, because of how it presents: a bad
 * annotation throws inside `binder.read()` during device registration, which
 * `RendererUpnpService` deliberately catches so a broken renderer cannot take
 * the app down. The symptom is therefore not a crash but a device that never
 * appears on the network -- indistinguishable, from the far end, from a Wi-Fi
 * problem. jUPnP is an ordinary JVM library, so the binding can be proved here
 * in milliseconds instead of on a phone.
 *
 * It also pins the wire contract. Controllers match action and argument names
 * exactly; a rename that still compiles is a rename that silently stops
 * working against Kazoo.
 */
class OpenHomeBindingTest {

    private fun bind(type: Class<*>): LocalService<*> =
        AnnotationLocalServiceBinder().read(type)

    private fun actionNames(service: LocalService<*>): Set<String> =
        service.actions.map { it.name }.toSet()

    @Test
    fun `every OpenHome service binds`() {
        for (type in listOf(
            OpenHomeProduct::class.java,
            OpenHomePlaylist::class.java,
            OpenHomeInfo::class.java,
            OpenHomeTime::class.java,
            OpenHomeVolume::class.java,
        )) {
            assertNotNull("$type failed to bind", bind(type))
        }
    }

    @Test
    fun `services are published in the av-openhome-org namespace`() {
        val service = bind(OpenHomePlaylist::class.java)
        // urn:av-openhome-org:service:Playlist:1 -- a controller looking for
        // an OpenHome device matches on exactly this.
        assertEquals("av-openhome-org", service.serviceType.namespace)
        assertEquals("Playlist", service.serviceType.type)
        assertEquals(1, service.serviceType.version)
        assertEquals("av-openhome-org", service.serviceId.namespace)
        assertEquals("Playlist", service.serviceId.id)
    }

    @Test
    fun `Playlist exposes the actions a controller drives`() {
        val names = actionNames(bind(OpenHomePlaylist::class.java))
        for (required in listOf(
            "Play", "Pause", "Stop", "Next", "Previous",
            "SeekId", "SeekIndex", "SeekSecondAbsolute", "SeekSecondRelative",
            "TransportState", "Id", "Read", "ReadList", "Insert",
            "DeleteId", "DeleteAll", "TracksMax", "IdArray", "IdArrayChanged",
            "Repeat", "SetRepeat", "Shuffle", "SetShuffle", "ProtocolInfo",
        )) {
            assertTrue("Playlist is missing $required", names.contains(required))
        }
    }

    @Test
    fun `IdArray is carried as bin base64, which is how controllers decode it`() {
        val service = bind(OpenHomePlaylist::class.java)
        val idArray = service.getStateVariable("IdArray")
        assertNotNull(idArray)
        assertEquals("bin.base64", idArray.typeDetails.datatype.builtin.descriptorName)
        // And it must event, or a controller never learns the playlist changed
        // without polling for it.
        assertTrue(idArray.eventDetails.isSendEvents)
    }

    @Test
    fun `IdArray action returns both the token and the array`() {
        val action = bind(OpenHomePlaylist::class.java).getAction("IdArray")
        assertNotNull(action)
        val outputs = action.outputArguments.map { it.name }
        assertEquals(listOf("Token", "Array"), outputs)
    }

    @Test
    fun `Read returns a uri and its metadata, in that order`() {
        val action = bind(OpenHomePlaylist::class.java).getAction("Read")
        assertEquals(listOf("Id"), action.inputArguments.map { it.name })
        assertEquals(listOf("Uri", "Metadata"), action.outputArguments.map { it.name })
    }

    @Test
    fun `Insert takes the spec's three arguments and answers with the new id`() {
        val action = bind(OpenHomePlaylist::class.java).getAction("Insert")
        assertEquals(listOf("AfterId", "Uri", "Metadata"), action.inputArguments.map { it.name })
        assertEquals(listOf("NewId"), action.outputArguments.map { it.name })
    }

    @Test
    fun `Product exposes the source actions the arbitration depends on`() {
        val names = actionNames(bind(OpenHomeProduct::class.java))
        for (required in listOf(
            "Manufacturer", "Model", "Product", "Attributes",
            "SourceCount", "SourceXml", "SourceIndex", "SetSourceIndex",
            "SetSourceIndexByName", "Source", "Standby", "SetStandby",
        )) {
            assertTrue("Product is missing $required", names.contains(required))
        }
    }

    @Test
    fun `Info Details reports the six fields that describe the stream`() {
        val action = bind(OpenHomeInfo::class.java).getAction("Details")
        assertEquals(
            listOf("Duration", "BitRate", "BitDepth", "SampleRate", "Lossless", "CodecName"),
            action.outputArguments.map { it.name },
        )
    }

    @Test
    fun `Time answers with track count, duration and position`() {
        val action = bind(OpenHomeTime::class.java).getAction("Time")
        assertEquals(
            listOf("TrackCount", "Duration", "Seconds"),
            action.outputArguments.map { it.name },
        )
    }

    @Test
    fun `Volume exposes the characteristics a controller scales its slider by`() {
        val action = bind(OpenHomeVolume::class.java).getAction("Characteristics")
        assertEquals(
            listOf(
                "VolumeMax", "VolumeUnity", "VolumeSteps",
                "VolumeMilliDbPerStep", "BalanceMax", "FadeMax",
            ),
            action.outputArguments.map { it.name },
        )
    }

    /**
     * Every evented variable must read back as something its own datatype
     * accepts.
     *
     * This is the test that was missing. jUPnP resolves an evented variable's
     * accessor by name and prefers a *field* over the getter, so a private
     * `trackCount: Int` sitting beside `getTrackCount(): UnsignedIntegerFourBytes`
     * silently bound the Int -- and every event then tried to write a raw
     * Integer into a ui4. Nothing failed at binding time, the service worked
     * for every action, and eventing died on the first track change with
     * "Value is not valid: 1". Controllers lost their subscriptions and
     * dropped the renderer while it carried on playing.
     *
     * Reading through jUPnP's own accessor is the point: asserting the getters
     * return the right types would have passed throughout, because the getters
     * were never the problem.
     */
    private fun assertEventedVariablesReadable(service: LocalService<*>, instance: Any) {
        val evented = service.stateVariables.filter { it.eventDetails.isSendEvents }
        assertTrue("$instance has no evented variables to check", evented.isNotEmpty())
        for (variable in evented) {
            val accessor = service.getAccessor(variable)
            assertNotNull("no accessor for ${variable.name}", accessor)
            val value = accessor.read(instance)
            try {
                // Exactly what GENA does when it writes the event body.
                StateVariableValue(variable, value).toString()
            } catch (e: Throwable) {
                throw AssertionError(
                    "${variable.name} (${variable.typeDetails.datatype.builtin?.descriptorName}) " +
                        "read back as ${value?.javaClass?.simpleName} = $value, " +
                        "which its datatype rejects: ${e.message}",
                )
            }
        }
    }

    @Test
    fun `every evented variable can actually be written to an event`() {
        RendererState.sourceFormat = "FLAC"
        RendererState.sourceRate = 96000
        RendererState.sourceBits = 24
        RendererState.dacVolume = 40

        val list = OpenHomeTrackList()
        list.insert(0, "http://h/a.flac", "")

        assertEventedVariablesReadable(
            bind(OpenHomePlaylist::class.java), OpenHomePlaylist(list))
        assertEventedVariablesReadable(
            bind(OpenHomeInfo::class.java), OpenHomeInfo { null })
        assertEventedVariablesReadable(
            bind(OpenHomeTime::class.java), OpenHomeTime({ 12 }, { 300 }))
        assertEventedVariablesReadable(
            bind(OpenHomeVolume::class.java), OpenHomeVolume { true })
        assertEventedVariablesReadable(
            bind(OpenHomeProduct::class.java),
            OpenHomeProduct(
                roomName = { "Study" },
                sources = listOf(OpenHomeSource("Playlist", "Playlist", "Playlist")),
            ),
        )
    }

    @Test
    fun `the counters still read correctly after a track change`() {
        // The failing value was the counter itself (1, then 2, then 3), so the
        // check has to run after it has been incremented, not only at zero.
        val info = OpenHomeInfo { null }
        val service = bind(OpenHomeInfo::class.java)
        repeat(3) { info.onTrackChanged() }
        assertEventedVariablesReadable(service, info)

        val time = OpenHomeTime({ 5 }, { 300 })
        repeat(3) { time.onTrackChanged() }
        assertEventedVariablesReadable(bind(OpenHomeTime::class.java), time)
    }

    @Test
    fun `the source list names both protocols, and Playlist is index 0`() {
        val product = OpenHomeProduct(
            roomName = { "Study" },
            sources = listOf(
                OpenHomeSource("Playlist", "Playlist", "Playlist"),
                OpenHomeSource("UpnpAv", "UpnpAv", "UPnP AV"),
            ),
        )
        val xml = product.getSourceXml()
        assertTrue(xml.startsWith("<SourceList>"))
        assertTrue(xml.contains("<SystemName>Playlist</SystemName>"))
        assertTrue(xml.contains("<Name>UPnP AV</Name>"))
        assertEquals(0, product.activeIndex)
        assertEquals("Study", product.getProduct().getRoom())
        // Controllers read Attributes to decide which controls to draw.
        assertEquals("Info Time Volume", product.getAttributes())
    }

    @Test
    fun `selecting a source reports it and tells the appliance once`() {
        var selected = -1
        val product = OpenHomeProduct(
            roomName = { "Study" },
            sources = listOf(
                OpenHomeSource("Playlist", "Playlist", "Playlist"),
                OpenHomeSource("UpnpAv", "UpnpAv", "UPnP AV"),
            ),
            onSourceSelected = { selected = it },
        )
        product.selectSource(1)
        assertEquals(1, selected)
        assertEquals(1, product.activeIndex)

        // Re-selecting the live source must not re-notify: the appliance stops
        // the previous source on that callback, so a repeat would stop the
        // track that is playing.
        selected = -1
        product.selectSource(1)
        assertEquals(-1, selected)
    }
}
