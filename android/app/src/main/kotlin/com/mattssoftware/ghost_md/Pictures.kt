package com.mattssoftware.ghost_md

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipboardManager
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

/**
 * A picture chosen on the phone for a note (lib/core/phone_pictures.dart, the phone's half of `ghost_md/pictures`).
 * Ported from ../glyph's MainActivity (`pickImage`, `shrinkPicture`, its `REQUEST_PICTURE` result), whose page was
 * told of the picture by `window.__glyph.image(json)`; here the call's own answer carries it.
 *
 * - `pick` -> `{path}`, the picture shrunk and turned the right way up in `cacheDir/picked/`, for the core to adopt
 *   (`sync_put_file_path`, which moves it among the pictures); `{cancelled: true}` when none was chosen; or an error
 *   whose message is the sentence for the note.
 * - `clipboard` -> what is on the clipboard, for the note's own Paste (its press-and-hold menu; ../glyph's
 *   `readClipboard`): `{text}` for words, `{path}` for a picture (shrunk and turned the right way up into
 *   `cacheDir/picked/`, the way the chooser's is, for the core to adopt), `{error}` when a picture could not be
 *   read, `{}` when there is nothing. Since Android 10 the clipboard only answers an app that holds focus, and a
 *   refusal reads as nothing at all.
 *
 * Android's own chooser ("Choose a picture"), which asks for no permission: the picture is read through the
 * address the chooser hands back, once, and the cache copy is the only thing this ever writes. Decoded at a sample
 * size that keeps memory sane, turned per its EXIF, its long side capped at 1600 px, written as a JPEG at 85: a
 * photo straight off the camera is several times what a note ever draws. A picture with no background is laid on
 * white paper first, as the page's own shrink lays a pasted one (core/imageShrink.ts): ../glyph's activity did not,
 * and a transparent screenshot came out black as a JPEG.
 */
class Pictures(private val activity: Activity) {
  private var asking: MethodChannel.Result? = null

  fun register(messenger: BinaryMessenger) {
    MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "pick" -> pick(result)
        "clipboard" -> clipboard(result)
        else -> result.notImplemented()
      }
    }
  }

  private fun pick(result: MethodChannel.Result) {
    // One picker at a time: a second ask while the first is up is answered as none chosen.
    asking?.success(mapOf("cancelled" to true))
    asking = result
    val intent = Intent(Intent.ACTION_GET_CONTENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE)
    try {
      activity.startActivityForResult(Intent.createChooser(intent, "Choose a picture"), REQUEST)
    } catch (error: ActivityNotFoundException) {
      asking = null
      result.error("none", "This phone has no picture picker.", null)
    }
  }

  /**
   * The first thing on the clipboard. The call arrives on the UI thread, where the clipboard belongs; a picture is
   * shrunk off it.
   */
  private fun clipboard(result: MethodChannel.Result) {
    val clipboard = activity.getSystemService(Activity.CLIPBOARD_SERVICE) as? ClipboardManager
    val item = clipboard?.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)
    if (item == null) {
      result.success(emptyMap<String, Any>())
      return
    }
    val uri = item.uri
    if (uri != null && (activity.contentResolver.getType(uri) ?: "").startsWith("image/")) {
      Thread {
        val path = try {
          shrink(uri).absolutePath
        } catch (error: Exception) {
          Log.w(TAG, "clipboard picture unreadable", error)
          null
        }
        activity.runOnUiThread {
          result.success(if (path != null) mapOf("path" to path) else mapOf("error" to "That picture couldn't be read from the clipboard."))
        }
      }.start()
      return
    }
    val text = item.coerceToText(activity)?.toString().orEmpty()
    if (text.isEmpty()) Log.i(TAG, "clipboard read came back empty (uri=${uri != null})")
    result.success(if (text.isEmpty()) emptyMap<String, Any>() else mapOf("text" to text))
  }

  /** The chooser's answer; whether the request was this one. The shrink is off the main thread. */
  fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    if (requestCode != REQUEST) return false
    val result = asking ?: return true
    asking = null
    val uri = data?.data
    if (resultCode != Activity.RESULT_OK || uri == null) {
      result.success(mapOf("cancelled" to true))
      return true
    }
    Thread {
      val path = try {
        shrink(uri).absolutePath
      } catch (error: Exception) {
        Log.w(TAG, "picture not read", error)
        null
      }
      activity.runOnUiThread {
        if (path != null) result.success(mapOf("path" to path)) else result.error("unread", "That picture could not be read.", null)
      }
    }.start()
    return true
  }

  /** Decodes `uri` at a sample size that keeps memory sane, rotates it per EXIF, caps the long side, writes a JPEG. */
  private fun shrink(uri: Uri): File {
    val resolver = activity.contentResolver
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
    val longest = maxOf(bounds.outWidth, bounds.outHeight).coerceAtLeast(1)
    var sample = 1
    while (longest / (sample * 2) >= MAX_PX) sample *= 2
    val decoded = resolver.openInputStream(uri)?.use {
      BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
    } ?: throw IllegalStateException("decode failed")
    val rotation = resolver.openInputStream(uri)?.use { stream ->
      when (ExifInterface(stream).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
        ExifInterface.ORIENTATION_ROTATE_90 -> 90f
        ExifInterface.ORIENTATION_ROTATE_180 -> 180f
        ExifInterface.ORIENTATION_ROTATE_270 -> 270f
        else -> 0f
      }
    } ?: 0f
    val scale = minOf(1f, MAX_PX.toFloat() / maxOf(decoded.width, decoded.height))
    val matrix = Matrix().apply {
      if (scale < 1f) postScale(scale, scale)
      if (rotation != 0f) postRotate(rotation)
    }
    val upright = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
    // Paper under a transparent picture, so a screenshot with no background does not turn black as a JPEG.
    val flat = if (upright.hasAlpha()) {
      Bitmap.createBitmap(upright.width, upright.height, Bitmap.Config.ARGB_8888).also { paper ->
        android.graphics.Canvas(paper).apply {
          drawColor(android.graphics.Color.WHITE)
          drawBitmap(upright, 0f, 0f, null)
        }
      }
    } else {
      upright
    }
    val dir = File(activity.cacheDir, "picked").apply { mkdirs() }
    val out = File(dir, "${UUID.randomUUID()}.jpg")
    FileOutputStream(out).use { flat.compress(Bitmap.CompressFormat.JPEG, 85, it) }
    return out
  }

  companion object {
    const val CHANNEL = "ghost_md/pictures"
    private const val TAG = "GhostPictures"

    /** The request code the activity's result arrives under: ../glyph's own for a picked picture. */
    const val REQUEST = 4102

    /** The long side a kept picture is capped at. */
    private const val MAX_PX = 1600
  }
}
