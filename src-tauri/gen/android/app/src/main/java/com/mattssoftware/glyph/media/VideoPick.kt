package com.mattssoftware.glyph.media

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.os.ext.SdkExtensions
import android.graphics.Bitmap
import android.graphics.Matrix
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.StatFs
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID

/**
 * A film for a note (native generation 21; docs/DESIGN.md §141, the + beside the line's "A video").
 *
 * Matt asked for a menu that adds "geotag cards images videos and more". The film is picked with the Photo Picker
 * (`MediaStore.ACTION_PICK_IMAGES` for videos only, on Android 13 and later and on 11 and 12 with the picker's
 * module), or the phone's chooser for videos where there is no Photo Picker. Neither asks for a permission: the picker
 * hands over one film the person chose, so the manifest declares no READ_MEDIA_*, and the store's "not asked" stays
 * true.
 *
 * The film is copied as it was filmed, off the UI thread, in 1 MB blocks, into `cacheDir/picked/<uuid>.<ext>`, with
 * 500 MB of the phone kept free: a gigabyte's film is not shrunk, and a phone with no room says so before a byte is
 * copied. A film only in someone's cloud is downloaded by its provider as it is read. Then its length, size and turn
 * are read off the copy, and its poster made from a frame near the start (a second in, or half way through a shorter
 * one), turned upright, shrunk to 1600 px and written as a JPEG beside it, as a picked picture is. The poster is made
 * here and not in the page: a frame drawn from the app's own `vid` scheme would taint the page's canvas. Nothing is
 * read from the file but that: no place it was filmed, no date, no device.
 *
 * The page hears `window.__glyph.video(json)`, its own event, never the picture's (a pick of each at once must not
 * answer the other): `{ path, poster, ms, width, height }`, `{ cancelled: true }` or `{ error }`. Rust then keeps both
 * (videos.rs `save_video`) or, for an answer the page was not waiting for, throws them away (`discard_picked`), and
 * what waits in `picked/` for more than an hour goes at the next launch. RUST TWIN: videos.rs, whose EXTENSIONS are
 * this file's, and paths.rs, whose `picked` this writes to; tests on both sides read the other.
 */
object VideoPick {
  /**
   * The request code the activity answers in onActivityResult: 4101 to 4104 are the activity's own (notifications, a
   * picked picture, meetings' notifications and microphone) and 4105 is location's (location/LocationAccess.kt).
   */
  const val REQUEST = 4106
  private const val TAG = "GlyphVideo"

  /** A film's type, and the extension it is kept under. RUST TWIN: videos.rs `EXTENSIONS`, read by a test there. */
  val EXTENSIONS = mapOf("video/mp4" to "mp4", "video/x-m4v" to "m4v", "video/quicktime" to "mov", "video/webm" to "webm")

  /** How much of the phone is kept free after a film is copied: the notes and everything else still need room. */
  const val SPARE_BYTES = 500L * 1024 * 1024
  private const val BLOCK = 1024 * 1024
  /** How many blocks are copied between looks at the room left, for a film whose size was not said. */
  private const val LOOK_EVERY = 64
  /** A poster's long side, as a picked picture's (MainActivity PICTURE_MAX_PX). */
  private const val POSTER_MAX_PX = 1600

  const val NO_ROOM = "There isn’t room on this phone for that video."
  const val UNREADABLE = "This video can’t be read."
  const val NO_PICKER = "This phone has no video picker."

  /** The film was taken up to no more room than the phone keeps free. */
  private class NoRoom : IOException()

  /** Whether this phone has the Photo Picker itself: Android 13 and later, or 11 and 12 with its module. */
  private fun photoPicker(): Boolean =
    Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ||
      (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && SdkExtensions.getExtensionVersion(Build.VERSION_CODES.R) >= 2)

  private fun pickerIntent(): Intent =
    if (photoPicker()) Intent(MediaStore.ACTION_PICK_IMAGES).setType("video/*")
    else Intent(Intent.ACTION_GET_CONTENT).setType("video/*").addCategory(Intent.CATEGORY_OPENABLE)

  /**
   * Opens the picker from the page's call, which comes on the bridge's thread: "started", and the film arrives later
   * through `answered`. A phone with no picker at all is told to the page the same way, as `{ error }`, since the
   * activity starts it on the UI thread after this has answered.
   */
  fun start(activity: Activity, tell: (String) -> Unit): String {
    activity.runOnUiThread {
      try {
        activity.startActivityForResult(pickerIntent(), REQUEST)
      } catch (error: ActivityNotFoundException) {
        tell(failed(NO_PICKER))
      }
    }
    return "started"
  }

  /**
   * The picker's answer: a film copied, read and given its poster on a thread of its own, and `tell` given the JSON the
   * page reads. Answers whether the request was this one.
   */
  fun answered(activity: Activity, requestCode: Int, resultCode: Int, data: Intent?, tell: (String) -> Unit): Boolean {
    if (requestCode != REQUEST) return false
    val uri = data?.data
    if (resultCode != Activity.RESULT_OK || uri == null) {
      tell(cancelled())
      return true
    }
    val context = activity.applicationContext
    Thread({ tell(keep(context, uri)) }, "glyph-video-pick").start()
    return true
  }

  /** The film at `uri` copied into picked/ with its poster beside it, as the answer's JSON. */
  private fun keep(context: Context, uri: Uri): String {
    val resolver = context.contentResolver
    val cacheDir = context.cacheDir
    // Where `save_video` adopts from: `PICKED` in src-tauri/src/paths.rs. Rename both together.
    val dir = File(cacheDir, "picked").apply { mkdirs() }
    val extension = extensionFor(resolver.getType(uri), nameOf(resolver, uri)) ?: return failed(UNREADABLE)
    val room = { StatFs(dir.path).availableBytes }
    if (!fits(sizeOf(resolver, uri), room())) return failed(NO_ROOM)
    val id = UUID.randomUUID().toString()
    val film = File(dir, "$id.$extension")
    val poster = File(dir, "$id.jpg")
    try {
      val input = resolver.openInputStream(uri) ?: return failed(UNREADABLE)
      input.use { from -> FileOutputStream(film).use { to -> copy(from, to, room) } }
    } catch (full: NoRoom) {
      film.delete()
      return failed(NO_ROOM)
    } catch (error: Exception) {
      Log.w(TAG, "video not copied", error)
      film.delete()
      return failed(UNREADABLE)
    }
    val retriever = MediaMetadataRetriever()
    return try {
      retriever.setDataSource(film.path)
      val number = { key: Int -> retriever.extractMetadata(key)?.toLongOrNull() ?: 0L }
      val ms = number(MediaMetadataRetriever.METADATA_KEY_DURATION)
      val width = number(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH).toInt()
      val height = number(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT).toInt()
      val rotation = number(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION).toInt()
      val frame = if (ms > 0) retriever.getFrameAtTime(frameAtUs(ms), MediaMetadataRetriever.OPTION_CLOSEST_SYNC) else null
      if (frame == null) {
        film.delete()
        return failed(UNREADABLE)
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
      picked(film.absolutePath, poster.absolutePath, ms, shownWidth, shownHeight)
    } catch (error: Exception) {
      Log.w(TAG, "video not read", error)
      film.delete()
      poster.delete()
      failed(UNREADABLE)
    } finally {
      try {
        retriever.release()
      } catch (_: Exception) {
        // Released or never set up: nothing to let go of.
      }
    }
  }

  /** Copies in 1 MB blocks, looking at the room left every so often, and stops before the phone is full. */
  private fun copy(from: InputStream, to: OutputStream, room: () -> Long) {
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

  // ---- the rules, pure, for the tests (VideoPickTest) --------------------------------------------------------

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
   * the frame: a quarter turn is made only when the frame still lies the way the film is stored. A half turn cannot be
   * told from the frame's shape and is left to the platform, which turns every angle alike.
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

  /** A film picked and copied: where it is, its poster, its length in ms, and its size as it is watched. */
  fun picked(path: String, poster: String, ms: Long, width: Int, height: Int): String =
    json("path" to path, "poster" to poster, "ms" to ms, "width" to width, "height" to height)

  /** The picker closed with nothing chosen. */
  fun cancelled(): String = json("cancelled" to true)

  /** Why no film came, in the words the page shows. */
  fun failed(message: String): String = json("error" to message)

  /** A flat JSON object of strings, numbers and booleans, written here so the tests need no Android to read one. */
  fun json(vararg fields: Pair<String, Any>): String =
    fields.joinToString(",", "{", "}") { (key, value) ->
      "${quote(key)}:" +
        when (value) {
          is String -> quote(value)
          is Number, is Boolean -> value.toString()
          else -> quote(value.toString())
        }
    }

  private fun quote(text: String): String =
    buildString {
      append('"')
      for (c in text) {
        when {
          c == '"' -> append("\\\"")
          c == '\\' -> append("\\\\")
          c < ' ' -> append(String.format("\\u%04x", c.code))
          else -> append(c)
        }
      }
      append('"')
    }
}
