package com.mattssoftware.ghost_md

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * `ghost_md/meet_audio` on the phone: a meeting Ghost was in, its sound made the WAV a meeting recorded here keeps
 * (lib/meet/tape.dart, docs/MEET.md "On the device"), the twin of macos/Runner/MeetAudio.swift. Dart reads the bot's
 * WebM and hands over its Opus packets in a file (`GOP1`, lib/meet/webm.dart `packedForDecoder`); this decodes them
 * with the phone's own Opus decoder (MediaCodec, given the `OpusHead`, the codec delay and the seek pre-roll as its
 * three codec-specific buffers, so the decoder drops the pre-skip itself), mixes the channels to one, and takes 48 kHz
 * to 16 kHz through a windowed-sinc low-pass, writing 16-bit PCM a buffer at a time, so an hour is never held whole.
 *
 * - `opusToWav {packets, wav}` -> `{ms}`: an error with the reason where the packets will not decode.
 *
 * On a thread of its own; the answer is given on the main one.
 */
object MeetAudio {
    private const val CHANNEL = "ghost_md/meet_audio"
    private val door = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "opusToWav") return@setMethodCallHandler result.notImplemented()
            val packets = call.argument<String>("packets")
            val wav = call.argument<String>("wav")
            if (packets == null || wav == null) return@setMethodCallHandler result.error("meet_audio", "Where are the packets, and where does the sound go?", null)
            door.execute {
                try {
                    val ms = opusToWav(File(packets), File(wav))
                    main.post { result.success(mapOf("ms" to ms)) }
                } catch (failure: Throwable) {
                    File(wav).delete()
                    main.post { result.error("meet_audio", failure.message ?: "The meeting's sound would not decode.", null) }
                }
            }
        }
    }

    /** The packets file, read. */
    class Packets(val channels: Int, val codecDelayNs: Long, val seekPreRollNs: Long, val head: ByteArray, val data: ByteArray, val offsets: IntArray, val sizes: IntArray, val frames: IntArray)

    fun read(file: File): Packets {
        val data = file.readBytes()
        val buffer = ByteBuffer.wrap(data).order(ByteOrder.BIG_ENDIAN)
        require(data.size >= 8 && String(data, 0, 4, Charsets.US_ASCII) == "GOP1") { "Those are not a meeting's packets." }
        val length = buffer.getInt(4)
        require(length > 0 && 8 + length <= data.size) { "Those packets have no head." }
        val head = org.json.JSONObject(String(data, 8, length, Charsets.UTF_8))
        val headBytes = head.optInt("headBytes", 0)
        var at = 8 + length
        val opusHead = data.copyOfRange(at, (at + headBytes).coerceAtMost(data.size))
        at += headBytes
        val offsets = ArrayList<Int>()
        val sizes = ArrayList<Int>()
        val frames = ArrayList<Int>()
        while (at + 8 <= data.size) {
            val size = buffer.getInt(at)
            val count = buffer.getInt(at + 4)
            if (size < 0 || at + 8 + size > data.size) break
            if (size > 0) {
                offsets.add(at + 8)
                sizes.add(size)
                frames.add(count)
            }
            at += 8 + size
        }
        return Packets(
            channels = head.optInt("channels", 1).coerceIn(1, 2),
            codecDelayNs = head.optLong("codecDelayNs", 0),
            seekPreRollNs = head.optLong("seekPreRollNs", 80_000_000),
            head = opusHead,
            data = data,
            offsets = offsets.toIntArray(),
            sizes = sizes.toIntArray(),
            frames = frames.toIntArray(),
        )
    }

    /** A 16 kHz mono 16-bit WAV, its header written last. */
    private class Wav(file: File) {
        private val out = RandomAccessFile(file, "rw").also { it.setLength(0); it.write(ByteArray(44)) }
        private val bytes = ByteBuffer.allocate(8192 * 2).order(ByteOrder.LITTLE_ENDIAN)
        var samples = 0L

        fun put(sample: Float) {
            bytes.putShort((sample * 32767f).roundToInt().coerceIn(-32768, 32767).toShort())
            samples += 1
            if (!bytes.hasRemaining()) flush()
        }

        private fun flush() {
            out.write(bytes.array(), 0, bytes.position())
            bytes.clear()
        }

        fun close() {
            flush()
            val data = (samples * 2).toInt()
            val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
            header.put("RIFF".toByteArray(Charsets.US_ASCII)).putInt(36 + data).put("WAVEfmt ".toByteArray(Charsets.US_ASCII))
            header.putInt(16).putShort(1).putShort(1).putInt(16000).putInt(32000).putShort(2).putShort(16)
            header.put("data".toByteArray(Charsets.US_ASCII)).putInt(data)
            out.seek(0)
            out.write(header.array())
            out.close()
        }
    }

    /**
     * Mono sound at [rate] to 16 kHz: a whole-number ratio through a windowed-sinc low-pass and every n-th sample
     * kept; any other ratio (a decoder that answers other than 48 kHz) by straight-line interpolation.
     */
    private class Resampler(private val rate: Int, private val wav: Wav) {
        private val factor = if (rate % 16000 == 0) rate / 16000 else 0
        private val taps: FloatArray
        private val history: FloatArray
        private var at = 0
        private var phase = 0
        private var position = 0.0
        private var last = 0f

        init {
            val n = if (factor > 1) 16 * factor + 1 else 1
            taps = FloatArray(n)
            if (n == 1) {
                taps[0] = 1f
            } else {
                // Cut a little under 8 kHz, so what folds back is out of speech.
                val cutoff = 7200.0 / rate
                var sum = 0.0
                for (i in 0 until n) {
                    val m = i - (n - 1) / 2.0
                    val sinc = if (m == 0.0) 2 * cutoff else sin(2 * PI * cutoff * m) / (PI * m)
                    val window = 0.54 - 0.46 * cos(2 * PI * i / (n - 1))
                    taps[i] = (sinc * window).toFloat()
                    sum += taps[i]
                }
                for (i in 0 until n) taps[i] = (taps[i] / sum).toFloat()
            }
            // Twice the taps' length, each sample written at both halves, so the newest n are always one run.
            history = FloatArray(2 * n)
        }

        fun push(sample: Float) {
            if (factor == 0) {
                // Straight-line: one output each time the input passes the next 1/16000 s.
                val step = rate / 16000.0
                while (position <= 1.0) {
                    wav.put(last + (sample - last) * position.toFloat())
                    position += step
                }
                position -= 1.0
                last = sample
                return
            }
            val n = taps.size
            history[at] = sample
            history[at + n] = sample
            at = if (at + 1 == n) 0 else at + 1
            phase += 1
            if (phase < factor) return
            phase = 0
            // The oldest of the newest n is at `at`; the taps are symmetric, so their order does not matter.
            var sum = 0f
            for (i in 0 until n) sum += taps[i] * history[at + i]
            wav.put(sum)
        }
    }

    /** Decodes [packetsFile] into the WAV at [wavFile]; answers its length in ms. */
    fun opusToWav(packetsFile: File, wavFile: File): Long {
        val packets = read(packetsFile)
        require(packets.sizes.isNotEmpty()) { "That meeting has no sound in it." }
        val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_OPUS, 48000, packets.channels)
        format.setByteBuffer("csd-0", ByteBuffer.wrap(packets.head))
        format.setByteBuffer("csd-1", ByteBuffer.allocate(8).order(ByteOrder.nativeOrder()).putLong(packets.codecDelayNs).also { it.flip() })
        format.setByteBuffer("csd-2", ByteBuffer.allocate(8).order(ByteOrder.nativeOrder()).putLong(packets.seekPreRollNs).also { it.flip() })
        val codec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_AUDIO_OPUS)
        val wav = Wav(wavFile)
        try {
            codec.configure(format, null, null, 0)
            codec.start()
            var channels = packets.channels
            var resampler = Resampler(48000, wav)
            val info = MediaCodec.BufferInfo()
            var next = 0
            var timeUs = 0L
            var inputDone = false
            while (true) {
                if (!inputDone) {
                    val index = codec.dequeueInputBuffer(10_000)
                    if (index >= 0) {
                        val into = codec.getInputBuffer(index)!!
                        into.clear()
                        if (next >= packets.sizes.size) {
                            codec.queueInputBuffer(index, 0, 0, timeUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            val size = packets.sizes[next]
                            into.put(packets.data, packets.offsets[next], size)
                            codec.queueInputBuffer(index, 0, size, timeUs, 0)
                            timeUs += packets.frames[next] * 1_000_000L / 48000
                            next += 1
                        }
                    }
                }
                val out = codec.dequeueOutputBuffer(info, 10_000)
                if (out == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val said = codec.outputFormat
                    channels = said.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    resampler = Resampler(said.getInteger(MediaFormat.KEY_SAMPLE_RATE), wav)
                } else if (out >= 0) {
                    val pcm = codec.getOutputBuffer(out)!!.order(ByteOrder.nativeOrder())
                    pcm.position(info.offset)
                    pcm.limit(info.offset + info.size)
                    val shorts = pcm.asShortBuffer()
                    val share = 1f / (channels * 32768f)
                    while (shorts.remaining() >= channels) {
                        var sum = 0f
                        for (c in 0 until channels) sum += shorts.get()
                        resampler.push(sum * share)
                    }
                    codec.releaseOutputBuffer(out, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
        } finally {
            try { codec.stop() } catch (_: Throwable) {}
            codec.release()
            wav.close()
        }
        return wav.samples / 16
    }
}
