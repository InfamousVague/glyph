package com.mattssoftware.ghost_md.wear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class TakeQueueTest {
    @get:Rule val tmp = TemporaryFolder()

    private var now = 1_000_000L
    private fun queue() = TakeQueue(tmp.root) { now }

    private fun recorded(q: TakeQueue, id: String, at: Long, ms: Long = 5_000): Take? {
        q.begin(id, at)
        q.wav(id).writeBytes(WavWriter.header(ms * 32) + ByteArray((ms * 32).toInt()))
        return q.finish(id, ms)
    }

    @Test
    fun aTakeIsQueuedSentAndLetGoOnlyWhenThePhoneSaysItHasIt() {
        val q = queue()
        val take = recorded(q, "a", at = 10)!!
        assertEquals(TakeState.QUEUED, take.state)
        assertEquals(listOf("a"), q.toSend().map { it.id })

        q.sending("a")
        assertEquals(TakeState.SENDING, q.get("a")!!.state)
        assertTrue(q.toSend().isEmpty())
        q.sent("a")
        assertEquals(TakeState.SENT, q.get("a")!!.state)
        assertTrue("its sound stays until the phone answers", q.wav("a").isFile)
        assertTrue(q.waiting())

        assertTrue(q.acked("a"))
        assertEquals(TakeState.ON_PHONE, q.get("a")!!.state)
        assertFalse(q.wav("a").isFile)
        assertFalse(q.waiting())
        // A second answer for the same take changes nothing; one for a take that was never here is not ours.
        assertTrue(q.acked("a"))
        assertFalse(q.acked("elsewhere"))
    }

    @Test
    fun aTakeSentAndNeverAnsweredIsSentAgainAfterTheWait() {
        val q = queue()
        recorded(q, "a", at = 10)
        q.sending("a")
        q.sent("a")
        now += TakeQueue.ACK_WAIT_MS - 1
        assertTrue(q.toSend().isEmpty())
        now += 2
        val again = q.toSend()
        assertEquals(listOf("a"), again.map { it.id })
        assertEquals(1, again.single().tries)
    }

    @Test
    fun aBrokenSendGoesBackInTheQueueOldestFirst() {
        val q = queue()
        recorded(q, "late", at = 20)
        recorded(q, "early", at = 10)
        assertEquals(listOf("early", "late"), q.toSend().map { it.id })
        q.sending("early")
        q.unsent("early")
        assertEquals(TakeState.QUEUED, q.get("early")!!.state)
        assertEquals(1, q.get("early")!!.tries)
        // The list on the screen is newest first.
        assertEquals(listOf("late", "early"), q.all().map { it.id })
    }

    @Test
    fun aTapThatWasAMistakeIsNotKept() {
        val q = queue()
        assertNull(recorded(q, "tap", at = 10, ms = 200))
        assertNull(q.get("tap"))
        assertFalse(q.wav("tap").exists())
    }

    @Test
    fun theQueueOutlivesTheProcessAndAKilledTakeIsClosedAndQueued() {
        val q = queue()
        recorded(q, "sent", at = 10)
        q.sending("sent")
        // A take the process died during: its file has a header with zero sizes and three seconds after it.
        q.begin("killed", 20)
        q.wav("killed").writeBytes(WavWriter.header(0) + ByteArray(96_000))
        // A take whose microphone opened and closed on nothing.
        q.begin("empty", 30)

        val again = queue()
        assertEquals(2, again.recover(recordingNow = null))
        assertEquals(TakeState.QUEUED, again.get("sent")!!.state)
        assertEquals(TakeState.QUEUED, again.get("killed")!!.state)
        assertEquals(3000L, again.get("killed")!!.durationMs)
        assertNull(again.get("empty"))
        assertEquals(listOf("sent", "killed"), again.toSend().map { it.id })
    }

    @Test
    fun theTakeBeingRecordedNowIsNotClosedUnderTheMicrophone() {
        val q = queue()
        q.begin("live", 10)
        q.wav("live").writeBytes(WavWriter.header(0) + ByteArray(64_000))
        assertEquals(0, queue().recover(recordingNow = "live"))
        assertEquals(TakeState.RECORDING, queue().get("live")!!.state)
    }

    @Test
    fun onlyTheLastFewOnThePhoneAreListed() {
        val q = queue()
        for (i in 1..(TakeQueue.HISTORY + 3)) {
            recorded(q, "t$i", at = i.toLong())
            q.acked("t$i")
        }
        val listed = q.all()
        assertEquals(TakeQueue.HISTORY, listed.size)
        assertEquals("t${TakeQueue.HISTORY + 3}", listed.first().id)
    }

    @Test
    fun everyChangeIsToldToTheScreen() {
        val q = queue()
        val heard = mutableListOf<List<TakeState>>()
        q.addListener { all -> heard.add(all.map { it.state }) }
        recorded(q, "a", at = 10)
        q.acked("a")
        assertEquals(listOf(listOf(TakeState.RECORDING), listOf(TakeState.QUEUED), listOf(TakeState.ON_PHONE)), heard)
    }
}
