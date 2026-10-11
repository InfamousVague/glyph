package com.mattssoftware.ghost_md

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Matrix
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.StatFs
import android.os.ext.SdkExtensions
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID

/**
 * A film chosen on the phone for a note (lib/core/phone_films.dart, the phone's half of `ghost_md/films`). Ported
 * from the Tauri app's media/VideoPick.kt, whose page was told of the film by `window.__glyph.video(json)`; here the
 * call's own answer carries it, and the one thing said before the answer is a call the other way.
 *
 * - `pick` -> `{path, poster, ms, width, height}`: the film copied as it was filmed into `cacheDir/picked/` with
 *   its poster beside it, for the core to adopt (`save_video`) or throw away (`discard_picked`);
 *   `{cancelled: true}` when none was chosen; or an error whose message is the sentence for the note.
 * - `copying`, said TO the app once a film is chosen and before its copy starts: the app says it is adding the
 *   film only then, and not while the picker is still up.
 *
 * The Photo Picker (`MediaStore.ACTION_PICK_IMAGES` for videos only, on Android 13 and later and on 11 and 12 with
 * the picker's module), or the phone's chooser for videos where there is none. Neither asks for a permission: the
 * picker hands over one film the person chose, so the manifest declares no READ_MEDIA_*.
 *
 * The film is copied off the UI thread, in 1 MB blocks, with 500 MB of the phone kept free: a gigabyte's film is
 * not shrunk, and a phone with no room says so before a byte is copied. Then its length, size and turn are read
 * off the copy, and its poster made from a frame near the start (a second in, or half way through a shorter one),
 * turned upright, shrunk to 1600 px and written as a JPEG beside it, as a picked picture is. Nothing is read from
 * the file but that: no place it was filmed, no date, no device. Whatever goes wrong on the copying thread is
 * answered, never thrown.
 *
 * RUST TWIN: native/src/kept/videos.rs, whose EXTENSIONS are this file's, and native/src/paths.rs, whose `picked`
 * this writes to. The rules at the foot are the Tauri app's own, line for line.
 */
class Films(private val activity: Activity) {
  private var asking: MethodChannel.Result? = null
  private var channel: MethodChannel? = null

  fun register(messenger: BinaryMessenger) {
    channel = MethodChannel(messenger, CHANNEL).also {
      it.setMethodCallHandler { call, result ->
        when (call.method) {
          "pick" -> pick(result)
          else -> result.notImplemented()
        }
      }
    }
  }

  private fun pick(result: MethodChannel.Result) {
    // One pick at a time: the app refuses a second while the first is being copied, and one asked for while the
    // picker is still up is answered as none chosen.
    if (asking != null) {
      result.success(mapOf("cancelled" to true))
      return
    }
    asking = result
    try {
      activity.startActivityForResult(pickerIntent(), REQUEST)
    } catch (error: ActivityNotFoundException) {
      asking = null
      result.error("none", NO_PICKER, null)
    } catch (error: Exception) {
      // A picker that refuses to be started (a SecurityException from a locked-down phone) is no picker here either.
      Log.w(TAG, "video picker not started", error)
      asking = null
      result.error("none", NO_PICKER, null)
    }
  }

  /** The picker's answer; whether the request was this one. The copy and the poster are off the main thread. */
  fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    if (requestCode != REQUEST) return false
    val result = asking ?: return true
    // The Photo Picker answers with the film's address; a chooser's provider may answer with it in a clip alone.
    val uri = data?.data ?: data?.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri
    if (resultCode != Activity.RESULT_OK || uri == null) {
      asking = null
      result.success(mapOf("cancelled" to true))
      return true
    }
    channel?.invokeMethod("copying", null)
    val context = activity.applicationContext
    Thread({
      val answer = keepAnswered(context, uri)
      activity.runOnUiThread {
        asking = null
        when (answer) {
          is Kept.Film -> result.success(mapOf("path" to answer.path, "poster" to answer.poster, "ms" to answer.ms, "width" to answer.width, "height" to answer.height))
          is Kept.Failed -> result.error("unkept", answer.message, null)
        }
      }
    }, "ghost-video-pick").start()
    return true
  }

  /** What a copy came to: the film with its poster, or the sentence for the note. */
  private sealed class Kept {
    data class Film(val path: String, val poster: String, val ms: Long, val width: Int, val height: Int) : Kept()
    data class Failed(val message: String) : Kept()
  }

  /** `keep`, with anything it throws answered as a film that could not be read rather than let loose on its thread. */
  private fun keepAnswered(context: Context, uri: Uri): Kept =
    try {
      keep(context, uri)
    } catch (error: Throwable) {
      Log.w(TAG, "video not kept", error)
      Kept.Failed(UNREADABLE)
    }

  /** The film at `uri` copied into picked/ with its poster beside it. */
  private fun keep(context: Context, uri: Uri): Kept {
    val resolver = context.contentResolver
    // Where `save_video` adopts from: `PICKED` in native/src/paths.rs. Rename both together.
    val dir = File(context.cacheDir, "picked").apply { mkdirs() }
    val extension = extensionFor(resolver.getType(uri), nameOf(resolver, uri)) ?: return Kept.Failed(UNSUPPORTED)
    val room = { StatFs(dir.path).availableBytes }
    if (!fits(sizeOf(resolver, uri), room())) return Kept.Failed(NO_ROOM)
    val id = UUID.randomUUID().toString()
    val film = File(dir, "$id.$extension")
    val poster = File(dir, "$id.jpg")
    try {
      val input = resolver.openInputStream(uri) ?: return Kept.Failed(UNREADABLE)
      input.use { from -> FileOutputStream(film).use { to -> copy(from, to, room) } }
    } catch (full: NoRoom) {
      film.delete()
      return Kept.Failed(NO_ROOM)
    } catch (error: Throwable) {
      Log.w(TAG, "video not copied", error)
      film.delete()
      return Kept.Failed(UNREADABLE)
    }
    val retriever = MediaMetadataRetriever()
    return try {
      retriever.setDataSource(film.path)
      val number = { key: Int -> retriever.extractMetadata(key)?.toLongOrNull() ?: 0L }
      val ms = number(MediaMetadataRetriever.METADATA_KEY_DURATION)
      val width = number(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH).toInt()
      val height = number(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT).toInt()
      val rotation = number(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION).toInt()
      val frame = if (ms > 0) frameOf(retriever, frameAtUs(ms)) else null
      if (frame == null) {
        film.delete()
        return Kept.Failed(UNREADABLE)
      }
      val turn = turnBy(rotation, frame.width, frame.height, width, height)
      val scale = minOf(1f, POSTER_MAX_PX.toFloat() / maxOf(frame.width, frame.height))
      val matrix = Matrix().apply {
        if (scale < 1f) postScale(scale, scale)
        if (turn != 0) postRotate(turn.toFloat())
      }
      val upright = Bitmap.createBitmap(frame, 0, 0, frame.width, frame.height, matrix, true)
      FileOutputStream(poster).use { upright.compress(Bitmap.CompressFormat.JPEG, 85, it) }
      val (shownWidth, shownHeight) = shown(rotation, width, height, upright.width, upright.height)
      Kept.Film(film.absolutePath, poster.absolutePath, ms, shownWidth, shownHeight)
    } catch (error: Throwable) {
      // An 8K frame made whole on a phone short of memory is an Error, not an Exception: the copies go all the same.
      Log.w(TAG, "video not read", error)
      film.delete()
      poster.delete()
      Kept.Failed(UNREADABLE)
    } finally {
      try {
        retriever.release()
      } catch (_: Exception) {
        // Released or never set up: nothing to let go of.
      }
    }
  }

  /**
   * The poster's frame, made no bigger than the poster, where the phone can (Android 8.1 and later): an 8K film's
   * frame made whole first is about 130 MB, only to be shrunk to 1600 px straight after.
   */
  private fun frameOf(retriever: MediaMetadataRetriever, us: Long): Bitmap? =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
      retriever.getScaledFrameAtTime(us, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, POSTER_MAX_PX, POSTER_MAX_PX)
    } else {
      retriever.getFrameAtTime(us, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
    }

  private fun nameOf(resolver: ContentResolver, uri: Uri): String? =
    try {
      resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { if (it.moveToFirst()) it.getString(0) else null }
    } catch (_: Exception) {
      null
    }

  /** The film's size as its provider says it, or -1 when it will not. */
  private fun sizeOf(resolver: ContentResolver, uri: Uri): Long =
    try {
      resolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use {
        if (it.moveToFirst() && !it.isNull(0)) it.getLong(0) else -1L
      } ?: -1L
    } catch (_: Exception) {
      -1L
    }

  /** The film was taken up to no more room than the phone keeps free. */
  internal class NoRoom : IOException()

  companion object {
    const val CHANNEL = "ghost_md/films"
    private const val TAG = "GhostFilms"

    /** The request code the activity's result arrives under: the Tauri app's own for a picked film. */
    const val REQUEST = 4106

    /** A film's type, and the extension it is kept under. RUST TWIN: kept/videos.rs `EXTENSIONS`. */
    val EXTENSIONS = mapOf("video/mp4" to "mp4", "video/x-m4v" to "m4v", "video/quicktime" to "mov", "video/webm" to "webm")

    /** How much of the phone is kept free after a film is copied: the notes and everything else still need room. */
    const val SPARE_BYTES = 500L * 1024 * 1024
    private const val BLOCK = 1024 * 1024

    /** How many blocks are copied between looks at the room left, for a film whose size was not said. */
    private const val LOOK_EVERY = 64

    /** A poster's long side, as a picked picture's (Pictures.kt MAX_PX). */
    private const val POSTER_MAX_PX = 1600

    const val NO_ROOM = "There isn’t room on this phone for that video."
    const val UNREADABLE = "This video can’t be read."
    const val NO_PICKER = "This phone has no video picker."

    /** A film of a kind that is not kept (3GP, MKV): not a damaged one, so not said as one. */
    const val UNSUPPORTED = "This kind of video can’t be added. MP4, MOV and WebM can."

    /** Whether this phone has the Photo Picker itself: Android 13 and later, or 11 and 12 with its module. */
    private fun photoPicker(): Boolean =
      Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ||
        (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && SdkExtensions.getExtensionVersion(Build.VERSION_CODES.R) >= 2)

    private fun pickerIntent(): Intent =
      if (photoPicker()) Intent(MediaStore.ACTION_PICK_IMAGES).setType("video/*")
      else Intent(Intent.ACTION_GET_CONTENT).setType("video/*").addCategory(Intent.CATEGORY_OPENABLE)

    /** Copies in 1 MB blocks, looking at the room left every so often, and stops before the phone is full. */
    internal fun copy(from: InputStream, to: OutputStream, room: () -> Long) {
      val block = ByteArray(BLOCK)
      var blocks = 0
      while (true) {
        val read = from.read(block)
        if (read < 0) return
        to.write(block, 0, read)
        blocks += 1
        if (blocks % LOOK_EVERY == 0 && room() < SPARE_BYTES) throw NoRoom()
      }
    }

    // ---- the rules, pure (the Tauri app's VideoPickTest holds the originals) ---------------------------------------

    /** The extension a film is kept under: its type's, or its name's where the type says no better; null for any other. */
    fun extensionFor(type: String?, name: String?): String? {
      EXTENSIONS[type?.lowercase()]?.let { return it }
      val fromName = name?.substringAfterLast('.', "")?.lowercase()
      return fromName?.takeIf { it in EXTENSIONS.values }
    }

    /** Whether a film of `size` bytes (-1 when not said) leaves the phone its spare room, of `available`. */
    fun fits(size: Long, available: Long): Boolean = if (size < 0) available >= SPARE_BYTES else size + SPARE_BYTES <= available

    /** Where the poster's frame is taken, in microseconds: a second in, or half way through a film shorter than two. */
    fun frameAtUs(ms: Long): Long = minOf(1000L, ms / 2) * 1000L

    /**
     * How far to turn a frame to stand it upright. The film says how it is to be turned (`rotation`, of its stored
     * `width` by `height`); whether the frame arrives already turned is the platform's to decide, so it is read from
     * the frame: a quarter turn is made only when the frame still lies the way the film is stored. A half turn cannot
     * be told from the frame's shape and is left to the platform, which turns every angle alike.
     */
    fun turnBy(rotation: Int, frameWidth: Int, frameHeight: Int, width: Int, height: Int): Int {
      val quarter = rotation == 90 || rotation == 270
      if (!quarter || width == height || width <= 0 || height <= 0) return 0
      val storedWide = width > height
      val frameWide = frameWidth > frameHeight
      return if (frameWide == storedWide) rotation else 0
    }

    /** The film's width and height as it is watched: as stored, or turned a quarter; the poster's where it says nothing. */
    fun shown(rotation: Int, width: Int, height: Int, posterWidth: Int, posterHeight: Int): Pair<Int, Int> {
      if (width <= 0 || height <= 0) return posterWidth to posterHeight
      return if (rotation == 90 || rotation == 270) height to width else width to height
    }
  }
}
