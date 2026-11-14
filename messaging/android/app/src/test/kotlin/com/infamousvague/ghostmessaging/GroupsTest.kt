package com.infamousvague.ghostmessaging

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Groups.kt apart from Android: who a group's conversation is with. */
class GroupsTest {
    private val id = "00112233445566778899aabbccddeeff"

    @Test fun aGroupsConversationIsWithAnAddressThatIsNobodys() {
        val address = Groups.address(id)
        assertEquals("gghhiijjkkllmmnnooppaabbccddeeff@group.ghost-sms.com", address)
        assertEquals(id, Groups.idOf(address))
        // No digit is in it: nothing that compares numbers by their last digits takes it for one (E2e.norm keeps
        // it whole, where an id written as it is would have been read as the number 5566778899).
        assertEquals(address, E2e.norm(address))
        assertTrue(address.none { it.isDigit() })
    }

    @Test fun nothingElseIsTakenForOne() {
        assertNull(Groups.idOf("+15551230001"))
        assertNull(Groups.idOf("someone@example.com"))
        assertNull(Groups.idOf("short@group.ghost-sms.com"))
        assertNull(Groups.idOf("$id@group.ghost-sms.com"))
        assertNull(Groups.idOf("${Groups.address(id).uppercase()}"))
        assertNull(Groups.idOf(null))
        assertTrue(Groups.isId(id))
        assertFalse(Groups.isId(id + "0"))
        assertFalse(Groups.isId("g".repeat(32)))
    }
}
