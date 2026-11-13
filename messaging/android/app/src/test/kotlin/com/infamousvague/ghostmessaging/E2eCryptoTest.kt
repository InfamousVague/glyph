package com.infamousvague.ghostmessaging

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Two phones, and a third that should read nothing. */
class E2eCryptoTest {
    private val alice = E2eCrypto.newKeyPair()
    private val bob = E2eCrypto.newKeyPair()
    private val eve = E2eCrypto.newKeyPair()
    private val a = E2eCrypto.publicBytes(alice.public)
    private val b = E2eCrypto.publicBytes(bob.public)
    private val e = E2eCrypto.publicBytes(eve.public)

    @Test
    fun aKeyTravelsInATextAndComesBackTheSameKey() {
        assertEquals(33, a.size)
        val text = "Ghost Messaging encryption key.\n" + E2eCrypto.keyText(a)
        assertArrayEquals(a, E2eCrypto.keyIn(text))
        assertEquals(alice.public, E2eCrypto.publicFrom(a))
        // Many keys, so both parities of y are met.
        repeat(40) {
            val k = E2eCrypto.newKeyPair()
            assertEquals(k.public, E2eCrypto.publicFrom(E2eCrypto.publicBytes(k.public)))
        }
        assertNull(E2eCrypto.keyIn("no key here"))
        assertNull(E2eCrypto.keyIn("ghost:k1:" + "A".repeat(44))) // not a point on the curve (or not a valid prefix)
        assertNull(E2eCrypto.publicFrom(ByteArray(33)))
    }

    @Test
    fun bothPhonesMakeTheSameKeyAndReadEachOther() {
        val ka = E2eCrypto.conversationKey(alice.private, a, b)!!
        val kb = E2eCrypto.conversationKey(bob.private, b, a)!!
        assertArrayEquals(ka, kb)
        assertEquals(32, ka.size)
        val words = "See you at 7 👻 — bring the “cable”\nsecond line"
        val wire = E2eCrypto.seal(ka, words)
        assertTrue(wire.startsWith("ghost:e1:"))
        assertTrue(E2eCrypto.isSealed(wire))
        assertTrue("stays in an SMS's own alphabet", wire.all { it.code < 128 })
        assertEquals(words, E2eCrypto.open(kb, wire))
        // The same words twice are two different texts.
        assertNotEquals(wire, E2eCrypto.seal(ka, words))
    }

    @Test
    fun anotherPhoneReadsNothingAndAChangedTextIsRefused() {
        val ka = E2eCrypto.conversationKey(alice.private, a, b)!!
        val ke = E2eCrypto.conversationKey(eve.private, e, a)!!
        val wire = E2eCrypto.seal(ka, "for bob only")
        assertNull(E2eCrypto.open(ke, wire))
        val at = wire.length - 5
        val flipped = wire.substring(0, at) + (if (wire[at] == 'A') 'B' else 'A') + wire.substring(at + 1)
        assertNull(E2eCrypto.open(ka, flipped))
        assertNull(E2eCrypto.open(ka, "hello"))
        assertNull(E2eCrypto.open(ka, "ghost:e1:AAAA"))
        assertNull(E2eCrypto.open(ka, "ghost:e1:not base64 !!"))
    }

    @Test
    fun theSafetyNumberIsTheSameOnBothPhonesAndDiffersWithSomeoneInTheMiddle() {
        val ab = E2eCrypto.safetyNumber(a, b)
        assertEquals(ab, E2eCrypto.safetyNumber(b, a))
        assertTrue(Regex("^(\\d{5} ){5}\\d{5}$").matches(ab))
        // Eve in the middle: Alice holds Eve's key as Bob's, Bob holds Eve's as Alice's. The numbers differ.
        assertNotEquals(E2eCrypto.safetyNumber(a, e), E2eCrypto.safetyNumber(b, e))
        assertNotEquals(ab, E2eCrypto.safetyNumber(a, e))
        assertNotNull(E2eCrypto.fingerprint(a))
    }

    @Test
    fun aKeyPairSurvivesBeingStored() {
        val restored = E2eCrypto.privateFrom(alice.private.encoded)
        assertArrayEquals(E2eCrypto.conversationKey(alice.private, a, b), E2eCrypto.conversationKey(restored, a, b))
    }
}
