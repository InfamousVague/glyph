package com.mattssoftware.ghost_md

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentResolver
import android.content.Context
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build

/**
 * A notification's sound from the chosen pack (Settings › Sounds; Matt, 2026-10-27: "build ... the sounds settings";
 * docs/ideas/CUSTOMIZATION_AND_SOUNDS.md, "Delivering them"). Android ties a sound to its channel and never lets it be
 * changed once the channel exists, so a pack's sound is a channel of its own beside the plain one: a write-up or a
 * reminder is posted on the pack's channel while its switch in Settings › Sounds is on, and on the plain channel, with
 * the phone's own sound, while it is off or the pack is Off. Two so far, the write-up's and the reminder's; the meeting,
 * the team's comments and Lovart's picture have their files in every pack and wait for their notifications to be
 * moved the same way.
 *
 * What the app chose arrives on `ghost_md/sounds` as `notifications {pack, events: [ids]}` (lib/sounds/sounds.dart
 * `startSounds`) whenever it changes, and is kept here, since a reminder rings and a write-up lands with no Dart
 * running. A new sound for a pack is a new [VERSION]: the old channel is left as the person set it, and the next post
 * makes a fresh one with the new file.
 */
object SoundChannels {
    private const val PREFS = "ghost_sounds"
    private const val KEY_PACK = "pack"
    private const val KEY_EVENTS = "events"

    /** Raised whenever a pack's notification sounds are replaced, so phones make channels with the new files. */
    private const val VERSION = 1

    /** The write-up's and the reminder's files, by pack: `res/raw/sound_<pack>_<event>.ogg`. */
    private val sounds = mapOf(
        "ghostly" to mapOf(
            WRITEUP to R.raw.sound_ghostly_writeup_ready,
            REMINDER to R.raw.sound_ghostly_reminder_due,
        ),
    )

    const val WRITEUP = "writeup-ready"
    const val REMINDER = "reminder-due"

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Keeps what the app chose: the pack, and the events whose switch is on. */
    fun choose(context: Context, pack: String, events: List<String>) {
        prefs(context).edit().putString(KEY_PACK, pack).putStringSet(KEY_EVENTS, events.toSet()).apply()
    }

    /**
     * The channel a notification for [event] goes on: the pack's own, made here the first time, where the pack has a
     * sound for it and its switch is on; otherwise [plain], the channel it always went on. [name] and [importance] are
     * the plain channel's, so the pack's sits beside it in the phone's settings looking the same but for its sound.
     */
    fun channel(context: Context, event: String, plain: String, name: String, importance: Int): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return plain
        val held = prefs(context)
        val pack = held.getString(KEY_PACK, null) ?: return plain
        if (held.getStringSet(KEY_EVENTS, emptySet())?.contains(event) != true) return plain
        val raw = sounds[pack]?.get(event) ?: return plain
        val id = "${plain}_${pack}_v$VERSION"
        val manager = context.getSystemService(NotificationManager::class.java) ?: return plain
        if (manager.getNotificationChannel(id) == null) {
            val made = NotificationChannel(id, "$name (${pack.replaceFirstChar { it.uppercase() }} sound)", importance)
            val uri = Uri.parse("${ContentResolver.SCHEME_ANDROID_RESOURCE}://${context.packageName}/$raw")
            made.setSound(uri, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            manager.createNotificationChannel(made)
        }
        return id
    }
}
