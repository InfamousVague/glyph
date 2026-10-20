package com.mattssoftware.ghost_md.watch

import com.mattssoftware.ghost_md.watchlink.TakeFrame
import com.mattssoftware.ghost_md.watchlink.TakeMeta
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException

/** The phone's side of a take (docs/WATCH.md, "On the phone"): kept whole, kept once, and handed to the app. */
class WatchInboxTest {
    @get:Rule val tmp = TemporaryFolder()

    private fun wav(samples: Int): ByteArray {
        val data = samples * 2
        val h = ByteArray(44)
        "RIFF".toByteArray().copyInto(h, 0)
        "WAVE".toByteArray().copyInto(h, 8)
        return h + ByteArray(data) { (it % 7).toByte() }
    }

    private fun sent(id: String, sound: ByteArray, at: Long = 1_000, cutAt: Int? = null): ByteArrayInputStream {
        val out = ByteArrayOutputStream()
        TakeFrame.write(out, TakeMeta(id = id, recordedAt = at, durationMs = sound.size / 32L, watch = "Galaxy Watch9", bytes = sound.size.toLong()))
        out.write(sound, 0, cutAt ?: sound.size)
        return ByteArrayInputStream(out.toByteArray())
    }

    @Test
    fun aTakeIsKeptWholeAndListedForTheApp() {
        val inbox = WatchInbox(tmp.root) { 5_000 }
        val sound = wav(16_000)
        val got = inbox.receive(sent("take-1", sound))
        assertTrue(got is WatchInbox.Received.Kept)

        val waiting = inbox.waiting().single()
        assertEquals("take-1", waiting.meta.id)
        assertEquals("Galaxy Watch9", waiting.meta.watch)
        assertEquals(File(tmp.root, "inbox/take-1.wav"), waiting.wav)
        assertArrayEquals(sound, waiting.wav.readBytes())
        val last = inbox.last()!!
        assertEquals("take-1", last.getString("id"))
        assertEquals(5_000L, last.getLong("receivedAt"))
    }

    @Test
    fun aTakeSentAgainIsAnsweredButKeptOnceWaitingOrMadeANote() {
        val inbox = WatchInbox(tmp.root)
        val sound = wav(800)
        assertTrue(inbox.receive(sent("a", sound)) is WatchInbox.Received.Kept)
        // Sent again before the app made it a note: the stream is read to its end (the channel closes cleanly) and
        // nothing is kept twice.
        val again = sent("a", sound)
        assertTrue(inbox.receive(again) is WatchInbox.Received.Again)
        assertEquals(0, again.available())
        assertEquals(1, inbox.waiting().size)

        inbox.done("a")
        assertTrue(inbox.waiting().isEmpty())
        assertFalse(File(tmp.root, "inbox/a.wav").exists())
        // And again after: the note was made, so it stays one note.
        assertTrue(inbox.receive(sent("a", sound)) is WatchInbox.Received.Again)
        assertTrue(inbox.waiting().isEmpty())
    }

    @Test
    fun aTakeThatBrokeOffIsNotKeptAndTheWatchSendsItAgain() {
        val inbox = WatchInbox(tmp.root)
        val sound = wav(4_000)
        try {
            inbox.receive(sent("cut", sound, cutAt = 1_000))
            fail("kept a take that broke off")
        } catch (_: IOException) {
        }
        assertTrue(inbox.waiting().isEmpty())
        assertFalse(File(tmp.root, "inbox/cut.wav.part").exists())
        assertNull(inbox.last())
        // Whole, the second time.
        assertTrue(inbox.receive(sent("cut", sound)) is WatchInbox.Received.Kept)
    }

    @Test
    fun soundThatIsNoWavIsRefused() {
        val inbox = WatchInbox(tmp.root)
        try {
            inbox.receive(sent("junk", ByteArray(100) { 9 }))
            fail("kept a take that is no WAV")
        } catch (_: IOException) {
        }
        assertTrue(inbox.waiting().isEmpty())
    }

    @Test
    fun theTakesWaitOldestFirstAndOnlyThoseWrittenWhole() {
        val inbox = WatchInbox(tmp.root)
        inbox.receive(sent("later", wav(10), at = 2_000))
        inbox.receive(sent("sooner", wav(10), at = 1_000))
        // A WAV whose JSON never came (the phone died between the two writes) is not a take yet.
        File(tmp.root, "inbox/orphan.wav").writeBytes(wav(10))
        assertEquals(listOf("sooner", "later"), inbox.waiting().map { it.meta.id })
    }

    @Test
    fun onlyTheLastFiveHundredNotesAreRemembered() {
        val inbox = WatchInbox(tmp.root)
        for (i in 0 until WatchInbox.SEEN + 1) inbox.done("t$i")
        // The first was forgotten, so it would be kept again: the app's note id, made from the take's, keeps it one note.
        assertTrue(inbox.receive(sent("t0", wav(10))) is WatchInbox.Received.Kept)
        assertTrue(inbox.receive(sent("t1", wav(10))) is WatchInbox.Received.Again)
        // An id that would name a file elsewhere is never removed by.
        inbox.done("../Library")
    }
}
