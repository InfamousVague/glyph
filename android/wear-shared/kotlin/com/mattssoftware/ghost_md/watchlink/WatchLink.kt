package com.mattssoftware.ghost_md.watchlink

import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream

/*
 * THE WORDS THE WATCH AND THE PHONE SPEAK (docs/WATCH.md, "The link"). Compiled into both apps from this one file
 * (android/wear/build.gradle.kts and android/app/build.gradle.kts add `wear-shared/kotlin` to their sources), so a
 * path or a field cannot be renamed on one side only.
 *
 * - A take goes from the watch to the phone over a Data Layer channel at [WatchLink.TAKE_PATH]: [TakeFrame]'s header,
 *   then the take's WAV, byte for byte, and the channel closed.
 * - The phone answers with a message at [WatchLink.ACK_PATH] whose data is the take's id in UTF-8, once the WAV is in
 *   its inbox (or was already: a take sent twice is acknowledged twice and kept once). Only then does the watch let
 *   its copy go.
 * - Each side declares a capability (res/values/wear.xml), so each can find the other among the connected nodes:
 *   the watch sends only to a node with [WatchLink.PHONE_CAPABILITY], and the phone's Settings lists the nodes with
 *   [WatchLink.WATCH_CAPABILITY].
 */
object WatchLink {
    const val TAKE_PATH = "/ghost/take"
    const val ACK_PATH = "/ghost/ack"
    const val PHONE_CAPABILITY = "ghost_md_phone"
    const val WATCH_CAPABILITY = "ghost_md_watch"

    /** The sound a take is: 16 kHz mono 16-bit PCM, the WAV the core's Whisper reads from a file. */
    const val SAMPLE_RATE = 16_000

    /** The longest take the watch records, and so the most the phone takes in one (with the header's 44 bytes). */
    const val MAX_TAKE_MS = 60L * 60 * 1000
    const val MAX_TAKE_BYTES = 44 + MAX_TAKE_MS * SAMPLE_RATE / 1000 * 2

    /** An id that can name a file on either side: letters, digits, '-' and '_', at most 64 of them. */
    fun plainId(id: String): Boolean = id.length in 1..64 && id.all { (it in 'a'..'z') || (it in 'A'..'Z') || (it in '0'..'9') || it == '-' || it == '_' }
}

/** What the phone is told about a take before its sound: who, when, how long, and how many bytes follow. */
data class TakeMeta(
    val id: String,
    /** When the take started, in ms since the epoch on the watch's clock. */
    val recordedAt: Long,
    val durationMs: Long,
    /** The watch's own name, for the phone's Settings ("Galaxy Watch9"). */
    val watch: String,
    /** The WAV's length in bytes, header included. */
    val bytes: Long,
)

/**
 * A take's header on the channel: four bytes of magic and a version, then the [TakeMeta] fields in a fixed order
 * (Java's DataOutput, big-endian, strings as modified UTF-8). Nothing is buffered past the header, so the WAV is read
 * from the same stream after [read].
 */
object TakeFrame {
    private const val MAGIC = 0x47484D57 // "GHMW"
    private const val VERSION = 1

    fun write(out: OutputStream, meta: TakeMeta) {
        val data = DataOutputStream(out)
        data.writeInt(MAGIC)
        data.writeInt(VERSION)
        data.writeUTF(meta.id)
        data.writeLong(meta.recordedAt)
        data.writeLong(meta.durationMs)
        data.writeUTF(meta.watch.take(64))
        data.writeLong(meta.bytes)
        data.flush()
    }

    /** The header, or an [IOException] saying why it is not one this side can read. */
    fun read(input: InputStream): TakeMeta {
        val data = DataInputStream(input)
        if (data.readInt() != MAGIC) throw IOException("not a take")
        val version = data.readInt()
        if (version != VERSION) throw IOException("a take of version $version")
        val id = data.readUTF()
        if (!WatchLink.plainId(id)) throw IOException("a take with no usable id")
        val recordedAt = data.readLong()
        val durationMs = data.readLong()
        val watch = data.readUTF()
        val bytes = data.readLong()
        if (bytes < 44 || bytes > WatchLink.MAX_TAKE_BYTES) throw IOException("a take of $bytes bytes")
        return TakeMeta(id = id, recordedAt = recordedAt, durationMs = durationMs.coerceAtLeast(0), watch = watch, bytes = bytes)
    }
}
