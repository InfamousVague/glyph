package com.mattssoftware.ghost_md

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * A note's recording, played: the phone's half of lib/tapes/phone_player.dart, and what the page's `<audio>` over
 * the `rec` scheme was to the Tauri app (src/app/tapes/useTape.ts; src-tauri/src/lib.rs served
 * `<app data>/recordings/<id>.wav`). Two for the whole app, each on a channel of its own name: the tape's
 * (`ghost_md/tape`, the page's one `<audio>` on a note's screen) and the voice memos' (`ghost_md/clip`, the element
 * the page made for a memo: editor/clips.ts), so a memo played takes nothing from the tape's playhead and the two
 * can sound at once, as two elements did.
 *
 * THE CHANNEL, `ghost_md/tape` for one and `ghost_md/clip` for the other:
 * - `load {noteId}` -> the recording's length in ms, stopped at its start; an error where there is no such file or
 *   it cannot be read. `load {file}` the same for a sound file a note links (`<data>/images/files/<name>`, a voice-over
 *   among them) and `load {cached}` for a sound kept in the cache (`<cache>/sounds/<name>`, an ElevenLabs voice's
 *   preview): lib/tapes/phone_player.dart `loadArguments`.
 * - `play`, `pause` -> null; `seek {ms}` -> null.
 * - `onDevice {noteId}` -> whether that note's recording is a file here (the `rec` scheme's 200 or 404).
 * - `release` -> null: the player let go.
 *
 * THE EVENTS on the channel's name with `/events` after it, each a map: `{event: "position", ms}` ten times a second while it plays
 * (the element's `timeupdate`), `{event: "playing", on}`, `{event: "ended"}` and `{event: "failed"}`.
 *
 * Only ever a file under the app's own `recordings` folder, named by a note's id, or under its files' or its cache's
 * sounds' folder, named as the app names a kept file: an id is letters, digits, `-` and `_`, a name that and an
 * extension, so nothing a caller says can name a file anywhere else.
 */
class TapePlayer(private val context: Context, private val channel: String = CHANNEL) {
    private val main = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private var sink: EventChannel.EventSink? = null

    private val tick = object : Runnable {
        override fun run() {
            val playing = player ?: return
            if (!playing.isPlaying) return
            say(mapOf("event" to "position", "ms" to playing.currentPosition))
            main.postDelayed(this, TICK_MS)
        }
    }

    fun register(messenger: BinaryMessenger) {
        EventChannel(messenger, "$channel/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
            override fun onCancel(arguments: Any?) { sink = null }
        })
        MethodChannel(messenger, channel).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "load" -> result.success(load(soundOf(call.argument<String>("file"), call.argument<String>("cached")) ?: fileOf(call.argument<String>("noteId"))))
                    "play" -> { play(); result.success(null) }
                    "pause" -> { pause(); result.success(null) }
                    "seek" -> { player?.seekTo(call.argument<Int>("ms") ?: 0); result.success(null) }
                    "onDevice" -> result.success(fileOf(call.argument<String>("noteId"))?.isFile == true)
                    "release" -> { release(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (failure: Exception) {
                result.error("tape", failure.message ?: "The recording could not be played.", null)
            }
        }
    }

    /** The recording's file for a note's id, or null for an id that is not one. */
    private fun fileOf(noteId: String?): File? {
        if (noteId == null || !ID.matches(noteId)) return null
        return File(File(context.dataDir, "recordings"), "$noteId.wav")
    }

    /** A sound file a note links, or one in the cache's sounds, by its kept name; null where neither is asked for. */
    private fun soundOf(file: String?, cached: String?): File? {
        val name = file ?: cached ?: return null
        if (!NAME.matches(name)) throw IllegalStateException("That is not a sound this app keeps.")
        return if (file != null) File(File(File(context.dataDir, "images"), "files"), name) else File(File(context.cacheDir, "sounds"), name)
    }

    private fun load(file: File?): Int {
        release()
        if (file == null || !file.isFile) throw IllegalStateException("This recording is not on this device.")
        val made = MediaPlayer()
        try {
            made.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            made.setDataSource(file.absolutePath)
            made.prepare()
        } catch (failure: Exception) {
            made.release()
            throw failure
        }
        made.setOnCompletionListener {
            main.removeCallbacks(tick)
            say(mapOf("event" to "playing", "on" to false))
            say(mapOf("event" to "ended"))
        }
        made.setOnErrorListener { _, _, _ ->
            main.removeCallbacks(tick)
            say(mapOf("event" to "playing", "on" to false))
            say(mapOf("event" to "failed"))
            true
        }
        player = made
        return made.duration
    }

    private fun play() {
        val loaded = player ?: throw IllegalStateException("No recording is loaded.")
        loaded.start()
        say(mapOf("event" to "playing", "on" to true))
        main.removeCallbacks(tick)
        main.post(tick)
    }

    private fun pause() {
        val loaded = player ?: return
        if (loaded.isPlaying) loaded.pause()
        main.removeCallbacks(tick)
        say(mapOf("event" to "position", "ms" to loaded.currentPosition))
        say(mapOf("event" to "playing", "on" to false))
    }

    /** The player let go: the activity's end, or another recording loaded. */
    fun release() {
        main.removeCallbacks(tick)
        player?.release()
        player = null
    }

    private fun say(event: Map<String, Any>) {
        main.post { sink?.success(event) }
    }

    companion object {
        const val CHANNEL = "ghost_md/tape"

        /** The voice memos' player: one of their own, beside the tape's. */
        const val CLIPS = "ghost_md/clip"
        private const val TICK_MS = 100L
        private val ID = Regex("^[A-Za-z0-9_-]{1,64}$")
        private val NAME = Regex("^[A-Za-z0-9_-]{1,64}\\.[a-z0-9]{1,10}$")
    }
}
