package com.mattssoftware.ghost_md.wear

import com.mattssoftware.ghost_md.watchlink.WatchLink
import java.io.Closeable
import java.io.File
import java.io.RandomAccessFile
import kotlin.math.log10
import kotlin.math.sqrt

/**
 * A take's sound as it is recorded: 16 kHz mono 16-bit PCM in a WAV, the file the phone's Whisper reads
 * (native/src/capture.rs `transcribe_wav`, the write-up's `wav::read`), written as it comes so a watch that dies
 * mid-take keeps all but the last read. The header is written first with its sizes at zero and put right by [close];
 * a file a kill left short is put right by [repair] the next time the app runs.
 */
class WavWriter(private val file: File) : Closeable {
    private val out = RandomAccessFile(file, "rw")
    private var dataBytes = 0L
    private var buffer = ByteArray(0)

    init {
        out.setLength(0)
        out.write(header(0))
    }

    /** How long the take is so far. */
    val durationMs: Long get() = bytesToMs(dataBytes)

    /** Adds [count] samples of [samples]. */
    fun write(samples: ShortArray, count: Int) {
        if (count <= 0) return
        if (buffer.size < count * 2) buffer = ByteArray(count * 2)
        for (i in 0 until count) {
            val s = samples[i].toInt()
            buffer[i * 2] = (s and 0xFF).toByte()
            buffer[i * 2 + 1] = ((s shr 8) and 0xFF).toByte()
        }
        out.write(buffer, 0, count * 2)
        dataBytes += count * 2
    }

    /** The sizes put right, and the file let go. */
    override fun close() {
        out.seek(0)
        out.write(header(dataBytes))
        out.close()
    }

    companion object {
        const val HEADER_BYTES = 44
        private const val BYTES_PER_MS = WatchLink.SAMPLE_RATE * 2 / 1000

        fun bytesToMs(bytes: Long): Long = bytes / BYTES_PER_MS

        /** The 44-byte header of a 16 kHz mono 16-bit WAV with [dataBytes] of sound after it. */
        fun header(dataBytes: Long): ByteArray {
            val rate = WatchLink.SAMPLE_RATE
            val h = ByteArray(HEADER_BYTES)
            fun text(at: Int, s: String) = s.forEachIndexed { i, c -> h[at + i] = c.code.toByte() }
            fun int(at: Int, v: Long) { for (i in 0 until 4) h[at + i] = ((v shr (8 * i)) and 0xFF).toByte() }
            fun short(at: Int, v: Int) { h[at] = (v and 0xFF).toByte(); h[at + 1] = ((v shr 8) and 0xFF).toByte() }
            text(0, "RIFF"); int(4, 36 + dataBytes); text(8, "WAVE")
            text(12, "fmt "); int(16, 16); short(20, 1); short(22, 1)
            int(24, rate.toLong()); int(28, rate * 2L); short(32, 2); short(34, 16)
            text(36, "data"); int(40, dataBytes)
            return h
        }

        /**
         * A take's file a kill left with its sizes at zero, put right from its length; answers its length in ms, or
         * null where it is not a WAV at all. An odd last byte (half a sample) is cut off.
         */
        fun repair(file: File): Long? {
            if (!file.isFile || file.length() < HEADER_BYTES) return null
            RandomAccessFile(file, "rw").use { raf ->
                val start = ByteArray(4)
                raf.readFully(start)
                if (String(start, Charsets.US_ASCII) != "RIFF") return null
                var data = raf.length() - HEADER_BYTES
                if (data % 2 != 0L) {
                    data -= 1
                    raf.setLength(HEADER_BYTES + data)
                }
                raf.seek(0)
                raf.write(header(data))
                return bytesToMs(data)
            }
        }
    }
}

/** How loud a read was, for the ring around the button: 0 at -60 dBFS and below, 1 at full scale. */
object Levels {
    fun of(samples: ShortArray, count: Int): Float {
        if (count <= 0) return 0f
        var sum = 0.0
        for (i in 0 until count) {
            val s = samples[i] / 32768.0
            sum += s * s
        }
        val rms = sqrt(sum / count)
        if (rms <= 0.0) return 0f
        val db = 20 * log10(rms)
        return ((db + 60) / 60).toFloat().coerceIn(0f, 1f)
    }
}
