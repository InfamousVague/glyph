package com.infamousvague.ghostmessaging

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The sign-in codes offered to Ghost Keyboard ([Codes.pick]): which texts' codes, in what order, for how long. */
class CodesTest {
    private val now = 1_800_000_000_000L
    private fun ago(minutes: Double) = now - (minutes * 60_000).toLong()
    private fun codes(vararg texts: Pair<String, Long>) = Codes.pick(texts.toList(), now).map { it.code }

    @Test fun aCodeIsOfferedAndOrdinaryWordsAreNot() {
        assertEquals(listOf("482913"), codes("Your verification code is 482913. Don't share it." to ago(1.0), "See you at 7" to ago(0.5)))
        assertTrue(codes("Call me at 5551234567 when you land" to ago(1.0)).isEmpty())
    }

    @Test fun theNewestComesFirstAndTheSameCodeOnce() {
        assertEquals(
            listOf("111222", "482913"),
            codes("Your code is 482913" to ago(4.0), "Use 111222 to sign in" to ago(1.0), "Your code is 482913" to ago(2.0)),
        )
        // The time kept for a code that came twice is its newest text's.
        val held = Codes.pick(listOf("Your code is 482913" to ago(4.0), "Your code is 482913" to ago(2.0)), now)
        assertEquals(ago(2.0), held.single().at)
    }

    @Test fun aCodeIsLetGoAfterTenMinutes() {
        assertEquals(listOf("482913"), codes("Your code is 482913" to ago(9.9)))
        assertTrue(codes("Your code is 482913" to ago(10.0)).isEmpty())
        // A text dated ahead of the clock (a carrier's stamp, a clock set back) is not offered for ever.
        assertTrue(codes("Your code is 482913" to now + 5 * 60_000L).isEmpty())
    }

    @Test fun threeAtMost() {
        val four = (1..4).map { "Your code is 10000$it" to ago(it.toDouble()) }
        assertEquals(listOf("100001", "100002", "100003"), Codes.pick(four, now).map { it.code })
    }
}
