package com.infamousvague.ghostmessaging

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MmsWhyTest {
    @Test
    fun mobileDataOffIsSaidAsThat() {
        assertTrue(MmsWhy.send(11).startsWith("mobile data is off"))
        assertTrue(MmsWhy.send(8).contains("mobile data"))
    }

    @Test
    fun theCarriersHttpAnswerIsKept() {
        assertTrue(MmsWhy.send(4, 403).contains("HTTP 403"))
        // No answer at all is not a refusal.
        assertTrue(MmsWhy.send(4, 0).contains("couldn't be reached"))
    }

    @Test
    fun aCodeNobodyKnowsIsStillSaid() {
        assertTrue(MmsWhy.send(99).contains("code 99"))
    }

    @Test
    fun aMessageTheCarrierNoLongerHasIsNotAFault() {
        assertTrue(MmsWhy.download(4, 404).contains("no longer has it"))
        assertEquals(MmsWhy.send(11), MmsWhy.download(11))
    }

    @Test
    fun aLostConnectionIsTriedAgainAndARefusalIsNot() {
        // No route to the carrier, the carrier asking for patience, its server in trouble or not answering.
        assertTrue(MmsWhy.worthAnotherTry(3, 0))
        assertTrue(MmsWhy.worthAnotherTry(6, 0))
        assertTrue(MmsWhy.worthAnotherTry(8, 0))
        assertTrue(MmsWhy.worthAnotherTry(4, 503))
        assertTrue(MmsWhy.worthAnotherTry(4, 0))
        // What the person has to mend, or the carrier said no to: asking again changes nothing.
        assertFalse(MmsWhy.worthAnotherTry(11, 0))
        assertFalse(MmsWhy.worthAnotherTry(12, 0))
        assertFalse(MmsWhy.worthAnotherTry(13, 0))
        assertFalse(MmsWhy.worthAnotherTry(4, 413))
        assertFalse(MmsWhy.worthAnotherTry(5, 0))
        assertTrue(MmsWhy.waitBefore(2) < MmsWhy.waitBefore(3))
    }

    @Test
    fun anAcceptedMessageIsNotRefused() {
        assertNull(MmsWhy.refused(null, null))
        assertNull(MmsWhy.refused(0x80, "OK"))
    }

    @Test
    fun aRefusalCarriesTheCarriersOwnWords() {
        assertEquals("the carrier doesn't know the number it is for: \"Unknown subscriber\"", MmsWhy.refused(0x84, " Unknown subscriber "))
        assertTrue(MmsWhy.refused(0xE2, null)!!.endsWith("(status 0xE2)"))
        assertTrue(MmsWhy.refused(0xC0, "")!!.startsWith("the carrier couldn't take it just now"))
    }
}
