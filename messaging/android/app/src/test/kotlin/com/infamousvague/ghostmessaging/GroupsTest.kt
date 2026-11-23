package com.infamousvague.ghostmessaging

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Groups.kt apart from Android: who a group's conversation is with, and the address a member is reached under. */
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

    // Found in review, 2026-11-23: a group's admin writes each member's address, and the routes found people by it.
    @Test fun aMemberIsNeverReachedUnderAnAddressThisPhonesOwnRecordsHold() {
        // The phone holds an encryption record for Ben's number, written as its owner wrote it.
        val held = setOf(E2e.norm("+1 (555) 000-2222"))
        // A stranger the admin listed under Ben's number, however it is written, is not reached under it.
        assertEquals("", Groups.listed("+15550002222", held))
        assertEquals("", Groups.listed("555-000-2222", held))
        assertEquals("", Groups.listed("0015550002222", held))
        // Nor under a username, which is a friend by username's record's alone.
        assertEquals("", Groups.listed("@maya", held))
        assertEquals("", Groups.listed("@", held))
        // A number no record of this phone's holds is the group's word for them, as before (the wake goes to it).
        assertEquals("+15550003333", Groups.listed("+15550003333", held))
        assertEquals("", Groups.listed("", held))
    }
}
