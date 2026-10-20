package com.mattssoftware.ghost_md.watch

import com.mattssoftware.ghost_md.watchlink.TakeFrame
import com.mattssoftware.ghost_md.watchlink.TakeMeta
import com.mattssoftware.ghost_md.watchlink.WatchLink
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.io.InputStream

/**
 * The takes a watch sent, waiting on the phone for the app to make each a voice note (docs/WATCH.md, "On the
 * phone"): `<dataDir>/watch/inbox/<id>.wav` and `<id>.json` (the take's [TakeMeta]), written whole or not at all, so
 * whatever is listed there is a take the watch may already have let go of, and is the phone's to keep until Dart says
 * [done]. Nothing here needs the app to be running: WatchListenerService fills it with the app closed, and the app
 * empties it the next time it runs (lib/watch/watch_notes.dart).
 *
 * ONE TAKE, ONE NOTE. A take is known by its id, which the watch made: one that is waiting, or was made into a note
 * (the last [SEEN] ids, in `seen.json`), is read to its end and answered [Received.Again] without being kept twice,
 * so the watch, which sends again whatever it has not heard back about, can be answered every time. Dart makes the
 * note's id from the take's too, so even a take that came again after `seen.json` forgot it is one note.
 */
class WatchInbox(private val root: File, private val clock: () -> Long = System::currentTimeMillis) {
    private val inbox = File(root, "inbox")
    private val seenFile = File(root, "seen.json")
    private val lastFile = File(root, "last.json")

    sealed class Received {
        /** Kept: a new take waiting for the app. */
        data class Kept(val meta: TakeMeta) : Received()

        /** Had already: waiting, or already a note. Answered all the same. */
        data class Again(val meta: TakeMeta) : Received()
    }

    /** A take waiting for the app. */
    data class Waiting(val meta: TakeMeta, val wav: File)

    /**
     * Reads one take from [input] (a [TakeFrame] header and its WAV) into the inbox. Throws an [IOException] where it
     * is not a take, or broke off before its end: nothing is kept then, and the watch, unanswered, sends it again.
     */
    @Synchronized
    fun receive(input: InputStream): Received {
        val meta = TakeFrame.read(input)
        if (isWaiting(meta.id) || meta.id in seen()) {
            drain(input, meta.bytes)
            return Received.Again(meta)
        }
        inbox.mkdirs()
        val part = File(inbox, "${meta.id}.wav.part")
        try {
            part.outputStream().use { out ->
                val buffer = ByteArray(64 * 1024)
                var left = meta.bytes
                while (left > 0) {
                    val read = input.read(buffer, 0, minOf(buffer.size.toLong(), left).toInt())
                    if (read < 0) throw IOException("the take broke off ${meta.bytes - left} bytes in")
                    out.write(buffer, 0, read)
                    left -= read
                }
            }
            if (!isRiff(part)) throw IOException("the take is not a WAV")
            val wav = File(inbox, "${meta.id}.wav")
            if (!part.renameTo(wav)) throw IOException("the take could not be kept")
            writeAtomically(File(inbox, "${meta.id}.json"), json(meta).toString())
        } catch (failure: IOException) {
            part.delete()
            throw failure
        }
        writeAtomically(lastFile, json(meta).put("receivedAt", clock()).toString())
        return Received.Kept(meta)
    }

    /** The takes waiting, oldest first. A WAV without its JSON was cut short in the write, and is not one. */
    @Synchronized
    fun waiting(): List<Waiting> {
        val files = inbox.listFiles() ?: return emptyList()
        return files.filter { it.name.endsWith(".json") }.mapNotNull { file ->
            val meta = try {
                meta(JSONObject(file.readText()))
            } catch (_: Exception) {
                null
            } ?: return@mapNotNull null
            val wav = File(inbox, "${meta.id}.wav")
            Waiting(meta, wav)
        }.sortedBy { it.meta.recordedAt }
    }

    /** The app has made take [id] a note (or has let it go): its files go, and its id is remembered. */
    @Synchronized
    fun done(id: String) {
        if (!WatchLink.plainId(id)) return
        File(inbox, "$id.wav").delete()
        File(inbox, "$id.json").delete()
        File(inbox, "$id.wav.part").delete()
        val ids = (seen() - id) + id
        root.mkdirs()
        writeAtomically(seenFile, JSONArray(ids.takeLast(SEEN)).toString())
    }

    /** The last take received, with when (`receivedAt`), for Settings; null before the first. */
    @Synchronized
    fun last(): JSONObject? = try {
        if (lastFile.isFile) JSONObject(lastFile.readText()) else null
    } catch (_: Exception) {
        null
    }

    private fun isWaiting(id: String) = File(inbox, "$id.json").isFile

    private fun seen(): List<String> = try {
        if (!seenFile.isFile) emptyList() else JSONArray(seenFile.readText()).let { list -> (0 until list.length()).map { list.getString(it) } }
    } catch (_: Exception) {
        emptyList()
    }

    private fun drain(input: InputStream, bytes: Long) {
        val buffer = ByteArray(64 * 1024)
        var left = bytes
        while (left > 0) {
            val read = input.read(buffer, 0, minOf(buffer.size.toLong(), left).toInt())
            if (read < 0) return
            left -= read
        }
    }

    private fun isRiff(file: File): Boolean = file.length() >= 44 && file.inputStream().use { input ->
        val start = ByteArray(4)
        input.read(start) == 4 && String(start, Charsets.US_ASCII) == "RIFF"
    }

    private fun writeAtomically(file: File, text: String) {
        file.parentFile?.mkdirs()
        val part = File(file.parentFile, "${file.name}.part")
        part.writeText(text)
        if (!part.renameTo(file)) {
            file.delete()
            if (!part.renameTo(file)) throw IOException("${file.name} could not be written")
        }
    }

    companion object {
        /** How many takes made into notes are remembered by id. */
        const val SEEN = 500

        fun json(meta: TakeMeta): JSONObject = JSONObject()
            .put("id", meta.id)
            .put("recordedAt", meta.recordedAt)
            .put("durationMs", meta.durationMs)
            .put("watch", meta.watch)
            .put("bytes", meta.bytes)

        fun meta(json: JSONObject): TakeMeta? {
            val id = json.optString("id")
            if (!WatchLink.plainId(id)) return null
            return TakeMeta(id = id, recordedAt = json.optLong("recordedAt"), durationMs = json.optLong("durationMs"), watch = json.optString("watch"), bytes = json.optLong("bytes"))
        }
    }
}
