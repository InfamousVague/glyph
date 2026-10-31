package com.mattssoftware.ghost_md

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.File

/**
 * A note's film, played: the phone's half of lib/core/phone_films.dart's player, and what the page's `<video>` over
 * the `vid` scheme was to the Tauri app (src/app/editor/videos.ts; src-tauri/src/videos.rs served
 * `<app data>/video/<name>` in ranges). There is no WebView to play one in, so each film a card starts is a
 * `MediaPlayer` drawing into a texture of Flutter's, which the card lays over its poster.
 *
 * THE CHANNEL `ghost_md/film`:
 * - `open {name, dirs?}` -> `{id, width, height, ms, turn}`: the texture's id, the film's size as it is stored,
 *   its length, and the quarter turns the app must still make to stand it upright (0 where the texture turns it
 *   itself); an error where there is no such film or it cannot be played. `dirs` is the list of folders the Rust
 *   core reads a film from, the first the one it writes to (library/attachments.rs `Places`, asked by Dart through
 *   `attachment_places`: `<data>/Library/video/` and, from an older build, `<data>/video/`; a library in a folder
 *   of the person's has its own), and the film is the first of them that has it; with no `dirs` the old folder
 *   beside the library is looked in alone, as before 2026-10-31.
 * - `play {id}`, `pause {id}`, `seek {id, ms}` -> null; `close {id}` -> null: the player and its texture let go.
 *
 * THE EVENTS on `ghost_md/film/events`, each a map with the film's `id`: `{event: "position", ms}` ten times a
 * second while it plays (the element's `timeupdate`) and after a seek, `{event: "playing", on}`, `{event: "ended"}`
 * and `{event: "failed"}` (the element's `error`).
 *
 * Only ever a file in one of those folders, by the name its note's line carries: a plain id and one film extension
 * (native/src/kept/videos.rs `valid_name`), so nothing a caller says can name a file outside the folders given.
 * Several may be open at once (a card's own and none other is the usual case); starting one never stops another
 * here, which is the app's to decide, as the page's `playing` was.
 */
class FilmPlayer(private val context: Context, private val textures: TextureRegistry) {
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private val open = HashMap<Long, Playing>()

    private inner class Playing(val producer: TextureRegistry.SurfaceProducer, val player: MediaPlayer) {
        val id: Long get() = producer.id()
        var ended = false

        val tick = object : Runnable {
            override fun run() {
                if (open[id] !== this@Playing || !player.isPlaying) return
                say(mapOf("event" to "position", "id" to id, "ms" to player.currentPosition))
                main.postDelayed(this, TICK_MS)
            }
        }

        fun release() {
            main.removeCallbacks(tick)
            try {
                player.release()
            } catch (_: Exception) {
                // Released already: nothing to let go of.
            }
            producer.release()
        }
    }

    fun register(messenger: BinaryMessenger) {
        EventChannel(messenger, EVENTS).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
            override fun onCancel(arguments: Any?) { sink = null }
        })
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                val playing = (call.argument<Number>("id"))?.toLong()?.let { open[it] }
                when (call.method) {
                    "open" -> result.success(open(call.argument<String>("name"), call.argument<List<*>>("dirs")?.filterIsInstance<String>()?.map { File(it) }?.takeIf { it.isNotEmpty() }))
                    "play" -> { playing?.let(::play); result.success(null) }
                    "pause" -> { playing?.let(::pause); result.success(null) }
                    "seek" -> {
                        playing?.let { film ->
                            film.ended = false
                            film.player.seekTo(call.argument<Number>("ms")?.toInt() ?: 0)
                        }
                        result.success(null)
                    }
                    "close" -> { playing?.let { open.remove(it.id)?.release() }; result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (failure: Exception) {
                result.error("film", failure.message ?: UNPLAYABLE, null)
            }
        }
    }

    /**
     * The film's file for the name a note's line carries, in the first of `dirs` that has it (or the first of them,
     * where none has, so `isFile` says no); null for a name that is not one.
     */
    private fun fileOf(name: String?, dirs: List<File>?): File? {
        if (name == null || !NAME.matches(name)) return null
        val folders = dirs ?: listOf(File(context.dataDir, "video"))
        return folders.map { File(it, name) }.firstOrNull { it.isFile } ?: File(folders.first(), name)
    }

    private fun open(name: String?, dirs: List<File>?): Map<String, Any> {
        val file = fileOf(name, dirs)
        if (file == null || !file.isFile) throw IllegalStateException(MISSING)
        val producer = textures.createSurfaceProducer()
        val made = MediaPlayer()
        try {
            made.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MOVIE).build())
            made.setDataSource(file.absolutePath)
            made.prepare()
            producer.setSize(made.videoWidth.coerceAtLeast(1), made.videoHeight.coerceAtLeast(1))
            made.setSurface(producer.surface)
        } catch (failure: Exception) {
            made.release()
            producer.release()
            throw IllegalStateException(UNPLAYABLE)
        }
        val playing = Playing(producer, made)
        val id = playing.id
        // The texture's surface goes while the app is behind another and comes back with it: the player is handed
        // the new one, and holds its place.
        producer.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
            override fun onSurfaceAvailable() {
                if (open[id] === playing) try { made.setSurface(producer.surface) } catch (_: Exception) {}
            }
            override fun onSurfaceCleanup() {
                if (open[id] === playing) try { made.setSurface(null) } catch (_: Exception) {}
            }
        })
        made.setOnCompletionListener {
            playing.ended = true
            main.removeCallbacks(playing.tick)
            say(mapOf("event" to "position", "id" to id, "ms" to made.duration))
            say(mapOf("event" to "playing", "id" to id, "on" to false))
            say(mapOf("event" to "ended", "id" to id))
        }
        made.setOnSeekCompleteListener { say(mapOf("event" to "position", "id" to id, "ms" to made.currentPosition)) }
        made.setOnErrorListener { _, _, _ ->
            main.removeCallbacks(playing.tick)
            say(mapOf("event" to "playing", "id" to id, "on" to false))
            say(mapOf("event" to "failed", "id" to id))
            true
        }
        open[id] = playing
        // A film says how it is to be turned; a texture that does not turn it leaves that to the app.
        val turn = if (producer.handlesCropAndRotation()) 0 else rotationOf(file)
        return mapOf("id" to id, "width" to made.videoWidth, "height" to made.videoHeight, "ms" to made.duration, "turn" to turn)
    }

    /** How the film says it is to be turned, in degrees; 0 where it does not say. */
    private fun rotationOf(file: File): Int {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.path)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
        } catch (_: Exception) {
            0
        } finally {
            try { retriever.release() } catch (_: Exception) {}
        }
    }

    private fun play(film: Playing) {
        // Played again from its end, as the element starts over.
        if (film.ended) {
            film.ended = false
            film.player.seekTo(0)
        }
        film.player.start()
        say(mapOf("event" to "playing", "id" to film.id, "on" to true))
        main.removeCallbacks(film.tick)
        main.post(film.tick)
    }

    private fun pause(film: Playing) {
        if (film.player.isPlaying) film.player.pause()
        main.removeCallbacks(film.tick)
        say(mapOf("event" to "position", "id" to film.id, "ms" to film.player.currentPosition))
        say(mapOf("event" to "playing", "id" to film.id, "on" to false))
    }

    /** Nothing sounds from an app nobody can see: every film is paused as the activity leaves the front. */
    fun pauseAll() {
        for (film in open.values.toList()) if (film.player.isPlaying) pause(film)
    }

    /** Every player let go: the activity's end. */
    fun release() {
        for (film in open.values.toList()) film.release()
        open.clear()
    }

    private fun say(event: Map<String, Any>) {
        main.post { sink?.success(event) }
    }

    companion object {
        const val CHANNEL = "ghost_md/film"
        const val EVENTS = "ghost_md/film/events"
        private const val TICK_MS = 100L
        const val MISSING = "This video isn’t on this phone."
        const val UNPLAYABLE = "This video can’t be played on this phone."

        /** A film's name: a plain id of at most 64 characters, then one film extension (kept/videos.rs `valid_name`). */
        private val NAME = Regex("^[A-Za-z0-9_-]{1,64}\\.(mp4|m4v|mov|webm)$")
    }
}
