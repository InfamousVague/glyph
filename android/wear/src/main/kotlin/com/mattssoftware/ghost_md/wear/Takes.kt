package com.mattssoftware.ghost_md.wear

import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Where a take is on its way to the phone. */
enum class TakeState {
    /** The microphone is on it now. */
    RECORDING,

    /** Recorded, and waiting for the phone: not near, or not tried yet. */
    QUEUED,

    /** On its way down a channel now. */
    SENDING,

    /** Sent whole, and the phone has not said it has it yet. */
    SENT,

    /** The phone has it: the watch's copy is gone. */
    ON_PHONE,
}

data class Take(
    val id: String,
    val recordedAt: Long,
    val durationMs: Long,
    val state: TakeState,
    /** When it was last sent, for the wait for the phone's answer. */
    val sentAt: Long = 0,
    /** Sends that did not end in the phone's answer. */
    val tries: Int = 0,
)

/**
 * The takes on this watch and where each is (docs/WATCH.md, "On the watch"), kept in `takes.json` beside their WAVs
 * so a watch that restarts, or an app that is swiped away, still sends what it recorded. A take's WAV stays until the
 * phone says it has it ([acked]); a take sent and never answered goes back in the queue after [ACK_WAIT_MS]. The last
 * [HISTORY] the phone has are kept, with no sound, for the list under the button.
 *
 * Every change is written through at once and told to [listeners] (the screen), on whichever thread made it; the
 * methods are synchronized, since the recorder, the sender and the listener service each change it from their own.
 */
class TakeQueue(private val dir: File, private val clock: () -> Long = System::currentTimeMillis) {
    private val index = File(dir, "takes.json")
    private val sounds = File(dir, "takes").apply { mkdirs() }
    private var takes: MutableList<Take> = load()
    private val listeners = mutableSetOf<(List<Take>) -> Unit>()

    fun wav(id: String): File = File(sounds, "$id.wav")

    @Synchronized fun all(): List<Take> = takes.sortedByDescending { it.recordedAt }

    @Synchronized fun get(id: String): Take? = takes.firstOrNull { it.id == id }

    @Synchronized fun addListener(listener: (List<Take>) -> Unit) {
        listeners.add(listener)
    }

    @Synchronized fun removeListener(listener: (List<Take>) -> Unit) {
        listeners.remove(listener)
    }

    /** A take whose microphone has just opened. */
    @Synchronized fun begin(id: String, at: Long): Take {
        val take = Take(id = id, recordedAt = at, durationMs = 0, state = TakeState.RECORDING)
        takes.removeAll { it.id == id }
        takes.add(take)
        save()
        return take
    }

    /**
     * A take stopped: queued for the phone, or thrown away when it is under [MIN_MS] (a tap that was a mistake),
     * which answers null.
     */
    @Synchronized fun finish(id: String, durationMs: Long): Take? {
        val at = takes.indexOfFirst { it.id == id }
        if (at < 0) return null
        if (durationMs < MIN_MS) {
            takes.removeAt(at)
            wav(id).delete()
            save()
            return null
        }
        val take = takes[at].copy(durationMs = durationMs, state = TakeState.QUEUED)
        takes[at] = take
        save()
        return take
    }

    /** What is ready to go to the phone, oldest first: queued, and sent so long ago that its answer is not coming. */
    @Synchronized fun toSend(): List<Take> {
        val now = clock()
        var changed = false
        takes = takes.map {
            if (it.state == TakeState.SENT && now - it.sentAt > ACK_WAIT_MS) {
                changed = true
                it.copy(state = TakeState.QUEUED, tries = it.tries + 1)
            } else it
        }.toMutableList()
        if (changed) save()
        return takes.filter { it.state == TakeState.QUEUED && wav(it.id).isFile }.sortedBy { it.recordedAt }
    }

    /** Whether anything is still the watch's to send or to hear about. */
    @Synchronized fun waiting(): Boolean = takes.any { it.state == TakeState.QUEUED || it.state == TakeState.SENDING || it.state == TakeState.SENT }

    @Synchronized fun sending(id: String) = move(id) { it.copy(state = TakeState.SENDING) }

    @Synchronized fun sent(id: String) = move(id) { it.copy(state = TakeState.SENT, sentAt = clock()) }

    /** A send that broke off: back in the queue, one more try counted. */
    @Synchronized fun unsent(id: String) = move(id) { if (it.state == TakeState.ON_PHONE) it else it.copy(state = TakeState.QUEUED, tries = it.tries + 1) }

    /**
     * The phone has the take: its sound goes from the watch and it is kept in the list as on the phone. Answers
     * whether it was one of this watch's; an answer for a take already on the phone changes nothing.
     */
    @Synchronized fun acked(id: String): Boolean {
        val at = takes.indexOfFirst { it.id == id }
        if (at < 0) return false
        wav(id).delete()
        if (takes[at].state != TakeState.ON_PHONE) {
            takes[at] = takes[at].copy(state = TakeState.ON_PHONE)
            trim()
            save()
        }
        return true
    }

    /**
     * After the process was gone: a take left recording is closed from what reached its file (or dropped where nothing
     * did), and one left mid-send is queued again. Answers how many takes were brought back to the queue.
     */
    @Synchronized fun recover(recordingNow: String?): Int {
        var back = 0
        val next = mutableListOf<Take>()
        for (take in takes) {
            when {
                take.state == TakeState.RECORDING && take.id != recordingNow -> {
                    val ms = WavWriter.repair(wav(take.id))
                    if (ms != null && ms >= MIN_MS) {
                        next.add(take.copy(durationMs = ms, state = TakeState.QUEUED))
                        back += 1
                    } else {
                        wav(take.id).delete()
                    }
                }
                take.state == TakeState.SENDING -> {
                    next.add(take.copy(state = TakeState.QUEUED))
                    back += 1
                }
                take.state != TakeState.ON_PHONE && take.state != TakeState.RECORDING && !wav(take.id).isFile -> Unit // its sound is gone: nothing to send
                else -> next.add(take)
            }
        }
        if (next != takes || back > 0) {
            takes = next
            save()
        }
        return back
    }

    private fun move(id: String, change: (Take) -> Take) {
        val at = takes.indexOfFirst { it.id == id }
        if (at < 0) return
        takes[at] = change(takes[at])
        save()
    }

    private fun trim() {
        val done = takes.filter { it.state == TakeState.ON_PHONE }.sortedByDescending { it.recordedAt }
        if (done.size > HISTORY) {
            val gone = done.drop(HISTORY).map { it.id }.toSet()
            takes.removeAll { it.id in gone }
        }
    }

    private fun load(): MutableList<Take> {
        if (!index.isFile) return mutableListOf()
        return try {
            val list = JSONArray(index.readText())
            (0 until list.length()).mapNotNull { i ->
                val o = list.optJSONObject(i) ?: return@mapNotNull null
                val state = runCatching { TakeState.valueOf(o.optString("state")) }.getOrNull() ?: return@mapNotNull null
                Take(o.getString("id"), o.optLong("recordedAt"), o.optLong("durationMs"), state, o.optLong("sentAt"), o.optInt("tries"))
            }.toMutableList()
        } catch (_: Exception) {
            mutableListOf()
        }
    }

    private fun save() {
        val list = JSONArray()
        for (t in takes) {
            list.put(JSONObject().put("id", t.id).put("recordedAt", t.recordedAt).put("durationMs", t.durationMs).put("state", t.state.name).put("sentAt", t.sentAt).put("tries", t.tries))
        }
        val part = File(dir, "takes.json.part")
        part.writeText(list.toString())
        if (!part.renameTo(index)) {
            index.delete()
            part.renameTo(index)
        }
        val now = all()
        for (listener in listeners.toList()) listener(now)
    }

    companion object {
        /** A take shorter than this was a tap, not a note. */
        const val MIN_MS = 600L

        /** How long the phone has to say it has a take before it is sent again. */
        const val ACK_WAIT_MS = 2L * 60 * 1000

        /** How many takes the phone has are listed. */
        const val HISTORY = 8
    }
}
