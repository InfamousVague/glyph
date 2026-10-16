package com.mattssoftware.ghost_md

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.os.Process
import android.provider.OpenableColumns
import android.util.Log
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.common.moduleinstall.ModuleInstallRequest
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Documents in notes (lib/files/phone_documents.dart, the phone's half of `ghost_md/documents`): any file chosen,
 * a document scanned, the words read in a picture or a PDF, a PDF's pages drawn, and a file handed to another app.
 *
 * - `pick` -> `{path, name, bytes}`: Android's own document picker (ACTION_OPEN_DOCUMENT, any type), which asks for
 *   no permission; the file chosen is copied once into `cacheDir/picked/` for the app to keep, in 1 MB blocks off
 *   the UI thread. `{cancelled: true}` when none was chosen.
 * - `canScan`, `scan` -> `{pdf, pages, count}`: Google's document scanner (ML Kit, play-services-mlkit-document-scanner),
 *   its own screen with the edges found, cropping and clean-up; the app never holds the camera and asks for no
 *   permission. What it made (one PDF of every page, and each page as a JPEG) is copied into `cacheDir/picked/`.
 *   It needs Google Play services, which delivers the scanner's screen the first time it is asked for.
 * - `read {path, pdf, most}` -> `{pages}`: the words in a picture, or in each of a PDF's first `most` pages, read on
 *   the phone by ML Kit's Latin text recognition (play-services-mlkit-text-recognition): its model is fetched once
 *   by Google Play services (asked for here the first time, `readerReady`), and kept, so after that it reads with
 *   no connection; nothing read leaves the phone. A PDF page's own words are taken where Android 15 can give them,
 *   and the page is drawn and read where it has none (a scan). On its own low-priority thread.
 * - `readerReady` -> whether that model is on the phone yet.
 * - `pdfOpen`, `pdfPage`, `pdfText`, `pdfFind`, `pdfClose`: a PDF drawn by Android's own PdfRenderer (PDFium, in
 *   the system), a page at a time on asking, as RGBA pixels; its words and where a word stands from Android 15.
 * - `openWith`, `share {path, name}`: the file copied into `cacheDir/open/<id>/<name>`, so the other app sees its
 *   real name, and handed out through this app's FileProvider for that folder only (AttachmentFiles below).
 * - `saving` -> whether Battery saver is on.
 */
class Documents(private val activity: Activity) {
  private var picking: MethodChannel.Result? = null
  private var scanning: MethodChannel.Result? = null

  /** The PDFs open to draw, by id, each used on [drawing] only: a PdfRenderer is for one thread at a time. */
  private val open = HashMap<Int, PdfRenderer>()
  private var nextId = 1
  private val drawing: ExecutorService = Executors.newSingleThreadExecutor()

  /** The reading of words, behind whatever the person is doing. */
  private val reading: ExecutorService = Executors.newSingleThreadExecutor { work ->
    Thread({
      Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
      work.run()
    }, "ghost-read")
  }
  private val recognizer by lazy { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }

  fun register(messenger: BinaryMessenger) {
    MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "pick" -> pick(result)
        "canScan" -> result.success(canScan())
        "scan" -> scan(result)
        "read" -> off(reading, result) { read(call) }
        "readerReady" -> off(reading, result) { readerReady() }
        "pdfOpen" -> off(drawing, result) { pdfOpen(call.argument<String>("path")) }
        "pdfPage" -> off(drawing, result) { pdfPage(call) }
        "pdfText" -> off(drawing, result) { pdfText(call) }
        "pdfFind" -> off(drawing, result) { pdfFind(call) }
        "pdfClose" -> off(drawing, result) { pdfClose(call.argument<Int>("id")) }
        "openWith" -> hand(call, result, share = false)
        "share" -> hand(call, result, share = true)
        "saving" -> result.success((activity.getSystemService(Activity.POWER_SERVICE) as? PowerManager)?.isPowerSaveMode == true)
        else -> result.notImplemented()
      }
    }
  }

  /** Work on [executor], its answer (or its sentence) back on the UI thread. */
  private fun off(executor: ExecutorService, result: MethodChannel.Result, work: () -> Any?) {
    executor.execute {
      val answer = try {
        Result.success(work())
      } catch (error: Throwable) {
        Log.w(TAG, "documents work failed", error)
        Result.failure(error)
      }
      activity.runOnUiThread {
        answer.fold(
          onSuccess = { result.success(it) },
          onFailure = { result.error("documents", (it as? Said)?.message ?: "That didn't work.", null) },
        )
      }
    }
  }

  /** A failure whose message is the sentence a person reads. */
  private class Said(message: String) : Exception(message)

  // ---- choosing a file ----------------------------------------------------------------------------------------

  private fun pick(result: MethodChannel.Result) {
    picking?.success(mapOf("cancelled" to true))
    picking = result
    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*")
    try {
      activity.startActivityForResult(intent, REQUEST_PICK)
    } catch (error: ActivityNotFoundException) {
      picking = null
      result.error("none", "This phone has no file picker.", null)
    }
  }

  private fun picked(uri: Uri, result: MethodChannel.Result) {
    Thread {
      val answer = try {
        val resolver = activity.contentResolver
        var name = "File"
        var size = -1L
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { row ->
          if (row.moveToFirst()) {
            row.getString(0)?.takeIf { it.isNotBlank() }?.let { name = it }
            if (!row.isNull(1)) size = row.getLong(1)
          }
        }
        if (size > MAX_BYTES) throw Said("That file is too large to add.")
        val out = File(File(activity.cacheDir, "picked").apply { mkdirs() }, "${UUID.randomUUID()}.part")
        var copied = 0L
        try {
          resolver.openInputStream(uri)?.use { input ->
            FileOutputStream(out).use { output ->
              val block = ByteArray(1 shl 20)
              while (true) {
                val read = input.read(block)
                if (read < 0) break
                copied += read
                if (copied > MAX_BYTES) throw Said("That file is too large to add.")
                output.write(block, 0, read)
              }
            }
          } ?: throw Said("That file could not be read.")
        } catch (error: Throwable) {
          out.delete()
          throw error
        }
        Result.success(mapOf("path" to out.absolutePath, "name" to name, "bytes" to copied))
      } catch (error: Throwable) {
        Log.w(TAG, "file not read", error)
        Result.failure<Map<String, Any>>(error)
      }
      activity.runOnUiThread {
        answer.fold(
          onSuccess = { result.success(it) },
          onFailure = { result.error("unread", (it as? Said)?.message ?: "That file could not be read.", null) },
        )
      }
    }.start()
  }

  // ---- scanning -----------------------------------------------------------------------------------------------

  private fun canScan(): Boolean = try {
    GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(activity) == ConnectionResult.SUCCESS
  } catch (error: Throwable) {
    false
  }

  private fun scan(result: MethodChannel.Result) {
    scanning?.success(mapOf("cancelled" to true))
    scanning = result
    val options = GmsDocumentScannerOptions.Builder()
      .setGalleryImportAllowed(true)
      .setPageLimit(PAGE_LIMIT)
      .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG, GmsDocumentScannerOptions.RESULT_FORMAT_PDF)
      .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
      .build()
    try {
      GmsDocumentScanning.getClient(options).getStartScanIntent(activity)
        .addOnSuccessListener { sender ->
          try {
            activity.startIntentSenderForResult(sender, REQUEST_SCAN, null, 0, 0, 0)
          } catch (error: Throwable) {
            Log.w(TAG, "scanner not started", error)
            scanning = null
            result.error("scanner", "The scanner did not open.", null)
          }
        }
        .addOnFailureListener { error ->
          Log.w(TAG, "scanner unavailable", error)
          scanning = null
          result.error("scanner", "This phone can't open Google's document scanner. It needs Google Play services.", null)
        }
    } catch (error: Throwable) {
      Log.w(TAG, "scanner unavailable", error)
      scanning = null
      result.error("scanner", "This phone can't open Google's document scanner. It needs Google Play services.", null)
    }
  }

  private fun scanned(data: Intent?, result: MethodChannel.Result) {
    val made = GmsDocumentScanningResult.fromActivityResultIntent(data)
    val pdf = made?.pdf?.uri
    if (made == null || pdf == null) {
      result.success(mapOf("cancelled" to true))
      return
    }
    val pages = made.pages?.map { it.imageUri } ?: emptyList()
    Thread {
      val answer = try {
        val dir = File(activity.cacheDir, "picked").apply { mkdirs() }
        val id = UUID.randomUUID().toString()
        val copy = { uri: Uri, to: File ->
          activity.contentResolver.openInputStream(uri)?.use { input -> FileOutputStream(to).use { input.copyTo(it, 1 shl 20) } } ?: throw Said("The scan could not be kept.")
          to.absolutePath
        }
        val pdfPath = copy(pdf, File(dir, "$id.pdf"))
        val pagePaths = pages.mapIndexed { index, uri -> copy(uri, File(dir, "$id-${index + 1}.jpg")) }
        Result.success(mapOf("pdf" to pdfPath, "pages" to pagePaths, "count" to (made.pdf?.pageCount ?: pagePaths.size)))
      } catch (error: Throwable) {
        Log.w(TAG, "scan not kept", error)
        Result.failure<Map<String, Any>>(error)
      }
      activity.runOnUiThread {
        answer.fold(
          onSuccess = { result.success(it) },
          onFailure = { result.error("scan", (it as? Said)?.message ?: "The scan could not be kept.", null) },
        )
      }
    }.start()
  }

  /** The pickers' answers; whether the request was one of these. */
  fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    when (requestCode) {
      REQUEST_PICK -> {
        val result = picking ?: return true
        picking = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) result.success(mapOf("cancelled" to true)) else picked(uri, result)
        return true
      }
      REQUEST_SCAN -> {
        val result = scanning ?: return true
        scanning = null
        if (resultCode != Activity.RESULT_OK) result.success(mapOf("cancelled" to true)) else scanned(data, result)
        return true
      }
    }
    return false
  }

  // ---- reading the words --------------------------------------------------------------------------------------

  /** Whether the reader's model is here, asked of Play services once and remembered once it is. */
  @Volatile private var ready = false

  private fun readerReady(): Boolean {
    if (ready) return true
    ready = try {
      Tasks.await(ModuleInstall.getClient(activity).areModulesAvailable(recognizer), 20, TimeUnit.SECONDS).areModulesAvailable()
    } catch (error: Throwable) {
      false
    }
    return ready
  }

  /** The reader's model, fetched by Play services where it is not here yet: waited for, on the reading thread. */
  private fun readyToRead() {
    if (readerReady()) return
    try {
      val request = ModuleInstallRequest.newBuilder().addApi(recognizer).build()
      Tasks.await(ModuleInstall.getClient(activity).installModules(request), 3, TimeUnit.MINUTES)
    } catch (error: Throwable) {
      Log.w(TAG, "reader not fetched", error)
      throw Said("The reader comes from Google Play services, and could not be fetched yet.")
    }
    ready = true
  }

  private fun recognised(image: InputImage): String = Tasks.await(recognizer.process(image)).text

  private fun read(call: MethodCall): Map<String, Any> {
    val path = call.argument<String>("path") ?: throw Said("Nothing to read.")
    val file = File(path)
    if (!file.isFile) throw Said("That file is not here.")
    readyToRead()
    if (call.argument<Boolean>("pdf") != true) return mapOf("pages" to listOf(recognised(InputImage.fromFilePath(activity, Uri.fromFile(file)))))
    val most = call.argument<Int>("most") ?: 60
    val words = ArrayList<String>()
    ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
      val renderer = PdfRenderer(fd)
      try {
        for (index in 0 until min(renderer.pageCount, most)) {
          val page = renderer.openPage(index)
          try {
            var said = ownWords(page) ?: ""
            if (said.isBlank()) {
              // No words of its own (a scan, a picture of a page): drawn about 2000 px on its long side, and read.
              val scale = READ_PX.toFloat() / max(page.width, page.height).coerceAtLeast(1)
              val bitmap = drawn(page, (page.width * scale).roundToInt().coerceAtLeast(1))
              said = try {
                recognised(InputImage.fromBitmap(bitmap, 0))
              } finally {
                bitmap.recycle()
              }
            }
            words.add(said)
          } finally {
            page.close()
          }
        }
      } finally {
        renderer.close()
      }
    }
    return mapOf("pages" to words)
  }

  /** A page's own words, where Android can say them (15 and later); null before. */
  private fun ownWords(page: PdfRenderer.Page): String? {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) return null
    return try {
      page.textContents.joinToString("\n") { it.text }
    } catch (error: Throwable) {
      null
    }
  }

  // ---- drawing a PDF ------------------------------------------------------------------------------------------

  private fun pdfOpen(path: String?): Map<String, Any> {
    val file = File(path ?: throw Said("This PDF can't be opened."))
    val renderer = try {
      PdfRenderer(ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY))
    } catch (error: SecurityException) {
      throw Said("This PDF has a password, and can't be opened here.")
    } catch (error: Throwable) {
      throw Said("This PDF can't be opened.")
    }
    val sizes = ArrayList<List<Int>>()
    for (index in 0 until renderer.pageCount) {
      val page = renderer.openPage(index)
      sizes.add(listOf(page.width, page.height))
      page.close()
    }
    val id = nextId++
    open[id] = renderer
    return mapOf("id" to id, "pages" to sizes)
  }

  private fun rendererOf(call: MethodCall): PdfRenderer = open[call.argument<Int>("id")] ?: throw Said("This PDF is closed.")

  /** A page drawn `width` pixels across on white, its long side at most [MAX_PX] and its pixels at most [MAX_PIXELS]. */
  private fun drawn(page: PdfRenderer.Page, width: Int): Bitmap {
    var w = width.coerceIn(1, MAX_PX)
    var h = (w.toFloat() * page.height / page.width.coerceAtLeast(1)).roundToInt().coerceAtLeast(1)
    if (h > MAX_PX || w.toLong() * h > MAX_PIXELS) {
      val scale = min(MAX_PX.toFloat() / h, kotlin.math.sqrt(MAX_PIXELS.toFloat() / (w.toFloat() * h)))
      w = (w * scale).roundToInt().coerceAtLeast(1)
      h = (h * scale).roundToInt().coerceAtLeast(1)
    }
    val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
    bitmap.eraseColor(Color.WHITE)
    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
    return bitmap
  }

  private fun pdfPage(call: MethodCall): Map<String, Any> {
    val renderer = rendererOf(call)
    val index = call.argument<Int>("page") ?: 0
    if (index !in 0 until renderer.pageCount) throw Said("There is no such page.")
    val page = renderer.openPage(index)
    val bitmap = try {
      drawn(page, call.argument<Int>("width") ?: 1080)
    } finally {
      page.close()
    }
    val pixels = ByteBuffer.allocate(bitmap.byteCount)
    bitmap.copyPixelsToBuffer(pixels)
    val answer = mapOf("width" to bitmap.width, "height" to bitmap.height, "pixels" to pixels.array())
    bitmap.recycle()
    return answer
  }

  private fun pdfText(call: MethodCall): String? {
    val renderer = rendererOf(call)
    val index = call.argument<Int>("page") ?: 0
    if (index !in 0 until renderer.pageCount) return null
    val page = renderer.openPage(index)
    return try {
      ownWords(page)
    } finally {
      page.close()
    }
  }

  private fun pdfFind(call: MethodCall): List<List<Float>>? {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) return null
    val renderer = rendererOf(call)
    val index = call.argument<Int>("page") ?: 0
    val query = call.argument<String>("query") ?: return emptyList()
    if (index !in 0 until renderer.pageCount || query.isBlank()) return emptyList()
    val page = renderer.openPage(index)
    return try {
      page.searchText(query).flatMap { match -> match.bounds.map { listOf(it.left, it.top, it.right, it.bottom) } }
    } catch (error: Throwable) {
      null
    } finally {
      page.close()
    }
  }

  private fun pdfClose(id: Int?): Any? {
    open.remove(id)?.close()
    return null
  }

  // ---- handing a file over ------------------------------------------------------------------------------------

  private fun hand(call: MethodCall, result: MethodChannel.Result, share: Boolean) {
    val path = call.argument<String>("path")
    val name = (call.argument<String>("name") ?: "File").replace(Regex("[/\\\\:*?\"<>|\\u0000-\\u001f]"), " ").trim().ifEmpty { "File" }
    if (path == null || !File(path).isFile) return result.error("gone", "That file is not on this phone.", null)
    Thread {
      val uri = try {
        val base = File(activity.cacheDir, "open")
        // What an earlier hand-over left: an hour is long enough for any app to have read it.
        base.listFiles()?.forEach { if (System.currentTimeMillis() - it.lastModified() > 3_600_000) it.deleteRecursively() }
        val dir = File(base, UUID.randomUUID().toString()).apply { mkdirs() }
        val copy = File(dir, name)
        File(path).copyTo(copy, overwrite = true)
        FileProvider.getUriForFile(activity, "${activity.packageName}.attachments", copy)
      } catch (error: Throwable) {
        Log.w(TAG, "file not handed over", error)
        null
      }
      activity.runOnUiThread {
        if (uri == null) return@runOnUiThread result.error("copy", "That file could not be handed over.", null)
        val extension = name.substringAfterLast('.', "").lowercase()
        val type = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "application/octet-stream"
        val intent = if (share) {
          Intent(Intent.ACTION_SEND).setType(type).putExtra(Intent.EXTRA_STREAM, uri)
        } else {
          Intent(Intent.ACTION_VIEW).setDataAndType(uri, type)
        }.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        try {
          activity.startActivity(Intent.createChooser(intent, if (share) "Share" else "Open with"))
          result.success(null)
        } catch (error: ActivityNotFoundException) {
          result.error("none", "No app on this phone opens that file.", null)
        }
      }
    }.start()
  }

  fun release() {
    drawing.execute {
      open.values.forEach { it.close() }
      open.clear()
    }
    drawing.shutdown()
    reading.shutdown()
  }

  companion object {
    const val CHANNEL = "ghost_md/documents"
    private const val TAG = "GhostDocuments"
    const val REQUEST_PICK = 4120
    const val REQUEST_SCAN = 4121

    /** The most a file may be to be added at all (lib/core/attachment_refs.dart `attachmentKeepLimit`). */
    private const val MAX_BYTES = 512L * 1024 * 1024

    /** The most pages one scan takes. */
    private const val PAGE_LIMIT = 50

    /** A page drawn for reading: about this many pixels on its long side. */
    private const val READ_PX = 2000

    /** The most a page is drawn at for the eye: on its long side, and in all. */
    private const val MAX_PX = 4096
    private const val MAX_PIXELS = 12_000_000L
  }
}

/** The files a person hands to another app, `cacheDir/open/` and nothing else (res/xml/ghost_attachment_paths.xml). */
class AttachmentFiles : FileProvider()
