package com.hifirend.airplay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The pure half of working out who is streaming: what counts as a name.
 *
 * The resolve itself needs a network and Android's NSD, but the decision that
 * actually shows something to a person is this one, and its failure mode is
 * putting an IP address or a Bonjour suffix on the screen where a name should
 * be.
 */
class DacpSenderNameTest {

    @Test
    fun `builds the instance name a sender advertises`() {
        // Measured from macOS 26: DACP-ID 20BC6070E22D669E is advertised as
        // iTunes_Ctrl_20BC6070E22D669E on _dacp._tcp.
        assertEquals("iTunes_Ctrl_20BC6070E22D669E",
            DacpSenderName.serviceName("20BC6070E22D669E"))
    }

    @Test
    fun `strips the Bonjour suffix and the trailing dot`() {
        // dns-sd reports the host with both. Neither is part of what anyone
        // calls their computer.
        assertEquals("Walrus", DacpSenderName.friendlyName("Walrus.local."))
        assertEquals("Walrus", DacpSenderName.friendlyName("Walrus.local"))
        assertEquals("Walrus", DacpSenderName.friendlyName("Walrus"))
    }

    @Test
    fun `a name with dots in it survives`() {
        // Only the .local suffix goes. A machine genuinely called
        // "Study.Mac.mini" keeps its name.
        assertEquals("Study.Mac.mini", DacpSenderName.friendlyName("Study.Mac.mini.local."))
    }

    @Test
    fun `an address is not a name`() {
        // Android's resolver hands back a bare address when it has nothing
        // better. "AirPlay from 192.168.100.134" tells the owner less than the
        // "Unknown track" it would replace, so it is refused and the honest
        // fallback stands.
        assertNull(DacpSenderName.friendlyName("192.168.100.134"))
        assertNull(DacpSenderName.friendlyName("192.168.100.134."))
        assertNull(DacpSenderName.friendlyName("fe80::1c9d:2aff:fe4b:1"))
        assertNull(DacpSenderName.friendlyName("2806:2f0:ab80:e254:6ccc:4eff:feca:3256"))
    }

    @Test
    fun `a hostname that merely starts with digits is still a name`() {
        // Four all-numeric parts is an address; anything else is not. A Mac
        // called "2nd.Floor" must not be mistaken for one.
        assertEquals("2nd.Floor", DacpSenderName.friendlyName("2nd.Floor.local"))
        assertEquals("192.168.1", DacpSenderName.friendlyName("192.168.1"))
    }

    @Test
    fun `nothing usable yields nothing`() {
        assertNull(DacpSenderName.friendlyName(null))
        assertNull(DacpSenderName.friendlyName(""))
        assertNull(DacpSenderName.friendlyName("   "))
        assertNull(DacpSenderName.friendlyName("."))
        assertNull(DacpSenderName.friendlyName(".local"))
    }
}
