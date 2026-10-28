package com.mattssoftware.ghost_md

import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.SoundPool
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * The app's sounds inside the app: the phone's half of lib/sounds/sounds.dart (Matt, 2026-10-27: "build ... the
 * sounds settings"; docs/ideas/CUSTOMIZATION_AND_SOUNDS.md, Sounds). A `SoundPool`, which the doc names for "no lag":
 * each sound is decoded once, when it is primed, and a play is the pool's alone.
 *
 * THE CHANNEL, `ghost_md/sounds`:
 * - `prime {key, bytes}` -> null once the pool has decoded it: the pack's file, read from the app's assets by Dart
 *   and handed over, since a Flutter asset is not a file Android's pool can open by itself. Kept as a file under the
 *   app's cache, named by the key.
 * - `play {key, volume, whileRecording}` -> whether it played: false where it was never primed, or where the phone
 *   says to keep quiet ([quiet]).
 * - `notifications {pack, events}` -> null: the pack and the notification events switched on, kept for the
 *   notifications posted with no Dart running (SoundChannels.kt).
 * - `narrate {key, bytes}` -> whether it plays: the walkthrough's voice for a page (lib/guide/narrator.dart; Matt,
 *   2026-10-27: "a friendly elevenlabs v4 voice explaining each section"), half a minute of speech, which is too long
 *   for the pool. Played on a `MediaPlayer` as speech on the media stream, so the volume keys turn it, in place of
 *   any page's voice still playing; false only in a call or while something records ([busy]). Not the ringer or Do
 *   Not Disturb: it is media the person opened the walkthrough to hear, which silent and Do Not Disturb let play (Matt,
 *   2026-10-28: "The welcome audio isn't playing now", his phone's Sleep mode having turned Do Not Disturb on).
 * - `hush` -> null: the voice stopped, as the guide turns a page or goes.
 *
 * The phone is respected here, where it can be read: the ringer on silent or vibrate, Do Not Disturb, a call, and an
 * open recording (the meeting's service, another app's microphone) each keep an interface sound from playing. The
 * recorder's own start and stop come with `whileRecording`, since the recording they mark is open as they play.
 */
class Sounds(private val context: Context) {
    private val main = Handler(Looper.getMainLooper())
    private val pool: SoundPool = SoundPool.Builder()
        .setMaxStreams(3)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build(),
        )
        .build()

    /** Each key's sound in the pool, and the primes waiting for theirs to be decoded. */
    private val loaded = mutableMapOf<String, Int>()
    private val waiting = mutableMapOf<Int, MutableList<MethodChannel.Result>>()
    private val ready = mutableSetOf<Int>()

    init {
        pool.setOnLoadCompleteListener { _, id, status ->
            main.post {
                if (status == 0) ready.add(id)
                for (result in waiting.remove(id) ?: mutableListOf()) {
                    if (status == 0) result.success(null) else result.error("sounds", "The sound could not be decoded.", null)
                }
            }
        }
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "prime" -> prime(call.argument<String>("key"), call.argument<ByteArray>("bytes"), result)
                    "notifications" -> {
                        // Which pack a write-up's and a reminder's notification sound comes from (SoundChannels.kt).
                        SoundChannels.choose(context, call.argument<String>("pack") ?: "off", call.argument<List<String>>("events") ?: emptyList())
                        result.success(null)
                    }
                    "narrate" -> result.success(narrate(call.argument<String>("key"), call.argument<ByteArray>("bytes")))
                    "hush" -> {
                        hush()
                        result.success(null)
                    }
                    "play" -> result.success(
                        play(call.argument<String>("key"), call.argument<Double>("volume") ?: 1.0, call.argument<Boolean>("whileRecording") == true),
                    )
                    else -> result.notImplemented()
                }
            } catch (failure: Exception) {
                result.error("sounds", failure.message ?: "The sound could not be played.", null)
            }
        }
    }

    private fun prime(key: String?, bytes: ByteArray?, result: MethodChannel.Result) {
        if (key == null || bytes == null || bytes.size > MOST_BYTES) throw IllegalArgumentException("No sound to keep.")
        val known = loaded[key]
        if (known != null && ready.contains(known)) return result.success(null)
        if (known != null) {
            waiting.getOrPut(known) { mutableListOf() }.add(result)
            return
        }
        // A file of the app's own cache, by the key with anything but a name's letters made an underscore: nothing a
        // caller says can name a file anywhere else.
        val folder = File(context.cacheDir, "sounds").apply { mkdirs() }
        val file = File(folder, key.replace(Regex("[^A-Za-z0-9._-]"), "_"))
        file.writeBytes(bytes)
        val id = pool.load(file.absolutePath, 1)
        loaded[key] = id
        waiting.getOrPut(id) { mutableListOf() }.add(result)
    }

    private fun play(key: String?, volume: Double, whileRecording: Boolean): Boolean {
        val id = loaded[key ?: return false] ?: return false
        if (!ready.contains(id) || quiet(whileRecording)) return false
        val level = volume.coerceIn(0.0, 1.0).toFloat()
        return pool.play(id, level, level, 1, 0, 1f) != 0
    }

    /** The walkthrough's voice playing now, if it is. */
    private var voice: MediaPlayer? = null

    private fun narrate(key: String?, bytes: ByteArray?): Boolean {
        if (key == null || bytes == null || bytes.size > MOST_VOICE_BYTES) throw IllegalArgumentException("No voice to play.")
        hush()
        if (busy()) return false
        val folder = File(context.cacheDir, "sounds").apply { mkdirs() }
        val file = File(folder, "voice-" + key.replace(Regex("[^A-Za-z0-9._-]"), "_"))
        if (!file.exists() || file.length() != bytes.size.toLong()) file.writeBytes(bytes)
        val player = MediaPlayer()
        voice = player
        player.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build(),
        )
        player.setDataSource(file.absolutePath)
        player.setOnPreparedListener { if (voice === it) it.start() }
        player.setOnCompletionListener { if (voice === it) hush() }
        player.setOnErrorListener { failed, _, _ ->
            if (voice === failed) hush()
            true
        }
        player.prepareAsync()
        return true
    }

    private fun hush() {
        val player = voice ?: return
        voice = null
        try {
            player.stop()
        } catch (_: IllegalStateException) {
            // Not started yet: there is nothing to stop, only to let go.
        }
        player.release()
    }

    /** Whether the phone asks for quiet now: silent or vibrate, Do Not Disturb, a call, or a recording open. */
    private fun quiet(whileRecording: Boolean): Boolean {
        val audio = context.getSystemService(AudioManager::class.java) ?: return false
        if (audio.ringerMode != AudioManager.RINGER_MODE_NORMAL) return true
        if (audio.mode != AudioManager.MODE_NORMAL) return true
        val notices = context.getSystemService(NotificationManager::class.java)
        if (notices != null) {
            val filter = notices.currentInterruptionFilter
            if (filter != NotificationManager.INTERRUPTION_FILTER_ALL && filter != NotificationManager.INTERRUPTION_FILTER_UNKNOWN) return true
        }
        if (!whileRecording && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && audio.activeRecordingConfigurations.isNotEmpty()) return true
        return false
    }

    /** A call, or a recording open (the meeting's service, another app's microphone): no voice over either. */
    private fun busy(): Boolean {
        val audio = context.getSystemService(AudioManager::class.java) ?: return false
        if (audio.mode != AudioManager.MODE_NORMAL) return true
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && audio.activeRecordingConfigurations.isNotEmpty()
    }

    /** The pool let go, with the activity. */
    fun release() {
        for (results in waiting.values) for (result in results) result.error("sounds", "Let go.", null)
        waiting.clear()
        hush()
        pool.release()
    }

    companion object {
        const val CHANNEL = "ghost_md/sounds"

        /** A sound is a second or so: anything near a megabyte is not one. */
        private const val MOST_BYTES = 1024 * 1024

        /** A page's voice is half a minute at 64 kbps, a quarter of a megabyte: four is far past any. */
        private const val MOST_VOICE_BYTES = 4 * 1024 * 1024
    }
}
