package com.example.remote_control

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class NativeFirewallReadbackTest {
    @Test fun readsOnlyDenyEntriesInTheUidOwnerMap() {
        val dump = """
            BPF map content:
              sCookieTagMap:
                10200 OEM_DENY_3_MATCH
              sUidOwnerMap:
                10421   STANDBY_MATCH OEM_DENY_3_MATCH

                10312 OEM_DENY_2_MATCH
                110315 OEM_DENY_3_MATCH
              sIngressDiscardMap:
                110500 OEM_DENY_3_MATCH
        """.trimIndent()
        assertEquals(setOf(10421, 110315), NativeFirewallReadback.deniedUids(dump))
    }

    @Test fun refusesAnIncompleteTable() {
        assertThrows(IllegalStateException::class.java) {
            NativeFirewallReadback.deniedUids("sUidOwnerMap:\n 10421 OEM_DENY_3_MATCH")
        }
    }
}
